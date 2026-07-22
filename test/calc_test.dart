import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/calc.dart';
import 'package:nqe/models.dart';

Account _acct({double cap = 100000, String cur = 'PHP', double fx = 1}) =>
    Account(id: 'a1', name: 'Book', currency: cur, startingCapital: cap,
        fxToPhp: fx, createdAt: '2026-01-01T00:00:00.000Z');

Trade _trade(String date, double shares, double buy, double? sell) => Trade(
      id: 'id-$date-$buy',
      accountId: 'a1',
      date: date,
      stock: 'XYZ',
      shares: shares,
      buyPrice: buy,
      sellPrice: sell,
      status: sell == null ? 'open' : 'closed',
      createdAt: '2026-01-01T00:00:00.000Z',
    );

void main() {
  test('trade P&L and win/loss flags', () {
    final win = _trade('2026-02-10', 1000, 1.0, 1.2); // +200
    final loss = _trade('2026-02-11', 1000, 1.0, 0.9); // -100
    final open = _trade('2026-02-12', 1000, 1.0, null);
    expect(win.pnl, closeTo(200, 0.0001));
    expect(loss.pnl, closeTo(-100, 0.0001));
    expect(win.isWin, true);
    expect(loss.isLoss, true);
    expect(open.isOpen, true);
    expect(open.pnl, 0);
  });

  test('computeAccountMetrics aggregates realised P&L and win rate', () {
    final a = _acct(cap: 100000);
    final trades = [
      _trade('2026-02-10', 1000, 1.0, 1.2), // +200
      _trade('2026-02-11', 1000, 1.0, 0.9), // -100
      _trade('2026-02-12', 1000, 1.0, null), // open
    ];
    final m = computeAccountMetrics(a, const [], trades, const []);
    expect(m.realizedPnl, closeTo(100, 0.0001));
    expect(m.closedTrades, 2);
    expect(m.wins, 1);
    expect(m.losses, 1);
    expect(m.openTrades, 1);
    expect(m.winRate, closeTo(0.5, 0.0001));
    expect(m.equity, closeTo(100100, 0.0001));
  });

  test('cashflows adjust invested capital and PHP equity', () {
    final a = _acct(cap: 0, cur: 'EUR', fx: 60);
    final cf = [
      Cashflow(id: 'c1', accountId: 'a1', date: '2026-01-05', type: 'deposit',
          amount: 100, fxRate: 60, createdAt: 'x'), // 6000 PHP
      Cashflow(id: 'c2', accountId: 'a1', date: '2026-02-05', type: 'deposit',
          amount: 100, fxRate: 70, createdAt: 'x'), // 7000 PHP
    ];
    final m = computeAccountMetrics(a, cf, const [], const []);
    expect(m.netCashflow, closeTo(200, 0.0001));
    expect(m.equityPhp, closeTo(13000, 0.0001));
  });

  test('monthlyStats produces chained TWR', () {
    final a = _acct(cap: 1000);
    final trades = [
      _trade('2026-01-15', 100, 1.0, 2.0), // +100 in Jan
      _trade('2026-02-15', 100, 1.0, 2.0), // +100 in Feb
    ];
    final stats = monthlyStats(a, const [], trades);
    expect(stats.length, 2);
    expect(stats[0].pnl, closeTo(100, 0.0001));
    // Jan: 100/1000 = 0.10 ; Feb start 1100, 100/1100 ≈ 0.0909
    // TWR = 1.10 * 1.0909 - 1 ≈ 0.20
    expect(stats[1].twr, closeTo(0.20, 0.001));
  });

  test('equityCurve starts at capital and accumulates', () {
    final a = _acct(cap: 500);
    final trades = [
      _trade('2026-01-15', 100, 1.0, 2.0), // +100
      _trade('2026-02-15', 100, 1.0, 0.5), // -50
    ];
    final curve = equityCurve(a, trades);
    expect(curve.first.equity, 500);
    expect(curve.last.equity, closeTo(550, 0.0001));
  });
}
