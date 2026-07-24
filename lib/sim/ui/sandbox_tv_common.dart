// Shared (platform-independent) helpers for the real TradingView Advanced
// Chart embed: internal-symbol → TradingView symbol mapping, and the widget's
// HTML. No dart:io / dart:html here, so both the mobile (WebView) and the web
// (iframe) implementations can import it.
import '../sim_market.dart';
import '../sim_models.dart';

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

/// The full TradingView Advanced Chart widget page (their real chart with their
/// own indicators, drawing tools and timeframes). Identical on mobile (loaded
/// into a WebView) and web (loaded into an iframe), so the chart looks the same
/// everywhere.
String tvHtml(String symbol, String theme, String bg) => '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>html,body{height:100%;width:100%;margin:0;padding:0;background:$bg;overflow:hidden}
/* The chart container MUST fill the viewport: TradingView's autosize reads
   this element's height, so if it collapses to content-height the widget
   renders at its ~120px minimum. Absolute inset:0 pins it to the full page,
   and the iframe TradingView injects inside inherits that 100% height. */
#tv{position:absolute;top:0;left:0;right:0;bottom:0;width:100%;height:100%}
#tv iframe{width:100%!important;height:100%!important}</style>
</head>
<body>
<div id="tv"></div>
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
