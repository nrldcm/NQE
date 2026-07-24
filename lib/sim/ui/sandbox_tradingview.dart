// Real TradingView Advanced Chart embed (their full widget: live symbols, their
// own indicators, drawing tools, timeframes). Platform-independent shell: the
// actual embed comes from a WebView on mobile (sandbox_tv_io.dart) or an iframe
// on web (sandbox_tv_web.dart), picked by conditional import so no dart:io is
// referenced on web and no dart:html on mobile. Shows REAL market data (not the
// simulated feed), so it's a reference chart alongside the built-in one.
import 'package:flutter/material.dart';

import 'sandbox_tv_io.dart' if (dart.library.html) 'sandbox_tv_web.dart'
    as tvimpl;

/// True where the real TradingView embed can be shown (mobile WebView or web
/// iframe). False on desktop native (no WebView target).
bool get tradingViewSupported => tvimpl.tradingViewSupportedImpl;

class SandboxTradingViewChart extends StatelessWidget {
  final String symbol;
  final double height;
  const SandboxTradingViewChart({
    super.key,
    required this.symbol,
    this.height = 360,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return tvimpl.buildTradingViewChart(
      symbol: symbol,
      height: height,
      dark: dark,
    );
  }
}
