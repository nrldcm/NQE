// Desktop Live tab — embedded TradingView chart via WebView2 (webview_windows).
// Mirrors the mobile Live tab. If the WebView2 runtime is unavailable, it falls
// back to a button that opens the chart in the system browser.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../theme.dart';

class DesktopLiveScreen extends StatefulWidget {
  const DesktopLiveScreen({super.key});

  @override
  State<DesktopLiveScreen> createState() => _DesktopLiveScreenState();
}

class _DesktopLiveScreenState extends State<DesktopLiveScreen> {
  final _controller = WebviewController();
  final _symbolCtrl = TextEditingController(text: 'NASDAQ:AAPL');
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(const Color(0xFF0A0A0A));
      if (!mounted) return;
      setState(() => _ready = true);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _symbol() {
    final s = _symbolCtrl.text.trim().toUpperCase();
    return s.isEmpty ? 'NASDAQ:AAPL' : s;
  }

  String _embedUrl(String symbol, bool dark) {
    final theme = dark ? 'dark' : 'light';
    final sym = Uri.encodeComponent(symbol);
    // The same widget the mobile tv.js embed loads internally — usable directly.
    return 'https://s.tradingview.com/widgetembed/?frameElementId=tv'
        '&symbol=$sym&interval=D&theme=$theme&style=1&locale=en'
        '&timezone=Asia/Manila&withdateranges=1&hideideas=1&hide_side_toolbar=0'
        '&allow_symbol_change=1';
  }

  Future<void> _load() async {
    if (!_ready) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    try {
      await _controller.loadUrl(_embedUrl(_symbol(), dark));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _openInBrowser() async {
    final dark =
        MediaQuery.maybeOf(context)?.platformBrightness == Brightness.dark;
    final uri = Uri.parse(_embedUrl(_symbol(), dark));
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* ignore */}
  }

  @override
  void dispose() {
    _symbolCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _symbolCtrl,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) =>
                        _failed ? _openInBrowser() : _load(),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Symbol e.g. NASDAQ:AAPL, PSE:SPNEC',
                      prefixIcon:
                          Icon(Icons.show_chart, size: 18, color: pal.textLo),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _failed ? _openInBrowser : _load,
                child: Text(_failed ? 'Open' : 'Load'),
              ),
            ],
          ),
        ),
        Expanded(child: _body(pal)),
      ],
    );
  }

  Widget _body(NqePalette pal) {
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.public_off, size: 44, color: pal.textLo),
              const SizedBox(height: 16),
              Text(
                'The embedded chart needs the Microsoft Edge WebView2 runtime. '
                'You can open the live chart in your browser instead.',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.textLo, height: 1.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in browser'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return Webview(_controller);
  }
}
