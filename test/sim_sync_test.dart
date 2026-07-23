// Cross-device Sandbox sync — drives the REAL SimSyncRepo.buildAll /
// applyRemote across two isolated SimDb "devices" (phone = authority,
// desktop = follower), including the clock-skew case that was the actual
// "sandbox doesn't sync" bug.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nqe/sim/sim_db.dart';
import 'package:nqe/sim/sim_sync.dart';

/// A raw account row with an explicit change-stamp (bypasses upsert's now()
/// stamping so a test can model a specific wall clock).
Map<String, Object?> accountRow(String id, double cash, int updatedAt) => {
      'id': id,
      'name': 'Sandbox',
      'currency': 'PHP',
      'starting_cash': 1000000.0,
      'cash': cash,
      'realized_pnl': 0.0,
      'margin_enabled': 1,
      'max_leverage': 10.0,
      'created_at': 1,
      'updated_at': updatedAt,
    };

Map<String, Object?> positionRow(String id, double qty, int updatedAt) => {
      'id': id,
      'account_id': 'acc1',
      'symbol': 'BTCUSDT',
      'market': 2,
      'mode': 0,
      'side': 0,
      'qty': qty,
      'avg_price': 60000.0,
      'leverage': 1.0,
      'margin_used': 0.0,
      'opened_at': 1,
      'updated_at': updatedAt,
    };

Map<String, Object?> orderRow(String id, int status, int updatedAt) => {
      'id': id,
      'account_id': 'acc1',
      'symbol': 'BTCUSDT',
      'market': 2,
      'mode': 0,
      'side': 0,
      'type': 1,
      'qty': 0.5,
      'leverage': 1.0,
      'limit_price': 59000.0,
      'stop_price': null,
      'reduce_only': 0,
      'status': status, // 0 open, 1 filled
      'fill_price': null,
      'created_at': 1,
      'filled_at': null,
      'updated_at': updatedAt,
    };

Future<SimDb> freshDevice() async {
  final dir = await Directory.systemTemp.createTemp('nqe_sim_sync');
  final path = '${dir.path}/sim_${DateTime.now().microsecondsSinceEpoch}_'
      '${dir.hashCode}.db';
  return SimDb.forDb(await SimDb.openAtPath(path));
}

Future<Map<String, Object?>?> row(SimDb d, String table, String id) async {
  final rows = await (await d.db)
      .query(table, where: 'id=?', whereArgs: [id], limit: 1);
  return rows.isEmpty ? null : rows.first;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('follower mirrors the authority VERBATIM despite reversed clocks '
      '(the clock-skew bug)', () async {
    final phone = await freshDevice(); // authority
    final desktop = await freshDevice(); // follower / mirror

    // The phone made the newer edit (cash 900k) but its wall clock is BEHIND,
    // so its stamp (100) is SMALLER than the desktop's stale copy (5000).
    await (await phone.db).insert('sim_accounts', accountRow('acc1', 900000, 100));
    await (await desktop.db)
        .insert('sim_accounts', accountRow('acc1', 1000000, 5000));

    final fromPhone = await SimSyncRepo.instance.buildAll(db: phone);
    final applied = await SimSyncRepo.instance
        .applyRemote(fromPhone, asFollower: true, db: desktop);

    expect(applied, greaterThan(0));
    final acc = await row(desktop, 'sim_accounts', 'acc1');
    // Verbatim: the follower takes the phone's value even though its stamp is
    // numerically older. Plain LWW would have WRONGLY kept 1,000,000.
    expect(acc!['cash'], 900000);
  });

  test('authority keeps engine-owned state but accepts a new forwarded order '
      'and an account (wallet) update', () async {
    final phone = await freshDevice(); // authority
    final desktop = await freshDevice(); // follower / active UI

    // Phone owns the account + a position.
    await (await phone.db).insert('sim_accounts', accountRow('acc1', 900000, 100));
    await (await phone.db).insert('sim_positions', positionRow('pos1', 1.0, 100));

    // Desktop side: a stale copy of the position (must NOT clobber the phone),
    // a newer account = a wallet top-up (LWW, should land), and a brand-new
    // forwarded order (should be accepted).
    await (await desktop.db)
        .insert('sim_positions', positionRow('pos1', 99.0, 5000));
    await (await desktop.db)
        .insert('sim_accounts', accountRow('acc1', 1500000, 5000));
    await (await desktop.db).insert('sim_orders', orderRow('ord-new', 0, 5000));

    final fromDesktop = await SimSyncRepo.instance.buildAll(db: desktop);
    await SimSyncRepo.instance
        .applyRemote(fromDesktop, asFollower: false, db: phone);

    // Position is engine-owned → the stale desktop copy is ignored.
    expect((await row(phone, 'sim_positions', 'pos1'))!['qty'], 1.0);
    // Account is shared → the newer wallet top-up lands (LWW).
    expect((await row(phone, 'sim_accounts', 'acc1'))!['cash'], 1500000);
    // The new forwarded order is accepted.
    expect(await row(phone, 'sim_orders', 'ord-new'), isNotNull);
  });

  test('a desktop cancel deletes an OPEN order on the authority but never a '
      'FILLED one', () async {
    final phone = await freshDevice();
    final desktop = await freshDevice();

    await (await phone.db).insert('sim_orders', orderRow('ord-open', 0, 100));
    await (await phone.db).insert('sim_orders', orderRow('ord-filled', 1, 100));

    // Desktop tombstones both (a cancel gesture).
    const now = 6000;
    for (final id in ['ord-open', 'ord-filled']) {
      await (await desktop.db).insert('sim_tombstones',
          {'entity': 'sim_orders', 'id': id, 'updated_at': now});
    }

    final fromDesktop = await SimSyncRepo.instance.buildAll(db: desktop);
    await SimSyncRepo.instance
        .applyRemote(fromDesktop, asFollower: false, db: phone);

    // Open order cancel is honored; the filled order (history) is protected.
    expect(await row(phone, 'sim_orders', 'ord-open'), isNull);
    expect(await row(phone, 'sim_orders', 'ord-filled'), isNotNull);
  });

  test('a desktop wallet command (intent) forwards to the authority', () async {
    final phone = await freshDevice();
    final desktop = await freshDevice();

    // Desktop queues a top-up command (it can't mutate the shared account
    // itself — that would fight the phone's copy).
    await (await desktop.db).insert('sim_intents', {
      'id': 'intent1',
      'account_id': 'acc1',
      'kind': 'topup',
      'amount': 50000.0,
      'created_at': 10,
      'updated_at': 10,
    });

    final fromDesktop = await SimSyncRepo.instance.buildAll(db: desktop);
    await SimSyncRepo.instance
        .applyRemote(fromDesktop, asFollower: false, db: phone);

    // The command reached the phone, where its engine will apply + clear it.
    final intent = await row(phone, 'sim_intents', 'intent1');
    expect(intent, isNotNull);
    expect(intent!['kind'], 'topup');
    expect(intent['amount'], 50000.0);
  });

  test('a desktop watchlist removal is honored by the authority', () async {
    final phone = await freshDevice();
    final desktop = await freshDevice();

    // Phone has a watch row; desktop removes it (tombstone).
    await (await phone.db).insert('sim_watch', {
      'id': 'w1',
      'account_id': 'acc1',
      'symbol': 'BTCUSDT',
      'market': 2,
      'added_at': 100,
    });
    await (await desktop.db).insert('sim_tombstones',
        {'entity': 'sim_watch', 'id': 'w1', 'updated_at': 5000});

    final fromDesktop = await SimSyncRepo.instance.buildAll(db: desktop);
    await SimSyncRepo.instance
        .applyRemote(fromDesktop, asFollower: false, db: phone);

    // User-owned watchlist removal reaches the phone (not resurrected).
    expect(await row(phone, 'sim_watch', 'w1'), isNull);
  });

  test('follower applies an authority tombstone (closed position propagates)',
      () async {
    final phone = await freshDevice();
    final desktop = await freshDevice();

    // Desktop currently shows a position the phone just closed.
    await (await desktop.db)
        .insert('sim_positions', positionRow('pos1', 1.0, 100));
    await (await phone.db).insert('sim_tombstones',
        {'entity': 'sim_positions', 'id': 'pos1', 'updated_at': 200});

    final fromPhone = await SimSyncRepo.instance.buildAll(db: phone);
    await SimSyncRepo.instance
        .applyRemote(fromPhone, asFollower: true, db: desktop);

    expect(await row(desktop, 'sim_positions', 'pos1'), isNull);
  });
}
