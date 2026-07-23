// Simulation Trading (Sandbox) — data models.
//
// A self-contained paper-trading exchange, fully ISOLATED from the real fund
// ledger (its own DB). Supports SPOT and MARGIN (leverage, long/short,
// liquidation) across multiple markets (PSE stocks, Forex, Crypto). Virtual
// money only — nothing here ever touches real funds.
import 'dart:convert';

enum SimMarket { stocks, forex, crypto }

enum TradeMode { spot, margin }

enum OrderSide { buy, sell }

/// For a resulting position: long (bought / +qty) or short (sold / -qty, margin
/// only).
enum PositionSide { long, short }

enum OrderType { market, limit, stop, takeProfit }

enum OrderStatus { open, filled, cancelled, rejected }

enum FeedMode { simulated, live }

String marketLabel(SimMarket m) => switch (m) {
      SimMarket.stocks => 'Stocks',
      SimMarket.forex => 'Forex',
      SimMarket.crypto => 'Crypto',
    };

// ---- Account -----------------------------------------------------------------

/// A virtual trading account (portfolio). One sandbox can hold several.
class SimAccount {
  String id;
  String name;
  String currency; // quote currency, e.g. 'USD' or 'PHP'
  double startingCash;
  double cash; // free cash (settled, not locked in margin/orders)
  double realizedPnl;
  bool marginEnabled;
  double maxLeverage; // e.g. 10x
  int createdAtMs;
  int updatedAtMs;

  SimAccount({
    required this.id,
    required this.name,
    this.currency = 'USD',
    this.startingCash = 100000,
    double? cash,
    this.realizedPnl = 0,
    this.marginEnabled = true,
    this.maxLeverage = 10,
    required this.createdAtMs,
    required this.updatedAtMs,
  }) : cash = cash ?? startingCash;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'currency': currency,
        'starting_cash': startingCash,
        'cash': cash,
        'realized_pnl': realizedPnl,
        'margin_enabled': marginEnabled ? 1 : 0,
        'max_leverage': maxLeverage,
        'created_at': createdAtMs,
        'updated_at': updatedAtMs,
      };

  factory SimAccount.fromMap(Map<String, Object?> m) => SimAccount(
        id: m['id'] as String,
        name: (m['name'] ?? 'Sandbox') as String,
        currency: (m['currency'] ?? 'USD') as String,
        startingCash: _d(m['starting_cash'], 100000),
        cash: _d(m['cash'], 100000),
        realizedPnl: _d(m['realized_pnl'], 0),
        marginEnabled: (m['margin_enabled'] as int? ?? 1) == 1,
        maxLeverage: _d(m['max_leverage'], 10),
        createdAtMs: (m['created_at'] as int?) ?? 0,
        updatedAtMs: (m['updated_at'] as int?) ?? 0,
      );
}

// ---- Position ----------------------------------------------------------------

/// An open position. Spot positions are always long (you hold the asset).
/// Margin positions can be long or short with leverage; [marginUsed] is the
/// collateral locked from cash and [liquidationPrice] is where equity hits zero.
class SimPosition {
  String id;
  String accountId;
  String symbol;
  SimMarket market;
  TradeMode mode;
  PositionSide side;
  double qty; // base units (always positive; direction is [side])
  double avgPrice; // entry
  double leverage; // 1 for spot
  double marginUsed; // collateral locked (0 for spot — fully cash-funded)
  int openedAtMs;
  int updatedAtMs;

  SimPosition({
    required this.id,
    required this.accountId,
    required this.symbol,
    required this.market,
    required this.mode,
    required this.side,
    required this.qty,
    required this.avgPrice,
    this.leverage = 1,
    this.marginUsed = 0,
    required this.openedAtMs,
    required this.updatedAtMs,
  });

  /// Position value at [price] (notional).
  double notional(double price) => qty * price;

  /// Cost basis (what you paid / the notional at entry).
  double get costBasis => qty * avgPrice;

  /// Unrealized P/L at [price], respecting direction. Leverage doesn't change
  /// P/L in currency (it changes the collateral, i.e. the % return on margin).
  double unrealizedPnl(double price) {
    final dir = side == PositionSide.long ? 1.0 : -1.0;
    return (price - avgPrice) * qty * dir;
  }

  /// Return on the collateral actually put up (leverage-aware). Computed from
  /// native quote-currency quantities so it's independent of FX conversion
  /// (marginUsed may be stored in a different base currency).
  double roiPct(double price) {
    final basis = mode == TradeMode.margin && leverage > 0
        ? costBasis / leverage
        : costBasis;
    if (basis == 0) return 0;
    return unrealizedPnl(price) / basis * 100;
  }

  /// Price at which the position's equity is wiped out (margin only).
  /// long:  entry * (1 - 1/leverage);  short: entry * (1 + 1/leverage).
  double? get liquidationPrice {
    if (mode != TradeMode.margin || leverage < 1) return null;
    final f = 1 / leverage;
    final liq = side == PositionSide.long
        ? avgPrice * (1 - f)
        : avgPrice * (1 + f);
    // A 1x long liquidates only at price 0 (unreachable, price is floored above
    // 0), so report none. A 1x short DOES liquidate — at 2x entry — so keep it.
    if (side == PositionSide.long && liq <= 0) return null;
    return liq;
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'symbol': symbol,
        'market': market.index,
        'mode': mode.index,
        'side': side.index,
        'qty': qty,
        'avg_price': avgPrice,
        'leverage': leverage,
        'margin_used': marginUsed,
        'opened_at': openedAtMs,
        'updated_at': updatedAtMs,
      };

  factory SimPosition.fromMap(Map<String, Object?> m) => SimPosition(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        symbol: m['symbol'] as String,
        market: _enumAt(SimMarket.values, m['market'], SimMarket.stocks),
        mode: _enumAt(TradeMode.values, m['mode'], TradeMode.spot),
        side: _enumAt(PositionSide.values, m['side'], PositionSide.long),
        qty: _d(m['qty'], 0),
        avgPrice: _d(m['avg_price'], 0),
        leverage: _d(m['leverage'], 1),
        marginUsed: _d(m['margin_used'], 0),
        openedAtMs: (m['opened_at'] as int?) ?? 0,
        updatedAtMs: (m['updated_at'] as int?) ?? 0,
      );
}

// ---- Order -------------------------------------------------------------------

class SimOrder {
  String id;
  String accountId;
  String symbol;
  SimMarket market;
  TradeMode mode;
  OrderSide side;
  OrderType type;
  double qty;
  double leverage;
  double? limitPrice; // for limit
  double? stopPrice; // for stop / take-profit trigger
  bool reduceOnly; // closes/reduces an existing position only
  OrderStatus status;
  double? fillPrice;
  int createdAtMs;
  int? filledAtMs;

  SimOrder({
    required this.id,
    required this.accountId,
    required this.symbol,
    required this.market,
    required this.mode,
    required this.side,
    required this.type,
    required this.qty,
    this.leverage = 1,
    this.limitPrice,
    this.stopPrice,
    this.reduceOnly = false,
    this.status = OrderStatus.open,
    this.fillPrice,
    required this.createdAtMs,
    this.filledAtMs,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'symbol': symbol,
        'market': market.index,
        'mode': mode.index,
        'side': side.index,
        'type': type.index,
        'qty': qty,
        'leverage': leverage,
        'limit_price': limitPrice,
        'stop_price': stopPrice,
        'reduce_only': reduceOnly ? 1 : 0,
        'status': status.index,
        'fill_price': fillPrice,
        'created_at': createdAtMs,
        'filled_at': filledAtMs,
      };

  factory SimOrder.fromMap(Map<String, Object?> m) => SimOrder(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        symbol: m['symbol'] as String,
        market: _enumAt(SimMarket.values, m['market'], SimMarket.stocks),
        mode: _enumAt(TradeMode.values, m['mode'], TradeMode.spot),
        side: _enumAt(OrderSide.values, m['side'], OrderSide.buy),
        type: _enumAt(OrderType.values, m['type'], OrderType.market),
        qty: _d(m['qty'], 0),
        leverage: _d(m['leverage'], 1),
        limitPrice: _dn(m['limit_price']),
        stopPrice: _dn(m['stop_price']),
        reduceOnly: (m['reduce_only'] as int? ?? 0) == 1,
        status: _enumAt(OrderStatus.values, m['status'], OrderStatus.open),
        fillPrice: _dn(m['fill_price']),
        createdAtMs: (m['created_at'] as int?) ?? 0,
        filledAtMs: m['filled_at'] as int?,
      );
}

// ---- Trade (executed fill / blotter) ----------------------------------------

class SimTrade {
  String id;
  String accountId;
  String symbol;
  SimMarket market;
  TradeMode mode;
  OrderSide side;
  double qty;
  double price;
  double fee;
  double realizedPnl; // non-zero when this fill closed/reduced a position
  int tsMs;

  SimTrade({
    required this.id,
    required this.accountId,
    required this.symbol,
    required this.market,
    required this.mode,
    required this.side,
    required this.qty,
    required this.price,
    this.fee = 0,
    this.realizedPnl = 0,
    required this.tsMs,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'symbol': symbol,
        'market': market.index,
        'mode': mode.index,
        'side': side.index,
        'qty': qty,
        'price': price,
        'fee': fee,
        'realized_pnl': realizedPnl,
        'ts': tsMs,
      };

  factory SimTrade.fromMap(Map<String, Object?> m) => SimTrade(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        symbol: m['symbol'] as String,
        market: _enumAt(SimMarket.values, m['market'], SimMarket.stocks),
        mode: _enumAt(TradeMode.values, m['mode'], TradeMode.spot),
        side: _enumAt(OrderSide.values, m['side'], OrderSide.buy),
        qty: _d(m['qty'], 0),
        price: _d(m['price'], 0),
        fee: _d(m['fee'], 0),
        realizedPnl: _d(m['realized_pnl'], 0),
        tsMs: (m['ts'] as int?) ?? 0,
      );
}

// ---- Watchlist ---------------------------------------------------------------

class SimWatch {
  String id;
  String accountId;
  String symbol;
  SimMarket market;
  int addedAtMs;

  SimWatch({
    required this.id,
    required this.accountId,
    required this.symbol,
    required this.market,
    required this.addedAtMs,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'symbol': symbol,
        'market': market.index,
        'added_at': addedAtMs,
      };

  factory SimWatch.fromMap(Map<String, Object?> m) => SimWatch(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        symbol: m['symbol'] as String,
        market: _enumAt(SimMarket.values, m['market'], SimMarket.stocks),
        addedAtMs: (m['added_at'] as int?) ?? 0,
      );
}

// ---- Quote (live price snapshot; not persisted) -----------------------------

class SimQuote {
  final String symbol;
  final double price;
  final double prevClose;
  final int tsMs;
  const SimQuote(this.symbol, this.price, this.prevClose, this.tsMs);

  double get changePct =>
      prevClose == 0 ? 0 : (price - prevClose) / prevClose * 100;
}

// ---- helpers -----------------------------------------------------------------

double _d(Object? v, double fallback) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : fallback;
  }
  if (v is String) {
    final d = double.tryParse(v);
    return (d != null && d.isFinite) ? d : fallback;
  }
  return fallback;
}

double? _dn(Object? v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) {
    final d = double.tryParse(v);
    return (d != null && d.isFinite) ? d : null;
  }
  return null;
}

/// Safe enum decode from a stored index — an out-of-range or non-int value
/// (e.g. a corrupted/hand-edited sandbox DB, or an enum case removed in a later
/// version) falls back to [fallback] instead of throwing RangeError.
T _enumAt<T>(List<T> values, Object? idx, T fallback) {
  if (idx is int && idx >= 0 && idx < values.length) return values[idx];
  return fallback;
}

/// Convenience for JSON round-tripping a list of maps (used in tests/exports).
String encodeMaps(List<Map<String, Object?>> rows) => jsonEncode(rows);
