// Export / import of the whole ledger as an encrypted .nqe backup.
//
// Export flow:  DB snapshot -> AES-GCM encrypt -> write temp file -> system
// share sheet (Save to Drive, etc.). Import validates & decrypts before
// atomically replacing the ledger, so a bad file can never corrupt existing
// data. Imports are size-capped and type-guarded against malformed/oversized
// files (DoS / crash hardening).
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database.dart';
import '../models.dart';
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
    final snap = await LedgerDb.instance.snapshot();
    final bytes = await CryptoService.instance
        .encryptJson(snap.toJson(), passphrase: passphrase);
    final file = await _writeTemp(bytes);
    try {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'NQE Ledger Backup',
        text:
            'NQE encrypted ledger backup (${DateFormat.yMMMd().format(DateTime.now())}).',
      );
    } finally {
      // Don't leave encrypted copies lingering in the cache dir.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {/* best effort */}
    }
  }

  /// Let the user pick a file and return its bytes (size-capped). Null if the
  /// user cancelled. Lets the caller decide about passphrases before importing.
  Future<Uint8List?> pickFileBytes() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final f = picked.files.single;

    if (f.size > maxImportBytes) {
      throw CryptoException('That file is too large to be an NQE backup.');
    }
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) {
      final file = File(f.path!);
      if (await file.length() > maxImportBytes) {
        throw CryptoException('That file is too large to be an NQE backup.');
      }
      bytes = await file.readAsBytes();
    }
    if (bytes == null) {
      throw CryptoException('Could not read the selected file.');
    }
    return bytes;
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
