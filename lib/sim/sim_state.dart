// Sandbox orchestrator: owns the active virtual account, drives the price
// engine, runs the trading engine on every tick, persists to the isolated
// SimDb, and raises in-app notifications (order filled, stop-loss / take-profit
// hit, liquidation). Screens listen via ListenableBuilder, like `appState`.
import 'package:flutter/foundation.dart';

import '../format.dart';
import '../util.dart';
import 'sim_candles.dart';
import 'sim_db.dart';
import 'sim_engine.dart';
import 'sim_market.dart';
import 'sim_models.dart';
import 'sim_notify.dart';
import 'sim_price.dart';

/// Global singleton (mirrors the real-ledger `appState`).
final SimState simState = SimState();

/// A price level the order ticket wants drawn on the chart (the limit/stop/TP
/// price the user is typing). Null when there's nothing to preview. The chart
/// listens to this and paints a coloured line at the level, like Binance.
class SimOrderLine {
  final String symbol;
  final double price;
  final bool isBuy;
  const SimOrderLine(this.symbol, this.price, this.isBuy);
}

/// Shared, lightweight channel between the order ticket and the chart.
final ValueNotifier<SimOrderLine?> simOrderLine = ValueNotifier(null);

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

  /// When true this device MIRRORS a paired authority (the phone): it displays
  /// synced sim state and forwards orders, but does NOT run the matching engine
  /// locally, so the two devices can't diverge. Set on a paired desktop.
  bool mirror = false;

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
      case 'SGD':
        return 1 / _pxOr('USDSGD', 1.35);
      case 'HKD':
        return 1 / _pxOr('USDHKD', 7.8);
      case 'CNH':
        return 1 / _pxOr('USDCNH', 7.2);
      case 'MXN':
        return 1 / _pxOr('USDMXN', 17);
      case 'ZAR':
        return 1 / _pxOr('USDZAR', 18);
      case 'TRY':
        return 1 / _pxOr('USDTRY', 32);
      case 'SEK':
        return 1 / _pxOr('USDSEK', 10.5);
      case 'NOK':
        return 1 / _pxOr('USDNOK', 10.6);
      default:
        return 1.0;
    }
  }

  // ---- lifecycle -----------------------------------------------------------

  Future<void> init() async {
    if (_started) return;
    _started = true;
    price.addListener(_onPrices);
    try {
      await _load();
    } catch (_) {
      // Non-fatal (e.g. a DB hiccup at launch) — don't leave the UI stuck on
      // the loading spinner; it will populate once data is available/synced.
      loading = false;
      notifyListeners();
    }
    price.start();
  }

  /// Stable id for the single default account. Fixed (not random) so a paired
  /// phone and desktop converge onto the SAME account instead of each creating
  /// its own and never merging.
  static const String kDefaultAccountId = 'sandbox-default';

  Future<void> _load() async {
    loading = true;
    notifyListeners();
    var accounts = await _db.accounts();
    // A mirror (paired desktop) must NOT create its own account — it waits for
    // the phone's account to sync in, or the two would never converge.
    if (accounts.isEmpty && !mirror) {
      final a = SimAccount(
        id: kDefaultAccountId,
        name: 'Sandbox',
        currency: 'PHP', // pesos — the Sandbox lists the PSE alongside FX/crypto
        startingCash: 1000000, // ₱1,000,000 virtual starting balance
        createdAtMs: _now(),
        updatedAtMs: _now(),
      );
      await _db.upsertAccount(a);
      accounts = [a];
    }
    if (accounts.isEmpty) {
      // Mirror with nothing synced yet — show empty until the phone's data
      // arrives (onRemoteSimApplied will populate the portfolio).
      loading = false;
      notifyListeners();
      return;
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

  // Serial queue for sim DB writes + reloads, so a reload can never read the
  // DB in the middle of a not-yet-finished persist (which could otherwise
  // reload a just-filled order as still "open" and double-fill it).
  Future<void> _q = Future.value();
  Future<void> _serial(Future<void> Function() task) {
    final r = _q.then((_) => task());
    _q = r.catchError((_) {});
    return r;
  }

  void _onPrices() {
    final pf = _pf;
    if (pf == null) return;
    // A mirror never matches orders / liquidates locally — the authority does
    // that and the result syncs back. It still repaints for live prices/P&L.
    if (!mirror) {
      final effect = SimEngine.onTick(pf,
          priceOf: priceOf, nowMs: _now(), uid: uid, fxOf: fxOf);
      if (effect.trades.isNotEmpty ||
          effect.filledOrders.isNotEmpty ||
          effect.liquidatedSymbols.isNotEmpty ||
          effect.removedOrderIds.isNotEmpty) {
        _noticeForEffect(effect);
        _serial(() => _persist(effect));
      }
    }
    notifyListeners();
  }

  /// Called by the sync layer after remote sandbox rows are applied, so the
  /// in-memory portfolio reflects them (and, on the authority, newly-synced
  /// orders enter the engine loop). Runs on the serial queue, so it never
  /// races a pending persist.
  Future<void> onRemoteSimApplied() => _serial(_reloadFromDb);

  Future<void> _reloadFromDb() async {
    final accounts = await _db.accounts();
    if (accounts.isEmpty) return;
    // Synced data has arrived — make sure the UI isn't still showing the
    // initial loading spinner (a mirror may never have run its own _load()).
    loading = false;
    final prevId = _pf?.account.id;
    final acc = accounts.firstWhere((a) => a.id == prevId,
        orElse: () => accounts.first);
    final pos = await _db.positions(acc.id);
    final ord = await _db.orders(acc.id, openOnly: true);
    _pf = SimPortfolio(account: acc, positions: pos, orders: ord);
    trades = await _db.trades(acc.id);
    watch = await _db.watch(acc.id);
    price.subscribeAll({
      ...pos.map((e) => e.symbol),
      ...ord.map((e) => e.symbol),
      ...watch.map((e) => e.symbol),
    });
    notifyListeners();
  }

  // ---- trading actions -----------------------------------------------------

  /// Place an order. Returns null on success, or a human-readable reject reason.
  Future<String?> placeOrder(SimOrder order) async {
    final pf = _pf;
    if (pf == null) return 'No sandbox account.';
    price.subscribe(order.symbol);
    // On a mirror, don't match locally — record the order as open, let it sync
    // to the authority, which executes it and syncs the result back.
    if (mirror) {
      order.status = OrderStatus.open;
      pf.orders.add(order);
      await _serial(() => _db.upsertOrder(order));
      notifyListeners();
      return null;
    }
    final e = SimEngine.placeOrder(pf, order,
        priceOf: priceOf, nowMs: _now(), uid: uid, fxOf: fxOf);
    if (e.rejected) return e.rejectReason;
    await _serial(() => _persist(e));
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
    // Serialize with engine persists/reloads so a concurrent tick can't
    // re-upsert a position that reset just deleted.
    await _serial(() async {
      acc.cash = acc.startingCash;
      acc.realizedPnl = 0;
      acc.updatedAtMs = _now();
      for (final p in List<SimPosition>.from(positions)) {
        await _db.deletePosition(p.id);
      }
      // Clear ALL orders — open AND filled/closed history — not just the ones
      // currently open, so a reset truly wipes the sandbox order history.
      await _db.clearOrders(acc.id);
      _pf = SimPortfolio(account: acc);
      await _db.upsertAccount(acc);
      // Clear the blotter too, so the Overview (fees, trade count, win rate)
      // matches the restored balance instead of showing pre-reset history.
      await _db.clearTrades(acc.id);
      trades = [];
    });
    _pushNotice(const SimNotice(
        SimNoticeType.info, 'Sandbox reset', 'Balance restored to starting cash.',
        0));
    notifyListeners();
  }

  /// Wallet top-up: add virtual cash to Free Cash. The deposit basis
  /// (startingCash) rises with it, so a deposit is NOT counted as trading
  /// profit — Total Return keeps measuring performance, not funding.
  Future<void> topUp(double amount) async {
    final acc = _pf?.account;
    if (acc == null || !amount.isFinite || amount <= 0) return;
    await _serial(() async {
      acc.cash += amount;
      acc.startingCash += amount;
      acc.updatedAtMs = _now();
      await _db.upsertAccount(acc);
    });
    _pushNotice(SimNotice(SimNoticeType.info, 'Wallet topped up',
        'Added ${money(amount, currency: currency)} to Free Cash.', _now()));
    notifyListeners();
  }

  /// Wallet cash-out: withdraw from Free Cash. Capped at the available Free
  /// Cash (can't withdraw money tied up in open positions). Lowers the deposit
  /// basis too, so a withdrawal isn't booked as a loss. Returns false if the
  /// amount is invalid or exceeds Free Cash.
  Future<bool> cashOut(double amount) async {
    final acc = _pf?.account;
    if (acc == null || !amount.isFinite || amount <= 0) return false;
    if (amount > acc.cash) return false;
    await _serial(() async {
      acc.cash -= amount;
      acc.startingCash = (acc.startingCash - amount).clamp(0, double.infinity);
      acc.updatedAtMs = _now();
      await _db.upsertAccount(acc);
    });
    _pushNotice(SimNotice(SimNoticeType.info, 'Cashed out',
        'Withdrew ${money(amount, currency: currency)} from Free Cash.',
        _now()));
    notifyListeners();
    return true;
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
    // Regenerate candles against the newly-active feed (so stale live klines
    // don't linger after switching to Simulated, and vice-versa).
    candles.clearAll();
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
          // Notify on any market fill — whether placed here (placed==true) or
          // filled on this device after syncing in from the paired one.
          _pushNotice(SimNotice(SimNoticeType.filled, 'Order filled',
              '${o.symbol} ${_sideWord(o.side)} ${_qtyStr(o.qty)} @ ${_pxStr(o.fillPrice)}',
              _now()));
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
    // Also emit a real Android system notification for trade events (fills,
    // stop-loss, take-profit, liquidation) so it surfaces off-screen too.
    if (n.type != SimNoticeType.info) {
      SimNotify.instance.show(n.title, n.message);
    }
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
