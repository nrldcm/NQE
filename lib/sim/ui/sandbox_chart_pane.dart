// Chart pane for the Sandbox. The chart ALWAYS matches the fill engine, so an
// order "hits" exactly when the price you see crosses it:
//   * Simulated feed → the built-in candlestick chart, whose right edge is the
//     simulated engine price (the same price orders fill against);
//   * Live feed + crypto → the real TradingView chart, and the engine fills
//     against the same live Binance price.
// The Live/Simulated pill (in the header) is the single control.
import 'package:flutter/material.dart';

import '../sim_models.dart';
import '../sim_state.dart';
import 'sandbox_candle_chart.dart';
import 'sandbox_tradingview.dart';

class SandboxChartPane extends StatelessWidget {
  final String symbol;
  final SimMarket market;
  final double height;
  const SandboxChartPane({
    super.key,
    required this.symbol,
    required this.market,
    this.height = 300,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: simState,
      builder: (context, _) {
        final live = simState.price.mode == FeedMode.live;
        // Show TradingView only when the engine is ALSO on real prices for this
        // instrument (live feed + crypto), so the chart and fills never diverge.
        final useTv =
            live && tradingViewSupported && market == SimMarket.crypto;
        if (useTv) {
          return SandboxTradingViewChart(symbol: symbol, height: height + 62);
        }
        return SandboxCandleChart(
            symbol: symbol, market: market, height: height);
      },
    );
  }
}
