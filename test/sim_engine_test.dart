// Unit tests for the Sandbox trading engine (spot + margin fills, P/L,
// pending-order triggers, liquidation, buying-power checks).
import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/sim/sim_engine.dart';
import 'package:nqe/sim/sim_models.dart';

void main() {
  var n = 0;
  String uid() => 'id${n++}';
  int now() => 1000;

  SimPortfolio fresh({double cash = 100000, double maxLev = 10}) => SimPortfolio(
        account: SimAccount(
          id: 'acc',
          name: 'Sandbox',
          currency: 'USD',
          startingCash: cash,
          maxLeverage: maxLev,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      );

  SimOrder mkt(String sym, OrderSide side, double qty,
          {TradeMode mode = TradeMode.spot,
          SimMarket market = SimMarket.crypto,
          double lev = 1}) =>
      SimOrder(
        id: uid(),
        accountId: 'acc',
        symbol: sym,
        market: market,
        mode: mode,
        side: side,
        type: OrderType.market,
        qty: qty,
        leverage: lev,
        createdAtMs: 0,
      );

  double Function(String) priced(Map<String, double> m) => (s) => m[s] ?? 0;

  setUp(() => n = 0);

  test('spot buy opens a long and deducts cash + fee', () {
    final p = fresh();
    final px = priced({'BTCUSDT': 100});
    final e = SimEngine.placeOrder(p, mkt('BTCUSDT', OrderSide.buy, 10),
        priceOf: px, nowMs: now(), uid: uid);
    expect(e.rejected, isFalse);
    expect(p.positions.length, 1);
    final pos = p.positions.first;
    expect(pos.side, PositionSide.long);
    expect(pos.qty, 10);
    expect(pos.avgPrice, 100);
    // cash = 100000 - (10*100) - fee(10*100*0.001=1) = 98999
    expect(p.account.cash, closeTo(98999, 1e-6));
    expect(SimEngine.equity(p, px), closeTo(99999, 1e-6)); // lost the 1 fee
  });

  test('spot sell realizes P/L and closes the position', () {
    final p = fresh();
    SimEngine.placeOrder(p, mkt('BTCUSDT', OrderSide.buy, 10),
        priceOf: priced({'BTCUSDT': 100}), nowMs: now(), uid: uid);
    final e = SimEngine.placeOrder(p, mkt('BTCUSDT', OrderSide.sell, 10),
        priceOf: priced({'BTCUSDT': 120}), nowMs: now(), uid: uid);
    expect(e.rejected, isFalse);
    expect(p.positions, isEmpty);
    // realized = (120-100)*10 = 200
    expect(p.account.realizedPnl, closeTo(200, 1e-6));
  });

  test('spot cannot be sold short', () {
    final p = fresh();
    final e = SimEngine.placeOrder(p, mkt('BTCUSDT', OrderSide.sell, 5),
        priceOf: priced({'BTCUSDT': 100}), nowMs: now(), uid: uid);
    expect(e.rejected, isTrue);
    expect(p.positions, isEmpty);
  });

  test('insufficient cash is rejected', () {
    final p = fresh(cash: 500);
    final e = SimEngine.placeOrder(p, mkt('BTCUSDT', OrderSide.buy, 10),
        priceOf: priced({'BTCUSDT': 100}), nowMs: now(), uid: uid);
    expect(e.rejected, isTrue);
  });

  test('margin long locks collateral and sets a liquidation price', () {
    final p = fresh();
    final e = SimEngine.placeOrder(
        p, mkt('ETHUSDT', OrderSide.buy, 10, mode: TradeMode.margin, lev: 5),
        priceOf: priced({'ETHUSDT': 100}), nowMs: now(), uid: uid);
    expect(e.rejected, isFalse);
    final pos = p.positions.first;
    expect(pos.mode, TradeMode.margin);
    expect(pos.leverage, 5);
    // collateral = 10*100/5 = 200; cash = 100000 - 200 - fee(1) = 99799
    expect(pos.marginUsed, closeTo(200, 1e-6));
    expect(p.account.cash, closeTo(99799, 1e-6));
    // liq (long, 5x) = 100 * (1 - 1/5) = 80
    expect(pos.liquidationPrice, closeTo(80, 1e-6));
  });

  test('margin short profits when price falls', () {
    final p = fresh();
    SimEngine.placeOrder(
        p, mkt('ETHUSDT', OrderSide.sell, 10, mode: TradeMode.margin, lev: 3),
        priceOf: priced({'ETHUSDT': 100}), nowMs: now(), uid: uid);
    final pos = p.positions.first;
    expect(pos.side, PositionSide.short);
    expect(pos.unrealizedPnl(90), closeTo(100, 1e-6)); // (90-100)*10*-1 = +100
    expect(pos.liquidationPrice, closeTo(100 * (1 + 1 / 3), 1e-6));
  });

  test('a stop (cut-loss) fills on the tick that crosses it', () {
    final p = fresh();
    SimEngine.placeOrder(p, mkt('BTCUSDT', OrderSide.buy, 10),
        priceOf: priced({'BTCUSDT': 100}), nowMs: now(), uid: uid);
    // Stop-sell at 90 (cut-loss).
    final stop = SimOrder(
      id: uid(),
      accountId: 'acc',
      symbol: 'BTCUSDT',
      market: SimMarket.crypto,
      mode: TradeMode.spot,
      side: OrderSide.sell,
      type: OrderType.stop,
      qty: 10,
      stopPrice: 90,
      reduceOnly: true,
      createdAtMs: 0,
    );
    final placed = SimEngine.placeOrder(p, stop,
        priceOf: priced({'BTCUSDT': 100}), nowMs: now(), uid: uid);
    expect(placed.newOrders.length, 1);
    // Price still above stop → no fill.
    var e = SimEngine.onTick(p,
        priceOf: priced({'BTCUSDT': 95}), nowMs: now(), uid: uid);
    expect(e.filledOrders, isEmpty);
    // Price drops to 88 (<=90) → stop fills, position closes.
    e = SimEngine.onTick(p,
        priceOf: priced({'BTCUSDT': 88}), nowMs: now(), uid: uid);
    expect(e.filledOrders.length, 1);
    expect(p.positions, isEmpty);
    expect(p.account.realizedPnl, lessThan(0)); // sold below cost
  });

  test('a limit-buy fills when price falls to the limit', () {
    final p = fresh();
    final lim = SimOrder(
      id: uid(),
      accountId: 'acc',
      symbol: 'BTCUSDT',
      market: SimMarket.crypto,
      mode: TradeMode.spot,
      side: OrderSide.buy,
      type: OrderType.limit,
      qty: 5,
      limitPrice: 90,
      createdAtMs: 0,
    );
    SimEngine.placeOrder(p, lim,
        priceOf: priced({'BTCUSDT': 100}), nowMs: now(), uid: uid);
    var e = SimEngine.onTick(p,
        priceOf: priced({'BTCUSDT': 95}), nowMs: now(), uid: uid);
    expect(e.filledOrders, isEmpty);
    e = SimEngine.onTick(p,
        priceOf: priced({'BTCUSDT': 89}), nowMs: now(), uid: uid);
    expect(e.filledOrders.length, 1);
    expect(p.positions.first.qty, 5);
  });

  test('margin long liquidates when price hits the liquidation price', () {
    final p = fresh();
    SimEngine.placeOrder(
        p, mkt('ETHUSDT', OrderSide.buy, 10, mode: TradeMode.margin, lev: 5),
        priceOf: priced({'ETHUSDT': 100}), nowMs: now(), uid: uid);
    // liq at 80; drop to 79 → liquidation closes it.
    final e = SimEngine.onTick(p,
        priceOf: priced({'ETHUSDT': 79}), nowMs: now(), uid: uid);
    expect(e.closedPositionIds.isNotEmpty, isTrue);
    expect(p.positions, isEmpty);
    // Collateral (200) is lost — realized loss ≈ -200.
    expect(p.account.realizedPnl, closeTo(-200, 1));
  });

  test('equity stays consistent through a margin round-trip', () {
    final p = fresh();
    final start = SimEngine.equity(p, priced({'ETHUSDT': 100}));
    expect(start, closeTo(100000, 1e-6));
    SimEngine.placeOrder(
        p, mkt('ETHUSDT', OrderSide.buy, 10, mode: TradeMode.margin, lev: 5),
        priceOf: priced({'ETHUSDT': 100}), nowMs: now(), uid: uid);
    // Right after opening, equity = start - fee.
    expect(SimEngine.equity(p, priced({'ETHUSDT': 100})),
        closeTo(100000 - 1, 1e-6));
    // Close at 110 for a gain.
    SimEngine.placeOrder(
        p, mkt('ETHUSDT', OrderSide.sell, 10, mode: TradeMode.margin, lev: 5),
        priceOf: priced({'ETHUSDT': 110}), nowMs: now(), uid: uid);
    expect(p.positions, isEmpty);
    // gain = (110-100)*10 = 100, minus two fees (~1 + 1.1).
    expect(SimEngine.equity(p, priced({'ETHUSDT': 110})),
        closeTo(100000 + 100 - 1 - 1.1, 0.5));
  });
}
