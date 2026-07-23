// Sandbox orchestrator: owns the active virtual account, drives the price
// engine, runs the trading engine on every tick, persists to the isolated
// SimDb, and raises in-app notifications (order filled, stop-loss / take-profit
// hit, liquidation). Screens listen via ListenableBuilder, like `appState`.
import 'package:flutter/foundation.dart';

import '../util.dart';
import 'sim_db.dart';
import 'sim_engine.dart';
import 'sim_market.dart';
import 'sim_models.dart';
import 'sim_price.dart';

/// Global singleton (mirrors the real-ledger `appState`).
final SimState simState = SimState();

enum SimNoticeType { filled, stopHit, tpHit, liquidation, info }

class SimNotice {
  final SimNoticeType type;
  final String title;
  final String message;
  final int tsMs;
  const SimNotice(this.type, this.title, this.message, this.tsMs);
}

class SimState extends ChangeNotifier {
  final PriceEngine price = PriceEngine();
  final SimDb _db = SimDb.instance;

  bool loading = true;
  SimPortfolio? _pf;
  List<SimTrade> trades = [];
  List<SimWatch> watch = [];

  /// Notification history (newest first) + the latest one for a transient toast.
  final List<SimNotice> notices = [];
  SimNotice? lastNotice;

  bool _started = false;

  SimAccount? get account => _pf?.account;
  List<SimPosition> get positions => _pf?.positions ?? const [];
  List<SimOrder> get openOrders => _pf?.orders ?? const [];

  double priceOf(String symbol) =>
      price.price(symbol) ?? seedPriceFor(symbol);

  double get equity => _pf == null ? 0 : SimEngine.equity(_pf!, priceOf);
  double get unrealized =>
      _pf == null ? 0 : SimEngine.unrealized(_pf!, priceOf);
  double get freeCash => _pf?.account.cash ?? 0;

  // ---- lifecycle -----------------------------------------------------------

  Future<void> init() async {
    if (_started) return;
    _started = true;
    price.addListener(_onPrices);
    await _load();
    price.start();
  }

  Future<void> _load() async {
    loading = true;
    notifyListeners();
    var accounts = await _db.accounts();
    if (accounts.isEmpty) {
      final a = SimAccount(
        id: uid(),
        name: 'Sandbox',
        currency: 'USD',
        startingCash: 100000,
        createdAtMs: _now(),
        updatedAtMs: _now(),
      );
      await _db.upsertAccount(a);
      accounts = [a];
    }
    final acc = accounts.first;
    final pos = await _db.positions(acc.id);
    final ord = await _db.orders(acc.id, openOnly: true);
    _pf = SimPortfolio(account: acc, positions: pos, orders: ord);
    trades = await _db.trades(acc.id);
    watch = await _db.watch(acc.id);

    // Seed prices for everything we care about + a few defaults.
    final syms = <String>{
      'BTCUSDT', 'ETHUSDT', 'AAPL', 'EURUSD', 'XAUUSD',
      ...pos.map((e) => e.symbol),
      ...ord.map((e) => e.symbol),
      ...watch.map((e) => e.symbol),
    };
    price.subscribeAll(syms);
    price.rollPrevClose();
    loading = false;
    notifyListeners();
  }

  void _onPrices() {
    final pf = _pf;
    if (pf == null) return;
    final effect = SimEngine.onTick(pf,
        priceOf: priceOf, nowMs: _now(), uid: uid);
    if (effect.trades.isNotEmpty ||
        effect.filledOrders.isNotEmpty ||
        effect.liquidatedSymbols.isNotEmpty) {
      _persist(effect);
      _noticeForEffect(effect);
    }
    // Always notify so live prices/P&L refresh on screen.
    notifyListeners();
  }

  // ---- trading actions -----------------------------------------------------

  /// Place an order. Returns null on success, or a human-readable reject reason.
  Future<String?> placeOrder(SimOrder order) async {
    final pf = _pf;
    if (pf == null) return 'No sandbox account.';
    price.subscribe(order.symbol);
    final e = SimEngine.placeOrder(pf, order,
        priceOf: priceOf, nowMs: _now(), uid: uid);
    if (e.rejected) return e.rejectReason;
    await _persist(e);
    _noticeForEffect(e, placed: true);
    notifyListeners();
    return null;
  }

  Future<void> cancelOrder(String orderId) async {
    final pf = _pf;
    if (pf == null) return;
    SimEngine.cancelOrder(pf, orderId);
    await _db.deleteOrder(orderId);
    notifyListeners();
  }

  /// Market-close a position (full or partial).
  Future<String?> closePosition(SimPosition pos, {double? qty}) async {
    final q = (qty == null || qty <= 0 || qty > pos.qty) ? pos.qty : qty;
    final order = SimOrder(
      id: uid(),
      accountId: pos.accountId,
      symbol: pos.symbol,
      market: pos.market,
      mode: pos.mode,
      side: pos.side == PositionSide.long ? OrderSide.sell : OrderSide.buy,
      type: OrderType.market,
      qty: q,
      leverage: pos.leverage,
      reduceOnly: true,
      createdAtMs: _now(),
    );
    return placeOrder(order);
  }

  Future<void> resetAccount() async {
    final acc = _pf?.account;
    if (acc == null) return;
    acc.cash = acc.startingCash;
    acc.realizedPnl = 0;
    acc.updatedAtMs = _now();
    for (final p in List<SimPosition>.from(positions)) {
      await _db.deletePosition(p.id);
    }
    for (final o in List<SimOrder>.from(openOrders)) {
      await _db.deleteOrder(o.id);
    }
    _pf = SimPortfolio(account: acc);
    await _db.upsertAccount(acc);
    trades = await _db.trades(acc.id); // history kept; clear if desired
    _pushNotice(const SimNotice(
        SimNoticeType.info, 'Sandbox reset', 'Balance restored to starting cash.',
        0));
    notifyListeners();
  }

  Future<void> addWatch(String symbol, SimMarket market) async {
    final acc = _pf?.account;
    if (acc == null) return;
    if (watch.any((w) => w.symbol == symbol)) return;
    final w = SimWatch(
        id: uid(),
        accountId: acc.id,
        symbol: symbol,
        market: market,
        addedAtMs: _now());
    await _db.upsertWatch(w);
    watch = await _db.watch(acc.id);
    price.subscribe(symbol);
    notifyListeners();
  }

  Future<void> removeWatch(String id) async {
    await _db.deleteWatch(id);
    final acc = _pf?.account;
    if (acc != null) watch = await _db.watch(acc.id);
    notifyListeners();
  }

  void setFeedMode(FeedMode mode) {
    price.mode = mode;
    notifyListeners();
  }

  void clearNotices() {
    notices.clear();
    lastNotice = null;
    notifyListeners();
  }

  // ---- persistence + notifications ----------------------------------------

  Future<void> _persist(SimEffect e) async {
    final pf = _pf;
    if (pf == null) return;
    await _db.upsertAccount(pf.account);
    for (final t in e.trades) {
      await _db.insertTrade(t);
    }
    for (final id in e.closedPositionIds) {
      await _db.deletePosition(id);
    }
    for (final pos in pf.positions) {
      await _db.upsertPosition(pos);
    }
    for (final o in e.newOrders) {
      await _db.upsertOrder(o);
    }
    for (final o in e.filledOrders) {
      await _db.upsertOrder(o); // status now filled (kept for history)
    }
    if (e.trades.isNotEmpty) {
      trades = await _db.trades(pf.account.id);
    }
  }

  void _noticeForEffect(SimEffect e, {bool placed = false}) {
    for (final o in e.filledOrders) {
      switch (o.type) {
        case OrderType.stop:
          _pushNotice(SimNotice(SimNoticeType.stopHit, 'Stop-loss hit',
              '${o.symbol} ${_sideWord(o.side)} ${_qtyStr(o.qty)} @ ${_pxStr(o.fillPrice)}',
              _now()));
          break;
        case OrderType.takeProfit:
          _pushNotice(SimNotice(SimNoticeType.tpHit, 'Take-profit hit',
              '${o.symbol} ${_sideWord(o.side)} ${_qtyStr(o.qty)} @ ${_pxStr(o.fillPrice)}',
              _now()));
          break;
        case OrderType.limit:
          _pushNotice(SimNotice(SimNoticeType.filled, 'Limit order filled',
              '${o.symbol} ${_sideWord(o.side)} ${_qtyStr(o.qty)} @ ${_pxStr(o.fillPrice)}',
              _now()));
          break;
        case OrderType.market:
          if (placed) {
            _pushNotice(SimNotice(SimNoticeType.filled, 'Order filled',
                '${o.symbol} ${_sideWord(o.side)} ${_qtyStr(o.qty)} @ ${_pxStr(o.fillPrice)}',
                _now()));
          }
          break;
      }
    }
    for (final sym in e.liquidatedSymbols) {
      _pushNotice(SimNotice(SimNoticeType.liquidation, 'Position liquidated',
          '$sym hit its liquidation price — collateral lost.', _now()));
    }
  }

  void _pushNotice(SimNotice n) {
    notices.insert(0, n);
    if (notices.length > 60) notices.removeRange(60, notices.length);
    lastNotice = n;
  }

  String _sideWord(OrderSide s) => s == OrderSide.buy ? 'buy' : 'sell';
  String _qtyStr(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(4);
  String _pxStr(double? p) => p == null ? '—' : p.toStringAsFixed(2);

  int _now() => DateTime.now().millisecondsSinceEpoch;

  @override
  void dispose() {
    price.removeListener(_onPrices);
    price.dispose();
    super.dispose();
  }
}
