// SQLite persistence via sqflite. SQLite is ACID/transactional, so a crash or
// kill mid-write can never leave the ledger half-updated — the core defence
// against corruption. Imports run inside a single transaction: either the whole
// snapshot is applied or nothing is.
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';

class LedgerDb {
  LedgerDb._();
  static final LedgerDb instance = LedgerDb._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'nqe_ledger.db');
    return openDatabase(
      path,
      version: kSchemaVersion,
      onConfigure: (d) async {
        await d.execute('PRAGMA foreign_keys = ON');
        // WAL improves crash-resilience of writes.
        await d.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: (d, _) async => _createSchema(d),
      onUpgrade: (d, _, __) async => _createSchema(d),
    );
  }

  Future<void> _createSchema(Database d) async {
    final batch = d.batch();
    batch.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, broker TEXT NOT NULL DEFAULT '',
        currency TEXT NOT NULL DEFAULT 'PHP', kind TEXT NOT NULL DEFAULT 'trading',
        starting_capital REAL NOT NULL DEFAULT 0, fx_to_php REAL NOT NULL DEFAULT 1,
        color INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS cashflows (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        date TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL DEFAULT 0,
        fx_rate REAL NOT NULL DEFAULT 1, remarks TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS trades (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        date TEXT NOT NULL, stock TEXT NOT NULL DEFAULT '', shares REAL NOT NULL DEFAULT 0,
        buy_price REAL NOT NULL DEFAULT 0, sell_price REAL, fees REAL NOT NULL DEFAULT 0,
        holding_period TEXT NOT NULL DEFAULT '', setup TEXT NOT NULL DEFAULT '',
        remarks TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'closed',
        created_at TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS dividends (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        date TEXT NOT NULL, stock TEXT NOT NULL DEFAULT '', shares REAL NOT NULL DEFAULT 0,
        div_rate REAL NOT NULL DEFAULT 0, net_amount REAL NOT NULL DEFAULT 0,
        remarks TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS holdings (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        stock TEXT NOT NULL DEFAULT '', goal_shares REAL NOT NULL DEFAULT 0,
        current_shares REAL NOT NULL DEFAULT 0, avg_price REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )''');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS ix_cf_acct ON cashflows(account_id, date)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS ix_tr_acct ON trades(account_id, date)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS ix_dv_acct ON dividends(account_id, date)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS ix_hd_acct ON holdings(account_id)');
    await batch.commit(noResult: true);
  }

  // ---- Accounts -------------------------------------------------------------
  Future<List<Account>> accounts({bool includeArchived = false}) async {
    final d = await db;
    final rows = await d.query('accounts',
        where: includeArchived ? null : 'archived = 0',
        orderBy: 'sort_order, created_at');
    return rows.map(Account.fromMap).toList();
  }

  Future<void> upsertAccount(Account a) async {
    final d = await db;
    await d.insert('accounts', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteAccount(String id) async {
    final d = await db;
    await d.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Cashflows ------------------------------------------------------------
  Future<List<Cashflow>> cashflows(String accountId) async {
    final d = await db;
    final rows = await d.query('cashflows',
        where: 'account_id = ?', whereArgs: [accountId], orderBy: 'date, created_at');
    return rows.map(Cashflow.fromMap).toList();
  }

  Future<void> upsertCashflow(Cashflow c) async {
    final d = await db;
    await d.insert('cashflows', c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCashflow(String id) async {
    final d = await db;
    await d.delete('cashflows', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Trades ---------------------------------------------------------------
  Future<List<Trade>> trades(String accountId) async {
    final d = await db;
    final rows = await d.query('trades',
        where: 'account_id = ?', whereArgs: [accountId], orderBy: 'date, created_at');
    return rows.map(Trade.fromMap).toList();
  }

  Future<List<Trade>> allTrades() async {
    final d = await db;
    final rows = await d.query('trades', orderBy: 'date, created_at');
    return rows.map(Trade.fromMap).toList();
  }

  Future<void> upsertTrade(Trade t) async {
    final d = await db;
    await d.insert('trades', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTrade(String id) async {
    final d = await db;
    await d.delete('trades', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Dividends ------------------------------------------------------------
  Future<List<Dividend>> dividends(String accountId) async {
    final d = await db;
    final rows = await d.query('dividends',
        where: 'account_id = ?', whereArgs: [accountId], orderBy: 'date, created_at');
    return rows.map(Dividend.fromMap).toList();
  }

  Future<void> upsertDividend(Dividend x) async {
    final d = await db;
    await d.insert('dividends', x.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDividend(String id) async {
    final d = await db;
    await d.delete('dividends', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Holdings -------------------------------------------------------------
  Future<List<Holding>> holdings(String accountId) async {
    final d = await db;
    final rows = await d.query('holdings',
        where: 'account_id = ?', whereArgs: [accountId], orderBy: 'stock');
    return rows.map(Holding.fromMap).toList();
  }

  Future<void> upsertHolding(Holding h) async {
    final d = await db;
    await d.insert('holdings', h.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteHolding(String id) async {
    final d = await db;
    await d.delete('holdings', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Snapshot / import ----------------------------------------------------
  Future<LedgerSnapshot> snapshot() async {
    final d = await db;
    final acc = (await d.query('accounts')).map(Account.fromMap).toList();
    final cf = (await d.query('cashflows')).map(Cashflow.fromMap).toList();
    final tr = (await d.query('trades')).map(Trade.fromMap).toList();
    final dv = (await d.query('dividends')).map(Dividend.fromMap).toList();
    final hd = (await d.query('holdings')).map(Holding.fromMap).toList();
    return LedgerSnapshot(
      schema: kSchemaVersion,
      exportedAt: DateTime.now().toUtc().toIso8601String(),
      accounts: acc,
      cashflows: cf,
      trades: tr,
      dividends: dv,
      holdings: hd,
    );
  }

  /// Replace the entire ledger from an imported snapshot, atomically.
  /// If anything throws, the transaction rolls back and existing data is intact.
  Future<void> replaceFromSnapshot(LedgerSnapshot s) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('holdings');
      await txn.delete('dividends');
      await txn.delete('trades');
      await txn.delete('cashflows');
      await txn.delete('accounts');
      for (final a in s.accounts) {
        await txn.insert('accounts', a.toMap());
      }
      for (final c in s.cashflows) {
        await txn.insert('cashflows', c.toMap());
      }
      for (final t in s.trades) {
        await txn.insert('trades', t.toMap());
      }
      for (final x in s.dividends) {
        await txn.insert('dividends', x.toMap());
      }
      for (final h in s.holdings) {
        await txn.insert('holdings', h.toMap());
      }
    });
  }

  Future<bool> isEmpty() async {
    final d = await db;
    final r = await d.rawQuery('SELECT COUNT(*) AS n FROM accounts');
    return (r.first['n'] as int? ?? 0) == 0;
  }
}
