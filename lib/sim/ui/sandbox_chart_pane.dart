// Chart pane for the Sandbox: switches between the real TradingView chart
// (mobile, live market data + their full toolset) and the built-in candlestick
// chart (offline + mirrors the simulated feed and your sandbox trades).
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../sim_models.dart';
import 'sandbox_candle_chart.dart';
import 'sandbox_tradingview.dart';

class SandboxChartPane extends StatefulWidget {
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
  State<SandboxChartPane> createState() => _SandboxChartPaneState();
}

class _SandboxChartPaneState extends State<SandboxChartPane> {
  // Prefer the richer TradingView chart where it's supported (mobile).
  late bool _tv = tradingViewSupported;

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tradingViewSupported)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: pal.surface2,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _seg('TradingView', _tv, () => setState(() => _tv = true)),
                  _seg('Built-in', !_tv, () => setState(() => _tv = false)),
                ],
              ),
            ),
          ),
        if (tradingViewSupported) const SizedBox(height: 8),
        if (_tv && tradingViewSupported)
          SandboxTradingViewChart(
              symbol: widget.symbol, height: widget.height + 30)
        else
          SandboxCandleChart(
              symbol: widget.symbol,
              market: widget.market,
              height: widget.height),
      ],
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) {
    final pal = context.nqe;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? pal.bg : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: active ? Border.all(color: pal.line) : null,
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? pal.textHi : pal.textLo,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}
