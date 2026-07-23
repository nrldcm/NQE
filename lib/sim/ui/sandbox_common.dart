// Shared presentational helpers for the Sandbox (Simulation Trading) UI.
// Theme-aware, matching the NQE design system in lib/theme.dart + widgets/common.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme.dart';
import '../sim_models.dart';

/// Sensible price precision per market (forex needs 4–5 dp, penny crypto more).
int priceDecimals(SimMarket market, double price) {
  switch (market) {
    case SimMarket.forex:
      return price >= 50 ? 3 : 5; // JPY pairs vs the rest
    case SimMarket.crypto:
      if (price >= 100) return 2;
      if (price >= 1) return 4;
      return 6;
    case SimMarket.stocks:
      return 2;
  }
}

String fmtPrice(double price, SimMarket market) {
  final d = priceDecimals(market, price);
  return NumberFormat('#,##0.${'0' * d}').format(price);
}

/// Account-currency money (Sandbox accounts are USD by default).
String simMoney(double v, {String currency = 'USD', int decimals = 2}) {
  final sym = currency == 'USD'
      ? '\$'
      : currency == 'PHP'
          ? '₱'
          : '$currency ';
  return NumberFormat.currency(symbol: sym, decimalDigits: decimals).format(v);
}

String simSignedMoney(double v, {String currency = 'USD'}) {
  final s = simMoney(v.abs(), currency: currency);
  if (v > 0) return '+$s';
  if (v < 0) return '-$s';
  return s;
}

String fmtQty(double q) =>
    q == q.roundToDouble() ? q.toStringAsFixed(0) : NumberFormat('#,##0.####').format(q);

String signedPctStr(double v, {int decimals = 2}) {
  final s = '${v.abs().toStringAsFixed(decimals)}%';
  if (v > 0) return '+$s';
  if (v < 0) return '-$s';
  return s;
}

Color marketColor(SimMarket m) => switch (m) {
      SimMarket.stocks => const Color(0xFF4C8DFF),
      SimMarket.forex => const Color(0xFFB07CF6),
      SimMarket.crypto => const Color(0xFFF39A3B),
    };

IconData marketIcon(SimMarket m) => switch (m) {
      SimMarket.stocks => Icons.business_center_outlined,
      SimMarket.forex => Icons.currency_exchange,
      SimMarket.crypto => Icons.currency_bitcoin,
    };

/// A framed panel matching the app's card styling.
class SimCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  const SimCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.color});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.line),
      ),
      child: child,
    );
  }
}

/// A small coloured badge for a market.
class MarketBadge extends StatelessWidget {
  final SimMarket market;
  final bool dense;
  const MarketBadge(this.market, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final c = marketColor(market);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        marketLabel(market).toUpperCase(),
        style: TextStyle(
            color: c,
            fontSize: dense ? 9 : 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5),
      ),
    );
  }
}

/// A price label that briefly flashes green/red when it moves.
class FlashPrice extends StatefulWidget {
  final double price;
  final SimMarket market;
  final TextStyle style;

  /// Identity of the series (usually the symbol). When it changes, the widget
  /// resets its baseline instead of flashing a spurious move.
  final Object? tag;
  const FlashPrice(
      {super.key,
      required this.price,
      required this.market,
      required this.style,
      this.tag});

  @override
  State<FlashPrice> createState() => _FlashPriceState();
}

class _FlashPriceState extends State<FlashPrice> {
  double? _last;
  int _dir = 0; // -1 down, 0 none, 1 up

  @override
  void didUpdateWidget(covariant FlashPrice old) {
    super.didUpdateWidget(old);
    if (widget.tag != old.tag) {
      // Different instrument — reset baseline, don't flash.
      _dir = 0;
      _last = widget.price;
      return;
    }
    if (_last != null && widget.price != _last) {
      _dir = widget.price > _last! ? 1 : -1;
    }
    _last = widget.price;
  }

  @override
  Widget build(BuildContext context) {
    _last ??= widget.price;
    final flash = _dir == 0
        ? widget.style.color
        : (_dir > 0 ? NqeColors.gain : NqeColors.loss);
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.price),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      builder: (context, t, _) {
        final color = Color.lerp(flash, widget.style.color, t) ?? widget.style.color;
        return Text(fmtPrice(widget.price, widget.market),
            style: widget.style.copyWith(color: color));
      },
    );
  }
}
