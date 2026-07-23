// Cross-device sync for the Sandbox. Turns the isolated sim SQLite tables into
// [SyncRecord]s (live rows + tombstones) that ride the SAME encrypted channel
// as the ledger, and applies remote sim records back with last-writer-wins.
//
// Kept fully separate from the ledger: buildAll only reads sim_* tables, and
// applyRemote only writes sim_* tables (it ignores every ledger record, exactly
// as SyncRepo ignores every sim record). Virtual data never mixes with funds.
import 'package:sqflite/sqflite.dart';

import '../sync/sync_engine.dart';
import 'sim_db.dart';

/// The sandbox tables that participate in sync.
const List<String> kSimTables = [
  'sim_accounts',
  'sim_positions',
  'sim_orders',
  'sim_trades',
  'sim_watch',
  'sim_intents',
];

/// The change-stamp column for each table (integer ms).
const Map<String, String> _stampCol = {
  'sim_accounts': 'updated_at',
  'sim_positions': 'updated_at',
  'sim_orders': 'updated_at',
  'sim_trades': 'ts',
  'sim_watch': 'added_at',
  'sim_intents': 'updated_at',
};

class SimSyncRepo {
  SimSyncRepo._();
  static final SimSyncRepo instance = SimSyncRepo._();

  int _stampOf(String table, Map<String, Object?> row) {
    final col = _stampCol[table] ?? 'updated_at';
    final v = row[col] ?? row['created_at'] ?? 0;
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  /// Snapshot all sandbox rows + tombstones as sync records (stamp = ms string).
  /// [db] defaults to the app's singleton; tests pass an isolated instance.
  Future<List<SyncRecord>> buildAll({SimDb? db}) async {
    final sdb = db ?? SimDb.instance;
    final out = <SyncRecord>[];
    for (final table in kSimTables) {
      final rows = await sdb.rawRows(table);
      for (final row in rows) {
        out.add(SyncRecord(
          table: table,
          id: (row['id'] ?? '').toString(),
          updatedAt: _stampOf(table, row).toString(),
          deleted: false,
          data: Map<String, Object?>.from(row),
        ));
      }
    }
    for (final t in await sdb.tombstoneRows()) {
      out.add(SyncRecord(
        table: (t['entity'] ?? '').toString(),
        id: (t['id'] ?? '').toString(),
        updatedAt: (t['updated_at'] ?? 0).toString(),
        deleted: true,
        data: const {},
      ));
    }
    return out;
  }

  /// Apply remote records that belong to sandbox tables. Returns how many were
  /// actually applied (0 → nothing sim-related changed). Ledger records are
  /// ignored here.
  ///
  /// The MOBILE is the single source of truth: it runs the engine and OWNS the
  /// positions/orders/trades. Because the two devices stamp rows with their own
  /// wall clocks, a plain last-writer-wins merge silently drops genuine updates
  /// whenever the clocks are skewed. So the merge is role-aware:
  ///
  ///  * [asFollower] == true (a paired desktop mirroring the phone): apply the
  ///    authority's rows VERBATIM, clock-independent — the mirror can never
  ///    drift or reject a real update. This is what makes phone→desktop reliable.
  ///  * [asFollower] == false (the phone authority): never let a mirror's stale
  ///    copy clobber engine-owned state. Accept the shared account row via LWW
  ///    (so a desktop wallet top-up still lands and the phone re-pushes it),
  ///    accept brand-NEW rows the phone doesn't have yet (an order the desktop
  ///    placed/forwarded), and accept a mirror's cancel of a still-open order.
  Future<int> applyRemote(List<SyncRecord> remote,
      {bool asFollower = false, SimDb? db}) async {
    final sim = remote.where((r) => kSimTables.contains(r.table)).toList();
    if (sim.isEmpty) return 0;
    final d = await (db ?? SimDb.instance).db;

    // Accounts before their children so a replaced child never dangles.
    sim.sort((a, b) => _priority(a.table).compareTo(_priority(b.table)));

    var applied = 0;
    await d.transaction((txn) async {
      for (final r in sim) {
        final remoteStamp = int.tryParse(r.updatedAt) ?? 0;

        if (!asFollower) {
          // ---- authority (phone) acceptance gate ----
          final localStamp = await _localStamp(txn, r.table, r.id);
          final isAccount = r.table == 'sim_accounts';
          if (isAccount) {
            // Shared row → last-writer-wins.
            if (localStamp != null && remoteStamp <= localStamp) continue;
          } else if (r.deleted) {
            // Mirror-originated deletes the authority honors: a cancel of a
            // still-open order, and a watchlist removal (both user-owned).
            // Never delete filled history / positions / trades / the account.
            if (r.table == 'sim_watch') {
              // ok — user-owned watchlist item, honor the removal
            } else if (r.table == 'sim_orders') {
              final rows = await txn.query('sim_orders',
                  columns: ['status'],
                  where: 'id=?',
                  whereArgs: [r.id],
                  limit: 1);
              final open = rows.isNotEmpty && (rows.first['status'] == 0);
              if (!open) continue;
            } else {
              continue;
            }
          } else {
            // A live non-account row is accepted only if brand new here (a
            // forwarded order). Otherwise the phone already owns it — ignore.
            if (localStamp != null) continue;
          }
        }
        // (Follower path applies everything verbatim — no gate.)

        if (r.deleted) {
          await txn.delete(r.table, where: 'id=?', whereArgs: [r.id]);
          await txn.insert(
              'sim_tombstones',
              {'entity': r.table, 'id': r.id, 'updated_at': remoteStamp},
              conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          final data = Map<String, Object?>.from(r.data)..['id'] = r.id;
          await txn.insert(r.table, data,
              conflictAlgorithm: ConflictAlgorithm.replace);
          await txn.delete('sim_tombstones',
              where: 'entity=? AND id=?', whereArgs: [r.table, r.id]);
        }
        applied++;
      }
    });
    return applied;
  }

  /// Newest stamp known locally for (table,id): the live row's, or a tombstone's.
  Future<int?> _localStamp(
      DatabaseExecutor txn, String table, String id) async {
    final rows = await txn.query(table, where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty) return _stampOf(table, rows.first);
    final tomb = await txn.query('sim_tombstones',
        where: 'entity=? AND id=?', whereArgs: [table, id], limit: 1);
    if (tomb.isNotEmpty) {
      final v = tomb.first['updated_at'] ?? 0;
      return v is int ? v : int.tryParse('$v') ?? 0;
    }
    return null;
  }

  static int _priority(String table) => table == 'sim_accounts' ? 0 : 1;
}
