// Sandbox orchestrator: owns the active virtual account, drives the price
// engine, runs the trading engine on every tick, persists to the isolated
// SimDb, and raises in-app notifications (order filled, stop-loss / take-profit
// hit, liquidation). Screens listen via ListenableBuilder, like `appState`.
import 'package:flutter/foundation.dart';

import '../util.dart';
import 'sim_candles.dart';
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
  final CandleStore candles = CandleStore();
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

  /// Account base currency (Sandbox trades in Philippine pesos, since it lists
  /// the PSE alongside global markets).
  String get currency => _pf?.account.currency ?? 'PHP';

  double get equity =>
      _pf == null ? 0 : SimEngine.equity(_pf!, priceOf, fxOf: fxOf);
  double get unrealized =>
      _pf == null ? 0 : SimEngine.unrealized(_pf!, priceOf, fxOf: fxOf);
  double get freeCash => _pf?.account.cash ?? 0;

  /// FX multiplier from an instrument's quote currency to the account base
  /// (e.g. a US/crypto symbol quoted in USD → PHP). Rates are read live from
  /// the forex feed, so amounts auto-convert as USDPHP moves.
  double fxOf(String symbol) {
    final base = _pf?.account.currency ?? 'PHP';
    final quote = quoteCurrencyFor(symbol);
    if (quote == base) return 1.0;
    final a = _fxToUsd(quote);
    final b = _fxToUsd(base);
    if (!(a > 0) || !(b > 0)) return 1.0;
    final m = a / b;
    return (m.isFinite && m > 0) ? m : 1.0;
  }

  double _pxOr(String sym, double fallback) {
    final p = price.price(sym);
    return (p != null && p.isFinite && p > 0) ? p : fallback;
  }

  /// Value of one unit of [ccy] in USD (pivot currency), derived from the
  /// forex pairs already in the feed.
  double _fxToUsd(String ccy) {
    switch (ccy) {
      case 'USD':
        return 1.0;
      case 'EUR':
        return _pxOr('EURUSD', 1.08);
      case 'GBP':
        return _pxOr('GBPUSD', 1.27);
      case 'AUD':
        return _pxOr('AUDUSD', 0.66);
      case 'NZD':
        return _pxOr('NZDUSD', 0.61);
      case 'JPY':
        return 1 / _pxOr('USDJPY', 150);
      case 'CAD':
        return 1 / _pxOr('USDCAD', 1.36);
      case 'CHF':
        return 1 / _pxOr('USDCHF', 0.88);
      case 'PHP':
        return 1 / _pxOr('USDPHP', 57);
      default:
        return 1.0;
    }
  }

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
        currency: 'PHP', // pesos — the Sandbox lists the PSE alongside FX/crypto
        startingCash: 1000000, // ₱1,000,000 virtual starting balance
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

    // Seed prices for everything we care about + the FX pairs used to convert
    // USD-quoted instruments into the peso base currency.
    final syms = <String>{
      'BTCUSDT', 'ETHUSDT', 'AAPL', 'EURUSD', 'XAUUSD',
      'USDPHP', 'USDJPY', 'USDCAD', 'USDCHF', 'GBPUSD', 'AUDUSD', 'NZDUSD',
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
        priceOf: priceOf, nowMs: _now(), uid: uid, fxOf: fxOf);
    if (effect.trades.isNotEmpty ||
        effect.filledOrders.isNotEmpty ||
        effect.liquidatedSymbols.isNotEmpty ||
        effect.removedOrderIds.isNotEmpty) {
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
        priceOf: priceOf, nowMs: _now(), uid: uid, fxOf: fxOf);
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
    for (final id in e.removedOrderIds) {
      await _db.deleteOrder(id); // rejected/cancelled pending orders
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
