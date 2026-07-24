// Export / import of the whole ledger as an encrypted .nqe backup.
//
// Export flow:  DB snapshot -> AES-GCM encrypt -> write temp file -> system
// share sheet (Save to Drive, etc.). Import validates & decrypts before
// atomically replacing the ledger, so a bad file can never corrupt existing
// data. Imports are size-capped and type-guarded against malformed/oversized
// files (DoS / crash hardening).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database.dart';
import '../models.dart';
import 'auth_service.dart';
import 'crypto_service.dart';

class ImportResult {
  final int accounts, cashflows, trades, dividends, holdings;
  ImportResult(this.accounts, this.cashflows, this.trades, this.dividends,
      this.holdings);
}

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const String ext = 'nqe';

  /// Hard cap on import size — a valid backup is tiny; anything larger is
  /// rejected before it is read into memory (OOM / DoS guard).
  static const int maxImportBytes = 16 * 1024 * 1024; // 16 MB

  Future<File> _writeTemp(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(dir.path, 'NQE_backup_$stamp.$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Produce the encrypted backup and open the share sheet (Drive, etc.).
  /// Best-effort deletes the temp file afterwards.
  Future<void> exportAndShare({String passphrase = ''}) async {
    // TODO(web): file share/download not wired up on web yet (uses dart:io temp
    // files + the native share sheet). The web build is a thin mirror client, so
    // fail with a clear message rather than crashing.
    if (kIsWeb) {
      throw CryptoException('Backup export is not available on web yet.');
    }
    final snap = await LedgerDb.instance.snapshot();
    final bytes = await CryptoService.instance
        .encryptJson(snap.toJson(), passphrase: passphrase);
    final file = await _writeTemp(bytes);
    // The share sheet backgrounds the app; suppress the resume-time relock so
    // returning doesn't pop a PIN/fingerprint prompt over the flow.
    AuthService.suppressAutoLock = true;
    try {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'NQE Ledger Backup',
        text:
            'NQE encrypted ledger backup (${DateFormat.yMMMd().format(DateTime.now())}).',
      );
    } finally {
      _clearAutoLockSuppressSoon();
      // Don't leave encrypted copies lingering in the cache dir.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {/* best effort */}
    }
  }

  /// Backstop: clear the auto-lock suppress a moment after a backgrounding
  /// backup op returns, in case no resume event fired to consume the one-shot
  /// (so the guard can never get stuck on and disable locking).
  void _clearAutoLockSuppressSoon() {
    Future.delayed(const Duration(seconds: 2),
        () => AuthService.suppressAutoLock = false);
  }

  /// Let the user pick a file and return its bytes (size-capped). Null if the
  /// user cancelled. Lets the caller decide about passphrases before importing.
  Future<Uint8List?> pickFileBytes() async {
    // TODO(web): file-picker restore not wired up on web yet (uses a dart:io
    // File path). Fail with a clear message rather than crashing.
    if (kIsWeb) {
      throw CryptoException('Backup restore is not available on web yet.');
    }
    // The system file picker backgrounds the app; suppress the resume-time
    // relock so returning with a file doesn't interrupt the restore with a
    // PIN / fingerprint prompt.
    AuthService.suppressAutoLock = true;
    FilePickerResult? picked;
    try {
      // withData:false so the whole file isn't slurped into memory before we can
      // reject an oversized pick (OOM/DoS guard).
      picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
    } finally {
      _clearAutoLockSuppressSoon();
    }
    if (picked == null || picked.files.isEmpty) return null;
    final f = picked.files.single;

    if (f.size > maxImportBytes) {
      throw CryptoException('That file is too large to be an NQE backup.');
    }
    final path = f.path;
    if (path == null) {
      // Fallback (e.g. platforms without a path): use in-memory bytes if small.
      final b = f.bytes;
      if (b == null) {
        throw CryptoException('Could not read the selected file.');
      }
      if (b.length > maxImportBytes) {
        throw CryptoException('That file is too large to be an NQE backup.');
      }
      return b;
    }
    final file = File(path);
    if (await file.length() > maxImportBytes) {
      throw CryptoException('That file is too large to be an NQE backup.');
    }
    return file.readAsBytes();
  }

  /// True if the given file needs a passphrase (used to prompt on import).
  bool needsPassphrase(Uint8List bytes) =>
      CryptoService.instance.isPassphraseProtected(bytes);

  Future<ImportResult> importBytes(Uint8List bytes,
      {String passphrase = ''}) async {
    if (bytes.length > maxImportBytes) {
      throw CryptoException('That file is too large to be an NQE backup.');
    }
    final json =
        await CryptoService.instance.decryptJson(bytes, passphrase: passphrase);

    LedgerSnapshot snap;
    try {
      snap = LedgerSnapshot.fromJson(json);
    } catch (_) {
      // Decrypted fine but the structure is not a valid ledger.
      throw CryptoException('Backup content is not a valid NQE ledger.');
    }
    if (snap.accounts.isEmpty &&
        snap.trades.isEmpty &&
        snap.cashflows.isEmpty &&
        snap.dividends.isEmpty) {
      throw CryptoException('Backup contains no ledger data.');
    }
    // Atomic replace — throws & rolls back on any problem.
    await LedgerDb.instance.replaceFromSnapshot(snap);
    return ImportResult(
      snap.accounts.length,
      snap.cashflows.length,
      snap.trades.length,
      snap.dividends.length,
      snap.holdings.length,
    );
  }
}
