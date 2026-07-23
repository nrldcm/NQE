// Isolated persistence for the Sandbox — its OWN SQLite file so simulation data
// can never mix with the real fund ledger. Works on mobile (sqflite) and
// desktop (sqflite_common_ffi via the global databaseFactory set in main()).
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'sim_models.dart';

class SimDb {
  SimDb._();
  static final SimDb instance = SimDb._();

  /// Test-only: a SimDb backed by an already-open database, so a test can spin
  /// up two isolated "devices" and exercise the real sync round-trip.
  SimDb.forDb(Database db) : _db = db;

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'nqe_sandbox.db');
    return openAtPath(path);
  }

  /// Open (creating / upgrading) the sandbox schema at [path]. Public so tests
  /// can create isolated databases; production goes through [_open].
  static Future<Database> openAtPath(String path) {
    return openDatabase(
      path,
      version: 2,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async => _create(d),
      onUpgrade: (d, _, __) async {
        await _create(d);
        // v2: change-tracking columns + tombstones for cross-device sync.
        try {
          await d.execute('ALTER TABLE sim_orders ADD COLUMN updated_at INTEGER');
        } catch (_) {/* already present */}
      },
    );
  }

  static Future<void> _create(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS sim_accounts(
        id TEXT PRIMARY KEY, name TEXT, currency TEXT,
        starting_cash REAL, cash REAL, realized_pnl REAL,
        margin_enabled INTEGER, max_leverage REAL,
        created_at INTEGER, updated_at INTEGER)''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS sim_positions(
        id TEXT PRIMARY KEY, account_id TEXT, symbol TEXT, market INTEGER,
        mode INTEGER, side INTEGER, qty REAL, avg_price REAL, leverage REAL,
        margin_used REAL, opened_at INTEGER, updated_at INTEGER)''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS sim_orders(
        id TEXT PRIMARY KEY, account_id TEXT, symbol TEXT, market INTEGER,
        mode INTEGER, side INTEGER, type INTEGER, qty REAL, leverage REAL,
        limit_price REAL, stop_price REAL, reduce_only INTEGER, status INTEGER,
        fill_price REAL, created_at INTEGER, filled_at INTEGER,
        updated_at INTEGER)''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS sim_trades(
        id TEXT PRIMARY KEY, account_id TEXT, symbol TEXT, market INTEGER,
        mode INTEGER, side INTEGER, qty REAL, price REAL, fee REAL,
        realized_pnl REAL, ts INTEGER)''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS sim_watch(
        id TEXT PRIMARY KEY, account_id TEXT, symbol TEXT, market INTEGER,
        added_at INTEGER)''');
    // Deletions are recorded so a closed position / cancelled order propagates
    // across paired devices (last-writer-wins with the live rows).
    await d.execute('''
      CREATE TABLE IF NOT EXISTS sim_tombstones(
        entity TEXT, id TEXT, updated_at INTEGER,
        PRIMARY KEY(entity, id))''');
  }

  // ---- accounts ----
  Future<List<SimAccount>> accounts() async {
    final rows = await (await db).query('sim_accounts', orderBy: 'created_at');
    return rows.map(SimAccount.fromMap).toList();
  }

  Future<void> upsertAccount(SimAccount a) async =>
      (await db).insert('sim_accounts', a.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteAccount(String id) async {
    final d = await db;
    final ts = DateTime.now().millisecondsSinceEpoch;
    // Tombstone every deleted row so the deletion propagates across devices and
    // a peer holding the old rows can't resurrect them on the next sync.
    Future<void> tomb(String entity, String rowId) => d.insert(
        'sim_tombstones',
        {'entity': entity, 'id': rowId, 'updated_at': ts},
        conflictAlgorithm: ConflictAlgorithm.replace);
    for (final t in ['sim_positions', 'sim_orders', 'sim_trades', 'sim_watch']) {
      final rows = await d.query(t,
          columns: ['id'], where: 'account_id=?', whereArgs: [id]);
      for (final r in rows) {
        await tomb(t, (r['id'] ?? '').toString());
      }
      await d.delete(t, where: 'account_id=?', whereArgs: [id]);
    }
    await d.delete('sim_accounts', where: 'id=?', whereArgs: [id]);
    await tomb('sim_accounts', id);
  }

  // ---- positions ----
  Future<List<SimPosition>> positions(String accountId) async {
    final rows = await (await db).query('sim_positions',
        where: 'account_id=?', whereArgs: [accountId]);
    return rows.map(SimPosition.fromMap).toList();
  }

  Future<void> upsertPosition(SimPosition x) async => (await db).insert(
      'sim_positions', x.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deletePosition(String id) async =>
      _deleteWithTomb('sim_positions', id);

  // ---- orders ----
  Future<List<SimOrder>> orders(String accountId, {bool openOnly = false}) async {
    final rows = await (await db).query('sim_orders',
        where: openOnly ? 'account_id=? AND status=?' : 'account_id=?',
        whereArgs: openOnly ? [accountId, OrderStatus.open.index] : [accountId],
        orderBy: 'created_at DESC');
    return rows.map(SimOrder.fromMap).toList();
  }

  Future<void> upsertOrder(SimOrder o) async {
    final m = o.toMap()..['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await (await db)
        .insert('sim_orders', m, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteOrder(String id) async => _deleteWithTomb('sim_orders', id);

  // ---- trades ----
  Future<List<SimTrade>> trades(String accountId, {int limit = 200}) async {
    final rows = await (await db).query('sim_trades',
        where: 'account_id=?',
        whereArgs: [accountId],
        orderBy: 'ts DESC',
        limit: limit);
    return rows.map(SimTrade.fromMap).toList();
  }

  Future<void> insertTrade(SimTrade t) async => (await db).insert(
      'sim_trades', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  /// Delete an account's whole trade blotter (used on reset), tombstoning each
  /// row so the clear also propagates to a paired device.
  Future<void> clearTrades(String accountId) async {
    final d = await db;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rows = await d.query('sim_trades',
        columns: ['id'], where: 'account_id=?', whereArgs: [accountId]);
    for (final r in rows) {
      await d.insert(
          'sim_tombstones',
          {'entity': 'sim_trades', 'id': (r['id'] ?? '').toString(), 'updated_at': ts},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await d.delete('sim_trades', where: 'account_id=?', whereArgs: [accountId]);
  }

  /// Delete EVERY order for an account (open + filled/closed history), each
  /// tombstoned so the clear propagates to the paired device on next sync.
  Future<void> clearOrders(String accountId) async {
    final d = await db;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rows = await d.query('sim_orders',
        columns: ['id'], where: 'account_id=?', whereArgs: [accountId]);
    for (final r in rows) {
      await d.insert(
          'sim_tombstones',
          {'entity': 'sim_orders', 'id': (r['id'] ?? '').toString(), 'updated_at': ts},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await d.delete('sim_orders', where: 'account_id=?', whereArgs: [accountId]);
  }

  // ---- watchlist ----
  Future<List<SimWatch>> watch(String accountId) async {
    final rows = await (await db).query('sim_watch',
        where: 'account_id=?', whereArgs: [accountId], orderBy: 'added_at');
    return rows.map(SimWatch.fromMap).toList();
  }

  Future<void> upsertWatch(SimWatch w) async => (await db).insert(
      'sim_watch', w.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteWatch(String id) async => _deleteWithTomb('sim_watch', id);

  // ---- sync support (tombstones + raw access) ----
  Future<void> _deleteWithTomb(String table, String id) async {
    final d = await db;
    await d.delete(table, where: 'id=?', whereArgs: [id]);
    await d.insert(
        'sim_tombstones',
        {'entity': table, 'id': id, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> rawRows(String table) async =>
      (await db).query(table);

  Future<List<Map<String, Object?>>> tombstoneRows() async =>
      (await db).query('sim_tombstones');
}
