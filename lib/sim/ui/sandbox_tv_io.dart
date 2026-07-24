// Mobile/desktop (dart:io) implementation of the real TradingView Advanced
// Chart embed. On Android/iOS it loads the widget HTML into a WebView; on
// desktop native (no webview_flutter target) it shows a small placeholder and
// reports the embed unsupported so callers fall back to the built-in chart.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'sandbox_tv_common.dart';

/// True where a WebView is available for the TradingView embed.
bool get tradingViewSupportedImpl => Platform.isAndroid || Platform.isIOS;

/// Build the TradingView embed for the current io platform.
Widget buildTradingViewChart({
  required String symbol,
  required double height,
  required bool dark,
}) {
  return _TvWebViewChart(symbol: symbol, height: height, dark: dark);
}

class _TvWebViewChart extends StatefulWidget {
  final String symbol;
  final double height;
  final bool dark;
  const _TvWebViewChart({
    required this.symbol,
    required this.height,
    required this.dark,
  });

  @override
  State<_TvWebViewChart> createState() => _TvWebViewChartState();
}

class _TvWebViewChartState extends State<_TvWebViewChart> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    if (tradingViewSupportedImpl) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant _TvWebViewChart old) {
    super.didUpdateWidget(old);
    if (old.symbol != widget.symbol || old.dark != widget.dark) _load();
  }

  void _load() {
    final c = _controller;
    if (c == null) return;
    final bg = widget.dark ? '#0A0A0A' : '#FFFFFF';
    final theme = widget.dark ? 'dark' : 'light';
    final tvSym = tvSymbolFor(widget.symbol);
    c.loadHtmlString(tvHtml(tvSym, theme, bg));
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      // Desktop native: no WebView target. Keep it quiet — the caller falls
      // back to the built-in candlestick chart.
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'TradingView chart is available on mobile and web.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: WebViewWidget(controller: c),
      ),
    );
  }
}
