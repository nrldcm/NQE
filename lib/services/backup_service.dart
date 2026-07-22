// Export / import of the whole ledger as an encrypted .nqe backup.
//
// Export flow:  DB snapshot -> AES-GCM encrypt -> write temp file -> system
// share sheet. From there the user can tap "Save to Drive" (free, no account
// setup) or send it anywhere. Import validates & decrypts before atomically
// replacing the ledger, so a bad file can never corrupt existing data.
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

  Future<File> _writeTemp(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(dir.path, 'NQE_backup_$stamp.$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Produce the encrypted backup and open the share sheet (Drive, etc.).
  Future<void> exportAndShare() async {
    final snap = await LedgerDb.instance.snapshot();
    final bytes = await CryptoService.instance.encryptJson(snap.toJson());
    final file = await _writeTemp(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/octet-stream')],
      subject: 'NQE Ledger Backup',
      text: 'NQE encrypted ledger backup (${DateFormat.yMMMd().format(DateTime.now())}).',
    );
  }

  /// Write the encrypted backup to app documents and return its path
  /// (used for a local "silent" auto-backup).
  Future<String> exportToAppFile() async {
    final snap = await LedgerDb.instance.snapshot();
    final bytes = await CryptoService.instance.encryptJson(snap.toJson());
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'nqe_autobackup.$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Let the user pick a .nqe file, then decrypt, validate and restore it.
  /// Returns null if the user cancelled.
  Future<ImportResult?> pickAndImport() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final f = picked.files.single;

    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) {
      bytes = await File(f.path!).readAsBytes();
    }
    if (bytes == null) {
      throw CryptoException('Could not read the selected file.');
    }
    return importBytes(bytes);
  }

  Future<ImportResult> importBytes(Uint8List bytes) async {
    final json = await CryptoService.instance.decryptJson(bytes);
    final snap = LedgerSnapshot.fromJson(json);
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
