// v2 — Live market view: an embedded TradingView advanced chart (WebView).
// Requires network. The symbol is editable; the chart follows the app theme.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final _symbolCtrl = TextEditingController(text: 'NASDAQ:AAPL');
  late final WebViewController _web;
  bool _initialised = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _initialised = true;
      _load();
    }
  }

  @override
  void dispose() {
    _symbolCtrl.dispose();
    super.dispose();
  }

  void _load() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? '#0a0a0a' : '#ffffff';
    final symbol = _symbolCtrl.text.trim().isEmpty
        ? 'NASDAQ:AAPL'
        : _symbolCtrl.text.trim().toUpperCase();
    setState(() => _loading = true);
    _web.setBackgroundColor(dark ? const Color(0xFF0A0A0A) : Colors.white);
    _web.loadHtmlString(_html(symbol, dark ? 'dark' : 'light', bg));
  }

  String _html(String symbol, String theme, String bg) => '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>html,body{height:100%;margin:0;background:$bg;overflow:hidden}#tv{height:100%;width:100%}</style>
</head>
<body>
<div id="tv"></div>
<script src="https://s3.tradingview.com/tv.js"></script>
<script>
  try {
    new TradingView.widget({
      container_id: "tv",
      symbol: "$symbol",
      interval: "D",
      timezone: "Asia/Manila",
      theme: "$theme",
      style: "1",
      locale: "en",
      autosize: true,
      hide_side_toolbar: false,
      allow_symbol_change: true,
      withdateranges: true,
      studies: []
    });
  } catch (e) {
    document.body.innerHTML =
      '<div style="color:#999;font-family:sans-serif;padding:24px;text-align:center">'+
      'Could not load live chart. Check your internet connection.</div>';
  }
</script>
</body>
</html>
''';

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        titleSpacing: 16,
        title: SizedBox(
          height: 40,
          child: TextField(
            controller: _symbolCtrl,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _load(),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Symbol e.g. NASDAQ:AAPL, PSE:SPNEC',
              prefixIcon: Icon(Icons.show_chart, size: 18, color: pal.textLo),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Load',
            icon: const Icon(Icons.arrow_forward),
            onPressed: _load,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _web),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
