// Web (dart:html) implementation of the real TradingView Advanced Chart embed.
// Registers a platform view backed by an <iframe> whose srcdoc is the same
// widget HTML used on mobile, so the chart looks identical everywhere.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'sandbox_tv_common.dart';

/// The TradingView iframe embed is always available on web.
bool get tradingViewSupportedImpl => true;

/// Build the TradingView iframe embed for web.
Widget buildTradingViewChart({
  required String symbol,
  required double height,
  required bool dark,
}) {
  return _TvIframeChart(symbol: symbol, height: height, dark: dark);
}

class _TvIframeChart extends StatefulWidget {
  final String symbol;
  final double height;
  final bool dark;
  const _TvIframeChart({
    required this.symbol,
    required this.height,
    required this.dark,
  });

  @override
  State<_TvIframeChart> createState() => _TvIframeChartState();
}

class _TvIframeChartState extends State<_TvIframeChart> {
  late String _viewType;
  String? _blobUrl;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(covariant _TvIframeChart old) {
    super.didUpdateWidget(old);
    if (old.symbol != widget.symbol || old.dark != widget.dark) {
      setState(_register);
    }
  }

  @override
  void dispose() {
    _revokeBlob();
    super.dispose();
  }

  void _revokeBlob() {
    final u = _blobUrl;
    if (u != null) {
      try {
        html.Url.revokeObjectUrl(u);
      } catch (_) {}
      _blobUrl = null;
    }
  }

  void _register() {
    // A unique viewType per (symbol, theme, instance) so re-registering after a
    // symbol/theme change produces a fresh iframe.
    final theme = widget.dark ? 'dark' : 'light';
    _viewType = 'tv-${identityHashCode(this)}-${widget.symbol}-$theme';
    final bg = widget.dark ? '#0A0A0A' : '#FFFFFF';
    final srcdoc = tvHtml(tvSymbolFor(widget.symbol), theme, bg);
    // IMPORTANT: load the widget HTML from a blob: URL, NOT srcdoc. A srcdoc
    // iframe has an opaque/null origin, and TradingView's tv.js refuses to
    // initialise there ("Chart unavailable"). A blob: URL inherits the served
    // page's origin, so the widget loads normally.
    _revokeBlob();
    final blob = html.Blob(<Object>[srcdoc], 'text/html');
    _blobUrl = html.Url.createObjectUrlFromBlob(blob);
    final url = _blobUrl!;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final iframe = html.IFrameElement()
        ..src = url
        ..allowFullscreen = true
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
