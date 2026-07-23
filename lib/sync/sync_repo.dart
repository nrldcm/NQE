// DB <-> sync bridge. Turns the sqflite ledger into a flat list of
// [SyncRecord]s (live rows + tombstones) that [SyncEngine] can merge, and
// applies a merged/remote set back into the DB with last-writer-wins conflict
// resolution.
//
// The merge math lives in sync_engine.dart (pure, unit-tested); this file only
// reads and writes the tables. It never touches models.dart — column maps are
// read straight from sqflite and written straight back, so a schema addition on
// a peer that this build doesn't know about still round-trips.
import 'package:sqflite/sqflite.dart';

import '../db/database.dart';
import 'sync_engine.dart';

class SyncRepo {
  SyncRepo._();
  static final SyncRepo instance = SyncRepo._();

  /// Snapshot the whole ledger as sync records: every live row of every
  /// syncable table (deleted:false) plus every tombstone (deleted:true).
  ///
  /// `table` is the sql table name, `data` is the raw row map, and `updatedAt`
  /// is the row's `updated_at`, falling back to `created_at` for rows written
  /// before change-tracking existed.
  Future<List<SyncRecord>> buildAll() async {
    final d = await LedgerDb.instance.db;
    final out = <SyncRecord>[];

    for (final table in kSyncTables) {
      final rows = await d.query(table);
      for (final row in rows) {
        out.add(SyncRecord(
          table: table,
          id: (row['id'] ?? '').toString(),
          updatedAt: _stamp(row),
          deleted: false,
          data: Map<String, Object?>.from(row),
        ));
      }
    }

    final tombs = await d.query('sync_tombstones');
    for (final t in tombs) {
      out.add(SyncRecord(
        table: (t['entity'] ?? '').toString(),
        id: (t['id'] ?? '').toString(),
        updatedAt: (t['updated_at'] ?? '').toString(),
        deleted: true,
        data: const <String, Object?>{},
      ));
    }

    return out;
  }

  /// Merge [remote] records into the local DB, atomically. For each record the
  /// local state (live row's `updated_at`, or a tombstone's, whichever exists)
  /// is compared via [SyncEngine.isNewer]; only records that win are applied:
  ///   * deleted   -> hard-delete the local row + upsert a tombstone.
  ///   * not deleted -> replace the row from `data` + drop any tombstone (restore).
  /// Returns the number of records actually applied. The whole batch runs in one
  /// transaction, so a failure rolls back to the pre-sync state.
  /// [asFollower] true means this device is a passive mirror of the peer (the
  /// desktop is always a mirror; the phone is one WHILE a desktop is connected,
  /// because Desktop Mode gates the phone so the desktop is the sole editor).
  /// A follower applies the peer's ledger rows VERBATIM — clock-independent —
  /// so a genuine edit/delete can't be silently dropped or resurrected by
  /// wall-clock skew between the two devices (the same fix the sandbox got).
  Future<int> applyRemote(List<SyncRecord> remote,
      {bool asFollower = false}) async {
    if (remote.isEmpty) return 0;
    final d = await LedgerDb.instance.db;

    // Parents before children so replacing a row never violates the
    // account_id foreign key while its account is still queued in this batch.
    final ordered = [...remote]..sort(
        (a, b) => _priority(a.table).compareTo(_priority(b.table)));

    var applied = 0;
    await d.transaction((txn) async {
      for (final r in ordered) {
        // Ignore records for tables we don't sync (defensive against a peer
        // sending an unknown/renamed table — never write to arbitrary tables).
        if (!kSyncTables.contains(r.table)) continue;

        if (!asFollower) {
          final local = await _localState(txn, r.table, r.id);
          if (local != null && !SyncEngine.isNewer(r, local)) continue;
        }

        if (r.deleted) {
          await txn.delete(r.table, where: 'id = ?', whereArgs: [r.id]);
          await txn.insert(
            'sync_tombstones',
            {'entity': r.table, 'id': r.id, 'updated_at': r.updatedAt},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          final data = Map<String, Object?>.from(r.data)
            ..['id'] = r.id
            ..['updated_at'] = r.updatedAt;
          await txn.insert(r.table, data,
              conflictAlgorithm: ConflictAlgorithm.replace);
          await txn.delete('sync_tombstones',
              where: 'entity = ? AND id = ?', whereArgs: [r.table, r.id]);
        }
        applied++;
      }
    });

    return applied;
  }

  /// Current local record for (table,id): the live row if present, else its
  /// tombstone, else null. Read inside [txn] so conflict checks see a
  /// consistent snapshot within [applyRemote]'s transaction.
  Future<SyncRecord?> _localState(
      DatabaseExecutor txn, String table, String id) async {
    final rows =
        await txn.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty) {
      final row = rows.first;
      return SyncRecord(
        table: table,
        id: id,
        updatedAt: _stamp(row),
        deleted: false,
        data: Map<String, Object?>.from(row),
      );
    }
    final tomb = await txn.query('sync_tombstones',
        where: 'entity = ? AND id = ?', whereArgs: [table, id], limit: 1);
    if (tomb.isNotEmpty) {
      return SyncRecord(
        table: table,
        id: id,
        updatedAt: (tomb.first['updated_at'] ?? '').toString(),
        deleted: true,
        data: const <String, Object?>{},
      );
    }
    return null;
  }

  /// Change stamp for a live row: `updated_at`, falling back to `created_at`.
  static String _stamp(Map<String, Object?> row) {
    final u = row['updated_at'];
    if (u != null && u.toString().isNotEmpty) return u.toString();
    return (row['created_at'] ?? '').toString();
  }

  /// Foreign-key apply order: accounts first, then their children.
  static int _priority(String table) => table == 'accounts' ? 0 : 1;
}
