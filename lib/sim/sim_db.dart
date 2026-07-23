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

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'nqe_sandbox.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async => _create(d),
      onUpgrade: (d, _, __) async => _create(d),
    );
  }

  Future<void> _create(Database d) async {
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
        fill_price REAL, created_at INTEGER, filled_at INTEGER)''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS sim_trades(
        id TEXT PRIMARY KEY, account_id TEXT, symbol TEXT, market INTEGER,
        mode INTEGER, side INTEGER, qty REAL, price REAL, fee REAL,
        realized_pnl REAL, ts INTEGER)''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS sim_watch(
        id TEXT PRIMARY KEY, account_id TEXT, symbol TEXT, market INTEGER,
        added_at INTEGER)''');
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
    await d.delete('sim_accounts', where: 'id=?', whereArgs: [id]);
    for (final t in ['sim_positions', 'sim_orders', 'sim_trades', 'sim_watch']) {
      await d.delete(t, where: 'account_id=?', whereArgs: [id]);
    }
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
      (await db).delete('sim_positions', where: 'id=?', whereArgs: [id]);

  // ---- orders ----
  Future<List<SimOrder>> orders(String accountId, {bool openOnly = false}) async {
    final rows = await (await db).query('sim_orders',
        where: openOnly ? 'account_id=? AND status=?' : 'account_id=?',
        whereArgs: openOnly ? [accountId, OrderStatus.open.index] : [accountId],
        orderBy: 'created_at DESC');
    return rows.map(SimOrder.fromMap).toList();
  }

  Future<void> upsertOrder(SimOrder o) async => (await db).insert(
      'sim_orders', o.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteOrder(String id) async =>
      (await db).delete('sim_orders', where: 'id=?', whereArgs: [id]);

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

  // ---- watchlist ----
  Future<List<SimWatch>> watch(String accountId) async {
    final rows = await (await db).query('sim_watch',
        where: 'account_id=?', whereArgs: [accountId], orderBy: 'added_at');
    return rows.map(SimWatch.fromMap).toList();
  }

  Future<void> upsertWatch(SimWatch w) async => (await db).insert(
      'sim_watch', w.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteWatch(String id) async =>
      (await db).delete('sim_watch', where: 'id=?', whereArgs: [id]);
}
