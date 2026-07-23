// Embeds the real TradingView Advanced Chart (their full widget: live symbols,
// their own indicators, drawing tools, timeframes) inside a WebView. Mobile
// only — webview_flutter targets Android/iOS; the desktop keeps the built-in
// candlestick chart. Shows REAL market data (not the simulated feed), so it's a
// reference chart alongside the sim-accurate built-in one.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme.dart';
import '../sim_market.dart';
import '../sim_models.dart';

/// True where a WebView is available for the TradingView embed.
bool get tradingViewSupported =>
    Platform.isAndroid || Platform.isIOS;

/// Map an internal instrument code to a TradingView symbol (exchange-qualified).
String tvSymbolFor(String symbol) {
  final up = symbol.toUpperCase();
  if (up == 'PSEI') return 'PSE:PSEI';
  final m = instrumentFor(up)?.market;
  const idx = {
    'US500': 'SP:SPX', 'US100': 'NASDAQ:NDX', 'US30': 'DJ:DJI',
    'US2000': 'TVC:RUT', 'JP225': 'TVC:NI225', 'GER40': 'XETR:DAX',
    'UK100': 'TVC:UKX', 'FRA40': 'TVC:CAC40', 'EU50': 'TVC:SX5E',
    'HK50': 'TVC:HSI', 'AUS200': 'ASX:XJO', 'INDIA50': 'NSE:NIFTY',
  };
  const comm = {
    'XAUUSD': 'OANDA:XAUUSD', 'XAGUSD': 'OANDA:XAGUSD',
    'XPTUSD': 'OANDA:XPTUSD', 'XPDUSD': 'OANDA:XPDUSD',
    'WTIUSD': 'TVC:USOIL', 'BRENTUSD': 'TVC:UKOIL', 'NATGAS': 'TVC:NATGAS',
    'COPPER': 'TVC:COPPER', 'WHEAT': 'TVC:WHEAT', 'CORN': 'TVC:CORN',
    'COFFEE': 'TVC:COFFEE1!', 'SUGAR': 'TVC:SUGAR1!',
  };
  switch (m) {
    case SimMarket.crypto:
      return 'BINANCE:$up';
    case SimMarket.indices:
      return idx[up] ?? up;
    case SimMarket.commodities:
      return comm[up] ?? 'OANDA:$up';
    case SimMarket.forex:
      return 'FX_IDC:$up';
    case SimMarket.stocks:
      return kPseTickers.contains(up) ? 'PSE:$up' : up;
    case null:
      return up;
  }
}

class SandboxTradingViewChart extends StatefulWidget {
  final String symbol;
  final double height;
  const SandboxTradingViewChart({
    super.key,
    required this.symbol,
    this.height = 360,
  });

  @override
  State<SandboxTradingViewChart> createState() =>
      _SandboxTradingViewChartState();
}

class _SandboxTradingViewChartState extends State<SandboxTradingViewChart> {
  WebViewController? _controller;
  bool _dark = true;

  @override
  void initState() {
    super.initState();
    if (tradingViewSupported) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark != _dark || _controller?.currentUrl == null) {
      _dark = dark;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant SandboxTradingViewChart old) {
    super.didUpdateWidget(old);
    if (old.symbol != widget.symbol) _load();
  }

  void _load() {
    final c = _controller;
    if (c == null) return;
    final pal = context.nqe;
    final bg = _dark ? '#0A0A0A' : '#FFFFFF';
    final tvSym = tvSymbolFor(widget.symbol);
    final theme = _dark ? 'dark' : 'light';
    c.setBackgroundColor(pal.bg);
    c.loadHtmlString(_html(tvSym, theme, bg));
  }

  String _html(String symbol, String theme, String bg) => '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>html,body{height:100%;margin:0;padding:0;background:$bg;overflow:hidden}
#wrap{position:absolute;inset:0}</style>
</head>
<body>
<div id="wrap"><div id="tv"></div></div>
<script src="https://s3.tradingview.com/tv.js"></script>
<script>
try {
  new TradingView.widget({
    "autosize": true,
    "symbol": "$symbol",
    "interval": "15",
    "timezone": "Asia/Manila",
    "theme": "$theme",
    "style": "1",
    "locale": "en",
    "enable_publishing": false,
    "allow_symbol_change": true,
    "hide_side_toolbar": false,
    "withdateranges": true,
    "details": false,
    "container_id": "tv"
  });
} catch (e) { document.body.innerHTML = '<p style="color:#888;font-family:sans-serif;padding:16px">Chart unavailable offline.</p>'; }
</script>
</body>
</html>
''';

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    if (!tradingViewSupported || _controller == null) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text('TradingView chart is available on mobile.',
              style: TextStyle(color: pal.textLo, fontSize: 12)),
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: WebViewWidget(controller: _controller!),
      ),
    );
  }
}
