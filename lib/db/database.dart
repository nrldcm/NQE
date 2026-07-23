// SQLite persistence via sqflite. SQLite is ACID/transactional, so a crash or
// kill mid-write can never leave the ledger half-updated — the core defence
// against corruption. Imports run inside a single transaction: either the whole
// snapshot is applied or nothing is.
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';

/// sqflite on-disk schema version. Bumped to 3 for LAN sync change-tracking
/// (nullable `updated_at` columns + `sync_tombstones`). Kept local to the DB
/// layer so the export/import model version (`kSchemaVersion`) is untouched.
const int _kDbSchemaVersion = 3;

/// Tables that participate in LAN sync (each has an `id` PK and an `updated_at`
/// change marker, and generates a tombstone on delete). `api_keys` is device-
/// only and deliberately excluded.
const List<String> kSyncTables = <String>[
  'accounts',
  'cashflows',
  'trades',
  'dividends',
  'holdings',
];

class LedgerDb {
  LedgerDb._();
  static final LedgerDb instance = LedgerDb._();

  /// Desktop-mirror flag: when true the ledger lives in memory ONLY, so the
  /// desktop persists nothing to disk and always gets/sends its data through
  /// the phone (the single source of truth). Set once at desktop startup,
  /// before the first DB access.
  static bool ephemeral = false;

  Database? _db;

  /// Change marker written on every upsert / delete. ISO-8601 UTC so it sorts
  /// lexicographically (matches [SyncRecord.updatedAt] semantics).
  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    // Desktop mirror: a scratch ledger file WIPED on every launch, so it starts
    // empty and is filled purely by what the phone syncs over — nothing
    // persists. (A temp file rather than ':memory:', whose onCreate is
    // unreliable with sqflite migrations.)
    String path;
    if (ephemeral) {
      final tmp = await getTemporaryDirectory();
      path = p.join(tmp.path, 'nqe_ledger_mirror.db');
      try {
        await deleteDatabase(path);
      } catch (_) {/* first run — nothing to delete */}
    } else {
      path = p.join(
          (await getApplicationDocumentsDirectory()).path, 'nqe_ledger.db');
    }
    return openDatabase(
      path,
      version: _kDbSchemaVersion,
      onConfigure: (d) async {
        // Only no-result PRAGMAs here — running a *querying* PRAGMA (e.g.
        // journal_mode, which returns a row) inside onConfigure can deadlock
        // sqflite and hang the app on the loading screen. WAL is already the
        // default journal mode on Android, so we don't need to set it.
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (d, _) async => _createSchema(d),
      onUpgrade: (d, _, __) async {
        // Existing tables already exist (IF NOT EXISTS is a no-op for them);
        // this creates any newly-added tables (e.g. sync_tombstones) ...
        await _createSchema(d);
        // ... and back-fills the nullable change-tracking column that CREATE
        // can't add to a pre-existing table.
        await _addUpdatedAtColumns(d);
      },
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
        archived INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
        updated_at TEXT
      )''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS cashflows (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        date TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL DEFAULT 0,
        fx_rate REAL NOT NULL DEFAULT 1, remarks TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL, updated_at TEXT
      )''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS trades (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        date TEXT NOT NULL, stock TEXT NOT NULL DEFAULT '', shares REAL NOT NULL DEFAULT 0,
        buy_price REAL NOT NULL DEFAULT 0, sell_price REAL, fees REAL NOT NULL DEFAULT 0,
        holding_period TEXT NOT NULL DEFAULT '', setup TEXT NOT NULL DEFAULT '',
        remarks TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'closed',
        created_at TEXT NOT NULL, updated_at TEXT
      )''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS dividends (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        date TEXT NOT NULL, stock TEXT NOT NULL DEFAULT '', shares REAL NOT NULL DEFAULT 0,
        div_rate REAL NOT NULL DEFAULT 0, net_amount REAL NOT NULL DEFAULT 0,
        remarks TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT
      )''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS holdings (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        stock TEXT NOT NULL DEFAULT '', goal_shares REAL NOT NULL DEFAULT 0,
        current_shares REAL NOT NULL DEFAULT 0, avg_price REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL, updated_at TEXT
      )''');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS ix_cf_acct ON cashflows(account_id, date)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS ix_tr_acct ON trades(account_id, date)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS ix_dv_acct ON dividends(account_id, date)');
    batch.execute(
        'CREATE INDEX IF NOT EXISTS ix_hd_acct ON holdings(account_id)');
    // v2: encrypted third-party integration credentials (device-only).
    batch.execute('''
      CREATE TABLE IF NOT EXISTS api_keys (
        id TEXT PRIMARY KEY, label TEXT NOT NULL DEFAULT '',
        service TEXT NOT NULL DEFAULT '', secret_enc TEXT NOT NULL DEFAULT '',
        hint TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL
      )''');
    // v3: LAN sync tombstones. A hard-deleted syncable row leaves a marker here
    // so the delete can propagate to peers (and be superseded by a newer
    // restore). Not exposed to normal ledger queries.
    batch.execute('''
      CREATE TABLE IF NOT EXISTS sync_tombstones (
        entity TEXT NOT NULL, id TEXT NOT NULL, updated_at TEXT,
        PRIMARY KEY (entity, id)
      )''');
    await batch.commit(noResult: true);
  }

  /// v3 migration: add the nullable `updated_at` change marker to each syncable
  /// table. CREATE ... IF NOT EXISTS can't alter a pre-existing table, so this
  /// runs on upgrade. Idempotent — skips tables that already have the column.
  Future<void> _addUpdatedAtColumns(Database d) async {
    for (final t in kSyncTables) {
      final cols = await d.rawQuery('PRAGMA table_info($t)');
      final has = cols.any((c) => c['name']?.toString() == 'updated_at');
      if (!has) {
        await d.execute('ALTER TABLE $t ADD COLUMN updated_at TEXT');
      }
    }
  }

  /// Insert (or refresh) a tombstone for a hard-deleted syncable row. Uses the
  /// given executor so it can share the caller's transaction.
  Future<void> _tombstone(DatabaseExecutor e, String entity, String id) async {
    await e.insert(
      'sync_tombstones',
      {'entity': entity, 'id': id, 'updated_at': _now()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    await d.insert('accounts', a.toMap()..['updated_at'] = _now(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteAccount(String id) async {
    final d = await db;
    await d.delete('accounts', where: 'id = ?', whereArgs: [id]);
    await _tombstone(d, 'accounts', id);
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
    await d.insert('cashflows', c.toMap()..['updated_at'] = _now(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCashflow(String id) async {
    final d = await db;
    await d.delete('cashflows', where: 'id = ?', whereArgs: [id]);
    await _tombstone(d, 'cashflows', id);
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
    await d.insert('trades', t.toMap()..['updated_at'] = _now(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTrade(String id) async {
    final d = await db;
    await d.delete('trades', where: 'id = ?', whereArgs: [id]);
    await _tombstone(d, 'trades', id);
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
    await d.insert('dividends', x.toMap()..['updated_at'] = _now(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDividend(String id) async {
    final d = await db;
    await d.delete('dividends', where: 'id = ?', whereArgs: [id]);
    await _tombstone(d, 'dividends', id);
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
    await d.insert('holdings', h.toMap()..['updated_at'] = _now(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteHolding(String id) async {
    final d = await db;
    await d.delete('holdings', where: 'id = ?', whereArgs: [id]);
    await _tombstone(d, 'holdings', id);
  }

  // ---- API keys (v2, encrypted, device-only) --------------------------------
  Future<List<ApiKey>> apiKeys() async {
    final d = await db;
    final rows = await d.query('api_keys', orderBy: 'created_at DESC');
    return rows.map(ApiKey.fromMap).toList();
  }

  Future<void> upsertApiKey(ApiKey k) async {
    final d = await db;
    await d.insert('api_keys', k.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteApiKey(String id) async {
    final d = await db;
    await d.delete('api_keys', where: 'id = ?', whereArgs: [id]);
  }

  Future<ApiKey?> apiKeyForService(String service) async {
    final d = await db;
    final rows = await d.query('api_keys',
        where: 'service = ?', whereArgs: [service], orderBy: 'created_at DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return ApiKey.fromMap(rows.first);
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
