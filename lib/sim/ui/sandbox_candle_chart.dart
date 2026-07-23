// TradingView / Binance-style candlestick chart for the Sandbox: a timeframe
// selector (1m · 5m · 15m · 1H · 4H · 1D · 1W · 1M), a live-forming candle, a
// price axis, a dashed last-price line, and a draggable crosshair with an OHLC
// read-out. Real Binance candles for crypto on the Live feed; a realistic
// simulated series otherwise.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../theme.dart';
import '../sim_candles.dart';
import '../sim_models.dart';
import '../sim_state.dart';
import 'sandbox_common.dart';

class SandboxCandleChart extends StatefulWidget {
  final String symbol;
  final SimMarket market;
  final double height;
  const SandboxCandleChart({
    super.key,
    required this.symbol,
    required this.market,
    this.height = 260,
  });

  @override
  State<SandboxCandleChart> createState() => _SandboxCandleChartState();
}

class _SandboxCandleChartState extends State<SandboxCandleChart> {
  Timeframe _tf = Timeframe.m15;
  int? _cross;
  String _fetchedKey = '';

  void _maybeFetchLive() {
    final live = simState.price.mode == FeedMode.live;
    final key = '${widget.symbol}|${_tf.name}|$live';
    if (key == _fetchedKey) return;
    _fetchedKey = key;
    if (live && widget.market == SimMarket.crypto) {
      simState.candles.fetchLive(widget.symbol, _tf);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    _maybeFetchLive();

    // Advance the forming candle, then read the series.
    final price = simState.priceOf(widget.symbol);
    simState.candles.update(widget.symbol, _tf, price);
    final candles = simState.candles.series(widget.symbol, _tf, price);

    final shown = (_cross != null && _cross! >= 0 && _cross! < candles.length)
        ? candles[_cross!]
        : (candles.isNotEmpty ? candles.last : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ohlcBar(context, shown),
        const SizedBox(height: 6),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, c) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _updateCross(d.localPosition.dx,
                    c.maxWidth, candles.length),
                onHorizontalDragUpdate: (d) => _updateCross(
                    d.localPosition.dx, c.maxWidth, candles.length),
                onHorizontalDragEnd: (_) => setState(() => _cross = null),
                onTap: () => setState(() => _cross = null),
                child: CustomPaint(
                  size: Size(c.maxWidth, widget.height),
                  painter: _CandlePainter(
                    candles: candles,
                    market: widget.market,
                    tf: _tf,
                    cross: _cross,
                    up: NqeColors.gain,
                    down: NqeColors.loss,
                    grid: pal.line,
                    textColor: pal.textLo,
                    bg: pal.surface,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _selector(context),
      ],
    );
  }

  void _updateCross(double dx, double width, int n) {
    if (n == 0) return;
    const rightAxis = 58.0;
    final plotW = (width - rightAxis).clamp(1.0, double.infinity);
    final i = (dx / plotW * n).floor().clamp(0, n - 1);
    setState(() => _cross = i);
  }

  Widget _ohlcBar(BuildContext context, SimCandle? c) {
    final pal = context.nqe;
    if (c == null) return const SizedBox(height: 18);
    final up = c.c >= c.o;
    final col = up ? NqeColors.gain : NqeColors.loss;
    final chg = c.o == 0 ? 0.0 : (c.c - c.o) / c.o * 100;
    TextSpan kv(String k, double v) => TextSpan(children: [
          TextSpan(
              text: '$k ',
              style: TextStyle(color: pal.textLo, fontSize: 10)),
          TextSpan(
              text: '${fmtPrice(v, widget.market)}  ',
              style: TextStyle(
                  color: col, fontSize: 10, fontWeight: FontWeight.w700)),
        ]);
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(children: [
                kv('O', c.o),
                kv('H', c.h),
                kv('L', c.l),
                kv('C', c.c),
              ]),
            ),
          ),
          Text('${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%',
              style: TextStyle(
                  color: col, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _selector(BuildContext context) {
    final pal = context.nqe;
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final tf in Timeframe.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() {
                  _tf = tf;
                  _cross = null;
                }),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: tf == _tf ? pal.textHi.withOpacity(0.12) : pal.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: tf == _tf ? pal.textHi.withOpacity(0.4) : pal.line),
                  ),
                  child: Text(tf.label,
                      style: TextStyle(
                          color: tf == _tf ? pal.textHi : pal.textLo,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  final List<SimCandle> candles;
  final SimMarket market;
  final Timeframe tf;
  final int? cross;
  final Color up, down, grid, textColor, bg;

  _CandlePainter({
    required this.candles,
    required this.market,
    required this.tf,
    required this.cross,
    required this.up,
    required this.down,
    required this.grid,
    required this.textColor,
    required this.bg,
  });

  static const double _rightAxis = 58;
  static const double _bottomAxis = 16;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.length < 2) return;
    final plotW = size.width - _rightAxis;
    final plotH = size.height - _bottomAxis;

    var lo = double.infinity, hi = -double.infinity;
    for (final c in candles) {
      if (c.l < lo) lo = c.l;
      if (c.h > hi) hi = c.h;
    }
    if (!(hi > lo)) {
      hi = lo + (lo.abs() * 0.01 + 1);
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    double y(double p) => plotH * (hi - p) / (hi - lo);

    final n = candles.length;
    final cw = plotW / n;
    final bodyW = (cw * 0.62).clamp(1.0, 18.0);

    // Grid + right price axis.
    final gridPaint = Paint()
      ..color = grid.withOpacity(0.5)
      ..strokeWidth = 1;
    const rows = 4;
    for (var i = 0; i <= rows; i++) {
      final yy = plotH * i / rows;
      canvas.drawLine(Offset(0, yy), Offset(plotW, yy), gridPaint);
      final price = hi - (hi - lo) * i / rows;
      _text(canvas, fmtPrice(price, market), Offset(plotW + 4, yy - 6),
          textColor, 9);
    }

    // Time axis (sparse labels).
    final labelEvery = (n / 4).ceil();
    for (var i = 0; i < n; i += labelEvery) {
      final x = i * cw + cw / 2;
      _text(canvas, _timeLabel(candles[i].t),
          Offset(x - 14, plotH + 2), textColor, 9);
    }

    // Candles.
    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final cx = i * cw + cw / 2;
      final bull = c.c >= c.o;
      final col = bull ? up : down;
      final wick = Paint()
        ..color = col
        ..strokeWidth = 1;
      canvas.drawLine(Offset(cx, y(c.h)), Offset(cx, y(c.l)), wick);
      final top = y(bull ? c.c : c.o);
      final bot = y(bull ? c.o : c.c);
      final rect = Rect.fromLTRB(
          cx - bodyW / 2, top, cx + bodyW / 2, bot < top + 1 ? top + 1 : bot);
      canvas.drawRect(rect, Paint()..color = col);
    }

    // Last price dashed line + label.
    final last = candles.last;
    final lastY = y(last.c);
    final lastCol = last.c >= last.o ? up : down;
    _dashed(canvas, Offset(0, lastY), Offset(plotW, lastY), lastCol);
    final lblRect = Rect.fromLTWH(plotW, lastY - 8, _rightAxis, 16);
    canvas.drawRect(lblRect, Paint()..color = lastCol);
    _text(canvas, fmtPrice(last.c, market), Offset(plotW + 3, lastY - 6),
        Colors.white, 9, bold: true);

    // Crosshair.
    if (cross != null && cross! >= 0 && cross! < n) {
      final c = candles[cross!];
      final cx = cross! * cw + cw / 2;
      final cy = y(c.c);
      final chPaint = Paint()
        ..color = textColor.withOpacity(0.6)
        ..strokeWidth = 1;
      _dashedV(canvas, cx, 0, plotH, chPaint);
      _dashed(canvas, Offset(0, cy), Offset(plotW, cy),
          textColor.withOpacity(0.6));
    }
  }

  String _timeLabel(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final intraday = tf.bucketMs < 24 * 60 * 60 * 1000;
    return DateFormat(intraday ? 'HH:mm' : 'MMM d').format(d);
  }

  void _text(Canvas canvas, String s, Offset at, Color color, double size,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: color,
              fontSize: size,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0, gap = 3.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * (d + dash).clamp(0, total);
      canvas.drawLine(s, e, paint);
      d += dash + gap;
    }
  }

  void _dashedV(Canvas canvas, double x, double y0, double y1, Paint paint) {
    const dash = 4.0, gap = 3.0;
    var y = y0;
    while (y < y1) {
      canvas.drawLine(Offset(x, y), Offset(x, (y + dash).clamp(y0, y1)), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.candles != candles ||
      old.cross != cross ||
      old.candles.length != candles.length ||
      (candles.isNotEmpty &&
          old.candles.isNotEmpty &&
          old.candles.last.c != candles.last.c);
}
