// Sandbox trading engine — pure, in-memory, deterministic. Handles order
// placement, fills (market immediately; limit/stop/TP on price ticks),
// position accounting for SPOT and MARGIN (leverage, long/short, weighted
// average, realized P/L), buying-power checks, and liquidations.
//
// It operates on a [SimPortfolio] value object and a price lookup; persistence
// and price feeding live elsewhere. No timers, no I/O — fully unit-testable.
import 'dart:math';

import 'sim_models.dart';

/// The mutable state the engine works on: one account + its positions + pending
/// (open) orders.
class SimPortfolio {
  SimAccount account;
  List<SimPosition> positions;
  List<SimOrder> orders; // OrderStatus.open only

  SimPortfolio({
    required this.account,
    List<SimPosition>? positions,
    List<SimOrder>? orders,
  })  : positions = positions ?? [],
        orders = orders ?? [];
}

/// A single change the engine produced, so the caller can persist exactly what
/// moved (and refresh the UI).
class SimEffect {
  final List<SimTrade> trades;
  final List<SimOrder> filledOrders;
  final List<SimOrder> newOrders;
  final List<String> closedPositionIds;
  final List<String> liquidatedSymbols; // symbols force-closed by liquidation
  final List<String> removedOrderIds; // pending orders cancelled/rejected on tick
  final String? rejectReason;
  const SimEffect({
    this.trades = const [],
    this.filledOrders = const [],
    this.newOrders = const [],
    this.closedPositionIds = const [],
    this.liquidatedSymbols = const [],
    this.removedOrderIds = const [],
    this.rejectReason,
  });
  bool get rejected => rejectReason != null;
}

class SimEngine {
  /// Trading fee rate by market (round-trip is charged per fill).
  static double feeRate(SimMarket m) => switch (m) {
        SimMarket.stocks => 0.0025,
        SimMarket.forex => 0.0002,
        SimMarket.crypto => 0.001,
        SimMarket.indices => 0.0002,
        SimMarket.commodities => 0.0005,
      };

  /// Identity FX — used when no converter is supplied (single-currency).
  static double _one(String _) => 1.0;

  // ---- valuation -----------------------------------------------------------

  /// Total account value = free cash + spot holdings at market + (for margin)
  /// locked collateral + unrealized P/L. All position values are converted to
  /// the account's base currency via [fxOf] (multiplier from the instrument's
  /// quote currency to base); collateral is already stored in base.
  static double equity(SimPortfolio p, double Function(String) priceOf,
      {double Function(String)? fxOf}) {
    final fx = fxOf ?? _one;
    var eq = p.account.cash;
    for (final pos in p.positions) {
      final px = priceOf(pos.symbol);
      final f = fx(pos.symbol);
      if (pos.mode == TradeMode.spot) {
        eq += pos.notional(px) * f;
      } else {
        eq += pos.marginUsed + pos.unrealizedPnl(px) * f;
      }
    }
    return eq;
  }

  static double unrealized(SimPortfolio p, double Function(String) priceOf,
      {double Function(String)? fxOf}) {
    final fx = fxOf ?? _one;
    var u = 0.0;
    for (final pos in p.positions) {
      u += pos.unrealizedPnl(priceOf(pos.symbol)) * fx(pos.symbol);
    }
    return u;
  }

  /// Free cash available to open new exposure.
  static double freeCash(SimPortfolio p) => p.account.cash;

  // ---- order placement -----------------------------------------------------

  /// Place an order. Market orders fill immediately at [priceOf]; limit/stop/TP
  /// are stored and later triggered by [onTick]. Returns the resulting effect
  /// (or a rejection with a reason).
  static SimEffect placeOrder(
    SimPortfolio p,
    SimOrder order, {
    required double Function(String) priceOf,
    required int nowMs,
    required String Function() uid,
    double slippage = 0,
    double Function(String)? fxOf,
  }) {
    final fx = fxOf ?? _one;
    if (!(order.qty > 0) || !order.qty.isFinite) {
      return const SimEffect(rejectReason: 'Quantity must be greater than 0.');
    }
    final lev = order.mode == TradeMode.margin ? order.leverage : 1.0;
    if (lev < 1 || lev > p.account.maxLeverage) {
      return SimEffect(
          rejectReason: 'Leverage must be 1–${p.account.maxLeverage.toInt()}x.');
    }
    if (order.mode == TradeMode.margin && !p.account.marginEnabled) {
      return const SimEffect(rejectReason: 'Margin is disabled on this account.');
    }
    // Spot can't go net short.
    if (order.mode == TradeMode.spot && order.side == OrderSide.sell) {
      final held = _netQty(p, order.symbol, TradeMode.spot);
      if (order.qty > held + 1e-9) {
        return const SimEffect(
            rejectReason: 'You can only sell what you hold (no shorting in spot).');
      }
    }

    // Reduce-only orders must never open or flip a position.
    if (order.reduceOnly) {
      final avail = _reducibleQty(p, order);
      if (avail <= 1e-9) {
        return const SimEffect(rejectReason: 'Nothing to close on this side.');
      }
      if (avail < order.qty) order.qty = avail;
    }

    if (order.type == OrderType.market) {
      final px = _fillPrice(priceOf(order.symbol), order.side, slippage);
      if (!(px > 0)) {
        return const SimEffect(rejectReason: 'No price available for this symbol.');
      }
      final afford = _affordCheck(p, order, px, fx);
      if (afford != null) return SimEffect(rejectReason: afford);
      final t = _applyFill(p, order, px, nowMs: nowMs, uid: uid, fx: fx);
      order.status = OrderStatus.filled;
      order.fillPrice = px;
      order.filledAtMs = nowMs;
      return SimEffect(trades: [t.trade], filledOrders: [order], closedPositionIds: t.closedIds);
    }

    // Pending order — validate affordability against its own limit/stop price.
    final ref = order.limitPrice ?? order.stopPrice ?? priceOf(order.symbol);
    final afford = _affordCheck(p, order, ref, fx);
    if (afford != null) return SimEffect(rejectReason: afford);
    order.status = OrderStatus.open;
    p.orders.add(order);
    return SimEffect(newOrders: [order]);
  }

  /// Advance the book on a fresh set of prices: trigger pending orders and run
  /// liquidations. Returns everything that changed.
  static SimEffect onTick(
    SimPortfolio p, {
    required double Function(String) priceOf,
    required int nowMs,
    required String Function() uid,
    double slippage = 0,
    double Function(String)? fxOf,
  }) {
    final fx = fxOf ?? _one;
    final trades = <SimTrade>[];
    final filled = <SimOrder>[];
    final closed = <String>[];
    final liquidated = <String>[];
    final removed = <String>[]; // pending orders cancelled/rejected this tick

    // 1) Pending order triggers.
    for (final o in p.orders.toList()) {
      if (o.status != OrderStatus.open) continue;
      final mkt = priceOf(o.symbol);
      if (!(mkt > 0)) continue;
      if (_triggered(o, mkt)) {
        // Reduce-only (stop-loss / take-profit / OCO leg): clamp to what's
        // actually open on the opposing side; cancel if the position is gone
        // so it can never open fresh exposure.
        if (o.reduceOnly) {
          final avail = _reducibleQty(p, o);
          if (avail <= 1e-9) {
            o.status = OrderStatus.cancelled;
            p.orders.remove(o);
            removed.add(o.id);
            continue;
          }
          if (avail < o.qty) o.qty = avail;
        }
        final px = _fillPrice(
            o.type == OrderType.limit ? (o.limitPrice ?? mkt) : mkt,
            o.side,
            slippage);
        final afford = _affordCheck(p, o, px, fx);
        if (afford != null) {
          o.status = OrderStatus.rejected;
          p.orders.remove(o);
          removed.add(o.id);
          continue;
        }
        final r = _applyFill(p, o, px, nowMs: nowMs, uid: uid, fx: fx);
        o.status = OrderStatus.filled;
        o.fillPrice = px;
        o.filledAtMs = nowMs;
        p.orders.remove(o);
        trades.add(r.trade);
        filled.add(o);
        closed.addAll(r.closedIds);
      }
    }

    // 2) Liquidations (margin positions whose equity is wiped out).
    for (final pos in p.positions.toList()) {
      if (pos.mode != TradeMode.margin) continue;
      final px = priceOf(pos.symbol);
      if (!(px > 0)) continue;
      final liq = pos.liquidationPrice;
      if (liq == null) continue;
      final hit = pos.side == PositionSide.long ? px <= liq : px >= liq;
      if (hit) {
        // Force-close the whole position at the liquidation price.
        final closeOrder = SimOrder(
          id: uid(),
          accountId: pos.accountId,
          symbol: pos.symbol,
          market: pos.market,
          mode: TradeMode.margin,
          side: pos.side == PositionSide.long ? OrderSide.sell : OrderSide.buy,
          type: OrderType.market,
          qty: pos.qty,
          leverage: pos.leverage,
          reduceOnly: true,
          createdAtMs: nowMs,
        );
        final r = _applyFill(p, closeOrder, liq, nowMs: nowMs, uid: uid, fx: fx);
        trades.add(r.trade);
        closed.addAll(r.closedIds);
        liquidated.add(pos.symbol);
      }
    }

    return SimEffect(
        trades: trades,
        filledOrders: filled,
        closedPositionIds: closed,
        liquidatedSymbols: liquidated,
        removedOrderIds: removed);
  }

  static void cancelOrder(SimPortfolio p, String orderId) {
    p.orders.removeWhere((o) => o.id == orderId);
  }

  /// Quantity a (reduce-only) order can actually close on the opposing side —
  /// 0 if there's nothing to reduce (so it must be cancelled, never opened).
  static double _reducibleQty(SimPortfolio p, SimOrder o) {
    final pos = _posFor(p, o.symbol, o.mode);
    if (pos == null) return 0;
    final reduces =
        (pos.side == PositionSide.long && o.side == OrderSide.sell) ||
            (pos.side == PositionSide.short && o.side == OrderSide.buy);
    if (!reduces) return 0;
    return min(o.qty, pos.qty);
  }

  // ---- internals -----------------------------------------------------------

  static bool _triggered(SimOrder o, double mkt) {
    switch (o.type) {
      case OrderType.market:
        return true;
      case OrderType.limit:
        // buy limit fills when price <= limit; sell limit when price >= limit.
        final lp = o.limitPrice;
        if (lp == null) return false;
        return o.side == OrderSide.buy ? mkt <= lp : mkt >= lp;
      case OrderType.stop:
        final sp = o.stopPrice;
        if (sp == null) return false;
        // stop-buy triggers when price >= stop; stop-sell when price <= stop.
        return o.side == OrderSide.buy ? mkt >= sp : mkt <= sp;
      case OrderType.takeProfit:
        final tp = o.stopPrice;
        if (tp == null) return false;
        // Take-profit is the mirror of a stop: a long's TP-sell fires when
        // price RISES to the target; a short's TP-buy fires when it FALLS.
        return o.side == OrderSide.buy ? mkt <= tp : mkt >= tp;
    }
  }

  static double _fillPrice(double mkt, OrderSide side, double slippage) {
    if (slippage <= 0) return mkt;
    return side == OrderSide.buy ? mkt * (1 + slippage) : mkt * (1 - slippage);
  }

  static double _netQty(SimPortfolio p, String symbol, TradeMode mode) {
    for (final pos in p.positions) {
      if (pos.symbol == symbol && pos.mode == mode) {
        return pos.side == PositionSide.long ? pos.qty : -pos.qty;
      }
    }
    return 0;
  }

  static SimPosition? _posFor(SimPortfolio p, String symbol, TradeMode mode) {
    for (final pos in p.positions) {
      if (pos.symbol == symbol && pos.mode == mode) return pos;
    }
    return null;
  }

  /// Affordability / margin check. Returns a reason string if rejected, else
  /// null. [fx] converts the instrument's quote currency to the account's base
  /// currency, so all comparisons happen in base (e.g. PHP).
  static String? _affordCheck(
      SimPortfolio p, SimOrder o, double price, double Function(String) fx) {
    if (!(price > 0)) return 'No price available.';
    final f = fx(o.symbol);
    final fee = o.qty * price * feeRate(o.market) * f;
    final net = _netQty(p, o.symbol, o.mode);
    final incoming = o.side == OrderSide.buy ? o.qty : -o.qty;
    // Only the portion that INCREASES exposure needs new funds; reducing frees.
    final increasing = net == 0 || net.sign == incoming.sign
        ? o.qty
        : max(0.0, o.qty - net.abs());
    if (increasing <= 0) return null; // pure reduce/close — always allowed
    if (o.mode == TradeMode.spot) {
      final need = increasing * price * f + fee;
      if (need > p.account.cash + 1e-6) {
        return 'Not enough cash (need ${need.toStringAsFixed(2)}).';
      }
    } else {
      final collateral = increasing * price * f / o.leverage;
      if (collateral + fee > p.account.cash + 1e-6) {
        return 'Not enough margin (need ${(collateral + fee).toStringAsFixed(2)} collateral).';
      }
    }
    return null;
  }

  static ({SimTrade trade, List<String> closedIds}) _applyFill(
    SimPortfolio p,
    SimOrder o,
    double price, {
    required int nowMs,
    required String Function() uid,
    double Function(String)? fx,
  }) {
    // All cash movements, collateral and realized P/L are kept in the account's
    // base currency: multiply quote-currency amounts by [f]. avgPrice/qty stay
    // in the instrument's native quote units.
    final f = (fx ?? _one)(o.symbol);
    final fee = o.qty * price * feeRate(o.market) * f;
    final closedIds = <String>[];
    var realized = 0.0;

    var pos = _posFor(p, o.symbol, o.mode);
    final incoming = o.side == OrderSide.buy ? o.qty : -o.qty;
    final oldNet =
        pos == null ? 0.0 : (pos.side == PositionSide.long ? pos.qty : -pos.qty);
    final newNet = oldNet + incoming;

    if (o.mode == TradeMode.spot) {
      // Spot: net >= 0 always. Buy adds, sell reduces.
      if (o.side == OrderSide.buy) {
        p.account.cash -= o.qty * price * f + fee;
        if (pos == null) {
          pos = SimPosition(
            id: uid(),
            accountId: o.accountId,
            symbol: o.symbol,
            market: o.market,
            mode: TradeMode.spot,
            side: PositionSide.long,
            qty: o.qty,
            avgPrice: price,
            openedAtMs: nowMs,
            updatedAtMs: nowMs,
          );
          p.positions.add(pos);
        } else {
          final newQty = pos.qty + o.qty;
          pos.avgPrice = (pos.avgPrice * pos.qty + price * o.qty) / newQty;
          pos.qty = newQty;
          pos.updatedAtMs = nowMs;
        }
      } else {
        // sell (reduce long)
        final sellQty = min(o.qty, pos?.qty ?? 0);
        realized = (price - (pos?.avgPrice ?? price)) * sellQty * f;
        p.account.cash += sellQty * price * f - fee;
        p.account.realizedPnl += realized;
        if (pos != null) {
          pos.qty -= sellQty;
          pos.updatedAtMs = nowMs;
          if (pos.qty <= 1e-9) {
            closedIds.add(pos.id);
            p.positions.remove(pos);
          }
        }
      }
    } else {
      // MARGIN.
      final incSign = incoming.sign;
      final oldSign = oldNet.sign;
      if (oldNet == 0 || incSign == oldSign) {
        // Opening or increasing in the same direction. Collateral in base ccy.
        final addCollateral = o.qty * price * f / o.leverage;
        p.account.cash -= addCollateral + fee;
        if (pos == null) {
          pos = SimPosition(
            id: uid(),
            accountId: o.accountId,
            symbol: o.symbol,
            market: o.market,
            mode: TradeMode.margin,
            side: incoming > 0 ? PositionSide.long : PositionSide.short,
            qty: o.qty,
            avgPrice: price,
            leverage: o.leverage,
            marginUsed: addCollateral,
            openedAtMs: nowMs,
            updatedAtMs: nowMs,
          );
          p.positions.add(pos);
        } else {
          final newQty = pos.qty + o.qty;
          pos.avgPrice = (pos.avgPrice * pos.qty + price * o.qty) / newQty;
          pos.qty = newQty;
          pos.marginUsed += addCollateral;
          pos.updatedAtMs = nowMs;
        }
      } else {
        // Reducing / closing / flipping.
        final reduceQty = min(o.qty, oldNet.abs());
        final dir = oldSign; // +1 long, -1 short
        realized = (price - (pos?.avgPrice ?? price)) * reduceQty * dir * f;
        // marginUsed is already stored in base currency.
        final released = (pos != null && pos.qty > 0)
            ? pos.marginUsed * (reduceQty / pos.qty)
            : 0.0;
        p.account.cash += released + realized - fee;
        p.account.realizedPnl += realized;
        if (pos != null) {
          pos.qty -= reduceQty;
          pos.marginUsed -= released;
          pos.updatedAtMs = nowMs;
          if (pos.qty <= 1e-9) {
            closedIds.add(pos.id);
            p.positions.remove(pos);
          }
        }
        // Flip: leftover opens a new position the other way.
        final leftover = o.qty - reduceQty;
        if (leftover > 1e-9) {
          final addCollateral = leftover * price * f / o.leverage;
          p.account.cash -= addCollateral; // fee already charged above
          final np = SimPosition(
            id: uid(),
            accountId: o.accountId,
            symbol: o.symbol,
            market: o.market,
            mode: TradeMode.margin,
            side: incoming > 0 ? PositionSide.long : PositionSide.short,
            qty: leftover,
            avgPrice: price,
            leverage: o.leverage,
            marginUsed: addCollateral,
            openedAtMs: nowMs,
            updatedAtMs: nowMs,
          );
          p.positions.add(np);
        }
      }
    }

    // Guard against FP dust.
    if (!p.account.cash.isFinite) p.account.cash = 0;
    final trade = SimTrade(
      id: uid(),
      accountId: o.accountId,
      symbol: o.symbol,
      market: o.market,
      mode: o.mode,
      side: o.side,
      qty: o.qty,
      price: price,
      fee: fee,
      realizedPnl: realized,
      tsMs: nowMs,
    );
    p.account.updatedAtMs = nowMs;
    // silence unused
    assert(newNet == newNet);
    return (trade: trade, closedIds: closedIds);
  }
}
