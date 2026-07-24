// Chart pane for the Sandbox. Two views, switchable with a small toggle:
//   * "Chart"       → the built-in candlestick chart. Its right edge is the
//                     engine price (the same price orders fill against), and it
//                     keeps its own drawing tools (drawings persist).
//   * "TradingView" → the real TradingView Advanced Chart (their widget, live
//                     symbols, their indicators and drawing tools). Shows real
//                     market data. Available on mobile (WebView) and web
//                     (iframe); hidden on platforms without an embed.
// The default follows the feed: on the simulated feed the built-in chart is
// selected (so chart and fills never diverge); on the live crypto feed the
// TradingView chart is selected. The user can flip anytime — the choice is kept
// in memory for the life of the pane.
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../sim_models.dart';
import '../sim_state.dart';
import 'sandbox_candle_chart.dart';
import 'sandbox_tradingview.dart';

enum _ChartView { custom, tradingView }

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
  // null = follow the feed default; non-null = user-picked override.
  _ChartView? _choice;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: simState,
      builder: (context, _) {
        final live = simState.price.mode == FeedMode.live;
        // The feed default: TradingView when the engine is also on real prices
        // for this instrument (live + crypto), else the built-in chart.
        final defaultView =
            (live && widget.market == SimMarket.crypto)
                ? _ChartView.tradingView
                : _ChartView.custom;
        final view = _choice ?? defaultView;

        if (!tradingViewSupported) {
          // No embed on this platform — only the built-in chart is possible.
          return SandboxCandleChart(
              symbol: widget.symbol, market: widget.market, height: widget.height);
        }

        final showTv = view == _ChartView.tradingView;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: _ChartViewToggle(
                value: view,
                onChanged: (v) => setState(() => _choice = v),
              ),
            ),
            const SizedBox(height: 8),
            if (showTv)
              // Give TradingView a tall footprint so it fills the chart area
              // like the built-in chart (which adds indicator sub-panels).
              SandboxTradingViewChart(
                  symbol: widget.symbol, height: widget.height + 120)
            else
              SandboxCandleChart(
                  symbol: widget.symbol,
                  market: widget.market,
                  height: widget.height),
          ],
        );
      },
    );
  }
}

/// Small two-option segmented toggle switching between the built-in chart and
/// the real TradingView embed. Styled from the theme palette.
class _ChartViewToggle extends StatelessWidget {
  final _ChartView value;
  final ValueChanged<_ChartView> onChanged;
  const _ChartViewToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: pal.line),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChartViewSegment(
            label: 'Chart',
            icon: Icons.candlestick_chart,
            selected: value == _ChartView.custom,
            onTap: () => onChanged(_ChartView.custom),
          ),
          _ChartViewSegment(
            label: 'TradingView',
            icon: Icons.show_chart,
            selected: value == _ChartView.tradingView,
            onTap: () => onChanged(_ChartView.tradingView),
          ),
        ],
      ),
    );
  }
}

class _ChartViewSegment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ChartViewSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final fg = selected ? pal.bg : pal.textLo;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? pal.textHi : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
