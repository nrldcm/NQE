// TradingView / Binance-style candlestick chart for the Sandbox: a timeframe
// selector (1m · 5m · 15m · 1H · 4H · 1D · 1W · 1M), a live-forming candle, a
// price axis, a dashed last-price line, a draggable crosshair with an OHLC
// read-out, and toggleable technical indicators — MA / EMA / Bollinger overlays
// plus Volume, RSI and MACD sub-panels. Real Binance candles for crypto on the
// Live feed; a realistic simulated series otherwise.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../theme.dart';
import '../sim_candles.dart';
import '../sim_indicators.dart';
import '../sim_models.dart';
import '../sim_state.dart';
import 'sandbox_common.dart';

// Overlay + sub-panel indicator keys.
const _kMa = 'MA';
const _kEma = 'EMA';
const _kBoll = 'BOLL';
const _kVol = 'VOL';
const _kRsi = 'RSI';
const _kMacd = 'MACD';
const _kWma = 'WMA';
const _kVwap = 'VWAP';
const _kStoch = 'STOCH';
const _kAtr = 'ATR';
const _kObv = 'OBV';

const _maColors = [Color(0xFFF0B90B), Color(0xFFE354C4), Color(0xFF7C4DFF)];
const _emaColor = Color(0xFF29B6F6);
const _bollColor = Color(0xFF5C9CE6);
const _rsiColor = Color(0xFF9C6ADE);
const _macdLine = Color(0xFF29B6F6);
const _signalLine = Color(0xFFF0B90B);
const _wmaColor = Color(0xFFEC407A);
const _vwapColor = Color(0xFFFFA726);
const _stochK = Color(0xFF29B6F6);
const _stochD = Color(0xFFF0B90B);
const _atrColor = Color(0xFF26C6DA);
const _obvColor = Color(0xFF66BB6A);

// Colour for user-drawn tools (TradingView-style blue).
const _drawColor = Color(0xFF2962FF);

/// Left-rail drawing tools.
enum _DrawTool { cursor, hline, trend }

/// A user-placed horizontal price line.
class _HLine {
  final double price;
  const _HLine(this.price);
}

/// A user-drawn trend line, stored in (fractionOfPlotWidth, price) space so it
/// tracks the chart's transform as new candles arrive.
class _TrendLine {
  final double fx1, p1, fx2, p2;
  const _TrendLine(this.fx1, this.p1, this.fx2, this.p2);
}

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
  final Set<String> _ind = {_kMa, _kVol};

  // ---- drawing tools -------------------------------------------------------
  _DrawTool _tool = _DrawTool.cursor;
  final List<_HLine> _hlines = [];
  final List<_TrendLine> _trends = [];
  _TrendLine? _trendPreview;
  // Cached plot geometry from the last build, so gestures can map screen
  // positions to price / fractional-x exactly like the painter does.
  double _lo = 0, _hi = 1, _plotW = 1;

  void _maybeFetchLive() {
    final live = simState.price.mode == FeedMode.live;
    final key = '${widget.symbol}|${_tf.name}|$live';
    if (key == _fetchedKey) return;
    _fetchedKey = key;
    if (live && widget.market == SimMarket.crypto) {
      simState.candles.fetchLive(widget.symbol, _tf);
    }
  }

  int get _subCount =>
      (_ind.contains(_kVol) ? 1 : 0) +
      (_ind.contains(_kRsi) ? 1 : 0) +
      (_ind.contains(_kMacd) ? 1 : 0) +
      (_ind.contains(_kStoch) ? 1 : 0) +
      (_ind.contains(_kAtr) ? 1 : 0) +
      (_ind.contains(_kObv) ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    _maybeFetchLive();

    final price = simState.priceOf(widget.symbol);
    simState.candles.update(widget.symbol, _tf, price);
    final candles = simState.candles.series(widget.symbol, _tf, price);

    final shown = (_cross != null && _cross! >= 0 && _cross! < candles.length)
        ? candles[_cross!]
        : (candles.isNotEmpty ? candles.last : null);

    final closes = [for (final c in candles) c.c];
    // Volume proxy is shared by the Volume panel, VWAP and OBV.
    final needVol =
        _ind.contains(_kVol) || _ind.contains(_kVwap) || _ind.contains(_kObv);
    final volume = needVol ? volumeProxy(candles) : const <double>[];
    final data = _IndicatorData(
      ma: _ind.contains(_kMa)
          ? [sma(closes, 7), sma(closes, 25), sma(closes, 99)]
          : null,
      ema: _ind.contains(_kEma) ? ema(closes, 21) : null,
      boll: _ind.contains(_kBoll) ? bollinger(closes) : null,
      wma: _ind.contains(_kWma) ? wma(closes, 21) : null,
      vwap: _ind.contains(_kVwap) ? vwap(candles, volume) : null,
      vol: _ind.contains(_kVol) ? volume : null,
      rsi: _ind.contains(_kRsi) ? rsi(closes) : null,
      macd: _ind.contains(_kMacd) ? macd(closes) : null,
      stoch: _ind.contains(_kStoch) ? stochastic(candles) : null,
      atr: _ind.contains(_kAtr) ? atr(candles) : null,
      obv: _ind.contains(_kObv) ? obv(candles, volume) : null,
    );
    final totalHeight = widget.height + _subCount * 68.0;

    // Compute the main-panel price range ONCE here so the painter and the
    // drawing-tool gestures share an identical price<->y mapping (no drift).
    _computeRange(candles, data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Binance-style chart toolbar: a compact timeframe SELECT, the
        // Indicators tool, and (room for) more chart tools, all in one row.
        Row(
          children: [
            _tfDropdown(context),
            const SizedBox(width: 8),
            _toolButton(context, Icons.candlestick_chart_outlined, 'Indicators',
                _openIndicators),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 6),
        _ohlcBar(context, shown),
        const SizedBox(height: 4),
        SizedBox(
          height: totalHeight,
          child: ValueListenableBuilder<SimOrderLine?>(
            valueListenable: simOrderLine,
            builder: (context, ol, _) {
              // Only the price line for THIS symbol is drawn here.
              final line = (ol != null && ol.symbol == widget.symbol) ? ol : null;
              return LayoutBuilder(
                builder: (context, c) {
                  final width = c.maxWidth;
                  _plotW = (width - 58.0).clamp(1.0, double.infinity);
                  return Stack(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => _onTapDown(d.localPosition, width,
                            candles.length),
                        onTap: _onTap,
                        onPanStart: (d) =>
                            _onPanStart(d.localPosition, width, candles.length),
                        onPanUpdate: (d) => _onPanUpdate(
                            d.localPosition, width, candles.length),
                        onPanEnd: (_) => _onPanEnd(),
                        child: CustomPaint(
                          size: Size(width, totalHeight),
                          painter: _CandlePainter(
                            candles: candles,
                            market: widget.market,
                            tf: _tf,
                            cross: _cross,
                            data: data,
                            mainHeight: widget.height,
                            lo: _lo,
                            hi: _hi,
                            up: NqeColors.gain,
                            down: NqeColors.loss,
                            grid: pal.line,
                            textColor: pal.textLo,
                            orderLine: line?.price,
                            orderUp: line?.isBuy ?? true,
                            hlines: _hlines,
                            trends: _trends,
                            trendPreview: _trendPreview,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        child: _drawingRail(context),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
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

  /// Replicates the painter's main-panel price range (min low / max high, with
  /// Bollinger bands and any pending-order line included, plus 8% padding) so
  /// the widget can map a tapped y-position to a price identically.
  void _computeRange(List<SimCandle> candles, _IndicatorData data) {
    if (candles.isEmpty) {
      _lo = 0;
      _hi = 1;
      return;
    }
    var lo = double.infinity, hi = -double.infinity;
    for (final c in candles) {
      if (c.l < lo) lo = c.l;
      if (c.h > hi) hi = c.h;
    }
    if (data.boll != null) {
      for (var i = 0; i < candles.length; i++) {
        final u = data.boll!.upper[i], l = data.boll!.lower[i];
        if (u != null && u > hi) hi = u;
        if (l != null && l < lo) lo = l;
      }
    }
    final ol = simOrderLine.value;
    if (ol != null && ol.symbol == widget.symbol) {
      final p = ol.price;
      if (p.isFinite && p > 0) {
        if (p > hi) hi = p;
        if (p < lo) lo = p;
      }
    }
    if (!(hi > lo)) hi = lo + (lo.abs() * 0.01 + 1);
    final pad = (hi - lo) * 0.08;
    _lo = lo - pad;
    _hi = hi + pad;
  }

  double _priceFromY(double dy) {
    final h = widget.height;
    final f = (dy.clamp(0.0, h)) / h;
    return _hi - (_hi - _lo) * f;
  }

  double _fxFromX(double dx) => (dx.clamp(0.0, _plotW)) / _plotW;

  // ---- tool-aware gesture handlers ----------------------------------------

  void _onTapDown(Offset p, double width, int n) {
    switch (_tool) {
      case _DrawTool.cursor:
        _updateCross(p.dx, width, n);
      case _DrawTool.hline:
        setState(() => _hlines.add(_HLine(_priceFromY(p.dy))));
      case _DrawTool.trend:
        break; // trend lines are drawn with a drag
    }
  }

  void _onTap() {
    if (_tool == _DrawTool.cursor) setState(() => _cross = null);
  }

  void _onPanStart(Offset p, double width, int n) {
    switch (_tool) {
      case _DrawTool.cursor:
        _updateCross(p.dx, width, n);
      case _DrawTool.trend:
        final fx = _fxFromX(p.dx), price = _priceFromY(p.dy);
        setState(() => _trendPreview = _TrendLine(fx, price, fx, price));
      case _DrawTool.hline:
        break;
    }
  }

  void _onPanUpdate(Offset p, double width, int n) {
    switch (_tool) {
      case _DrawTool.cursor:
        _updateCross(p.dx, width, n);
      case _DrawTool.trend:
        final prev = _trendPreview;
        if (prev != null) {
          setState(() => _trendPreview =
              _TrendLine(prev.fx1, prev.p1, _fxFromX(p.dx), _priceFromY(p.dy)));
        }
      case _DrawTool.hline:
        break;
    }
  }

  void _onPanEnd() {
    switch (_tool) {
      case _DrawTool.cursor:
        setState(() => _cross = null);
      case _DrawTool.trend:
        final prev = _trendPreview;
        setState(() {
          if (prev != null) _trends.add(prev);
          _trendPreview = null;
        });
      case _DrawTool.hline:
        break;
    }
  }

  /// TradingView-style vertical rail of drawing tools on the chart's left edge.
  Widget _drawingRail(BuildContext context) {
    final pal = context.nqe;
    Widget btn(_DrawTool tool, IconData icon, String tip) {
      final active = _tool == tool;
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: () => setState(() => _tool = tool),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: active ? _drawColor.withOpacity(0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: active ? _drawColor : Colors.transparent, width: 1),
            ),
            child: Icon(icon,
                size: 15, color: active ? _drawColor : pal.textLo),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(left: 2, top: 2),
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      decoration: BoxDecoration(
        color: pal.bg.withOpacity(0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(_DrawTool.cursor, Icons.near_me_outlined, 'Cursor / crosshair'),
          btn(_DrawTool.hline, Icons.horizontal_rule, 'Horizontal line'),
          btn(_DrawTool.trend, Icons.show_chart, 'Trend line'),
          Container(
            width: 16,
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 3),
            color: pal.line,
          ),
          Tooltip(
            message: 'Clear drawings',
            child: InkWell(
              onTap: (_hlines.isEmpty && _trends.isEmpty)
                  ? null
                  : () => setState(() {
                        _hlines.clear();
                        _trends.clear();
                        _trendPreview = null;
                      }),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.symmetric(vertical: 2),
                child: Icon(Icons.delete_outline,
                    size: 15,
                    color: (_hlines.isEmpty && _trends.isEmpty)
                        ? pal.textLo.withOpacity(0.4)
                        : pal.textLo),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openIndicators() async {
    final pal = context.nqe;
    await showModalBottomSheet(
      context: context,
      backgroundColor: pal.bg,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          Widget tile(String key, String title, String sub) => SwitchListTile(
                dense: true,
                value: _ind.contains(key),
                title: Text(title,
                    style: TextStyle(
                        color: pal.textHi, fontWeight: FontWeight.w600)),
                subtitle: Text(sub,
                    style: TextStyle(color: pal.textLo, fontSize: 12)),
                onChanged: (v) {
                  setSheet(() => setState(() {
                        if (v) {
                          _ind.add(key);
                        } else {
                          _ind.remove(key);
                        }
                      }));
                },
              );
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 20),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Indicators',
                    style: TextStyle(
                        color: pal.textHi,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ),
              tile(_kMa, 'Moving Average (MA 7/25/99)', 'Trend overlay'),
              tile(_kEma, 'EMA 21', 'Exponential moving average'),
              tile(_kWma, 'WMA 21', 'Weighted moving average overlay'),
              tile(_kVwap, 'VWAP', 'Volume-weighted average price overlay'),
              tile(_kBoll, 'Bollinger Bands', '20, 2σ volatility bands'),
              Divider(color: pal.line),
              tile(_kVol, 'Volume', 'Sub-panel'),
              tile(_kRsi, 'RSI (14)', 'Momentum, 0–100 sub-panel'),
              tile(_kMacd, 'MACD (12,26,9)', 'Trend/momentum sub-panel'),
              tile(_kStoch, 'Stochastic (14,3)', '%K / %D, 0–100 sub-panel'),
              tile(_kAtr, 'ATR (14)', 'Average true range sub-panel'),
              tile(_kObv, 'OBV', 'On-balance volume sub-panel'),
            ],
          );
        },
      ),
    );
  }

  Widget _ohlcBar(BuildContext context, SimCandle? c) {
    final pal = context.nqe;
    if (c == null) return const SizedBox(height: 18);
    final up = c.c >= c.o;
    final col = up ? NqeColors.gain : NqeColors.loss;
    final chg = c.o == 0 ? 0.0 : (c.c - c.o) / c.o * 100;
    TextSpan kv(String k, double v) => TextSpan(children: [
          TextSpan(
              text: '$k ', style: TextStyle(color: pal.textLo, fontSize: 10)),
          TextSpan(
              text: '${fmtPrice(v, widget.market)}  ',
              style: TextStyle(
                  color: col, fontSize: 10, fontWeight: FontWeight.w700)),
        ]);
    return SizedBox(
      height: 18,
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(children: [
          kv('O', c.o),
          kv('H', c.h),
          kv('L', c.l),
          kv('C', c.c),
          TextSpan(
              text: '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%',
              style: TextStyle(
                  color: col, fontSize: 10, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  /// Compact timeframe SELECT (Binance-style): shows the current interval and
  /// opens a menu of all timeframes — far tidier than a full chip row.
  Widget _tfDropdown(BuildContext context) {
    final pal = context.nqe;
    return PopupMenuButton<Timeframe>(
      tooltip: 'Timeframe',
      initialValue: _tf,
      color: pal.surface,
      position: PopupMenuPosition.under,
      onSelected: (tf) => setState(() {
        _tf = tf;
        _cross = null;
      }),
      itemBuilder: (context) => [
        for (final tf in Timeframe.values)
          PopupMenuItem<Timeframe>(
            value: tf,
            height: 40,
            child: Text(tf.label,
                style: TextStyle(
                    color: tf == _tf ? pal.textHi : pal.textLo,
                    fontWeight: tf == _tf ? FontWeight.w800 : FontWeight.w600)),
          ),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: pal.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: pal.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 13, color: pal.textLo),
            const SizedBox(width: 6),
            Text(_tf.label,
                style: TextStyle(
                    color: pal.textHi,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down, size: 16, color: pal.textLo),
          ],
        ),
      ),
    );
  }

  /// A framed toolbar button matching the timeframe select's height/shape, so
  /// the chart toolbar reads as one consistent row of controls.
  Widget _toolButton(BuildContext context, IconData icon, String label,
      VoidCallback onTap) {
    final pal = context.nqe;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: pal.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: pal.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: pal.textLo),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: pal.textHi,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Pre-computed indicator series for the painter (null = indicator off).
class _IndicatorData {
  final List<List<double?>>? ma; // [ma7, ma25, ma99]
  final List<double?>? ema;
  final ({List<double?> mid, List<double?> upper, List<double?> lower})? boll;
  final List<double?>? wma;
  final List<double?>? vwap;
  final List<double>? vol;
  final List<double?>? rsi;
  final ({List<double?> macd, List<double?> signal, List<double?> hist})? macd;
  final ({List<double?> k, List<double?> d})? stoch;
  final List<double?>? atr;
  final List<double?>? obv;
  const _IndicatorData(
      {this.ma,
      this.ema,
      this.boll,
      this.wma,
      this.vwap,
      this.vol,
      this.rsi,
      this.macd,
      this.stoch,
      this.atr,
      this.obv});
}

class _CandlePainter extends CustomPainter {
  final List<SimCandle> candles;
  final SimMarket market;
  final Timeframe tf;
  final int? cross;
  final _IndicatorData data;
  final double mainHeight;

  /// Main-panel price range (already padded), computed by the widget so its
  /// gesture math and this painter share one price<->y mapping.
  final double lo, hi;
  final Color up, down, grid, textColor;

  /// A pending-order price level to draw (from the ticket), and its side colour.
  final double? orderLine;
  final bool orderUp;

  /// User-drawn shapes from the left drawing-tools rail.
  final List<_HLine> hlines;
  final List<_TrendLine> trends;
  final _TrendLine? trendPreview;

  _CandlePainter({
    required this.candles,
    required this.market,
    required this.tf,
    required this.cross,
    required this.data,
    required this.mainHeight,
    required this.lo,
    required this.hi,
    required this.up,
    required this.down,
    required this.grid,
    required this.textColor,
    this.orderLine,
    this.orderUp = true,
    this.hlines = const [],
    this.trends = const [],
    this.trendPreview,
  });

  static const double _rightAxis = 58;
  static const double _bottomAxis = 16;
  static const double _subH = 62;
  static const double _subGap = 6;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.length < 2) return;
    final n = candles.length;
    final plotW = size.width - _rightAxis;
    final cw = plotW / n;
    final bodyW = (cw * 0.62).clamp(1.0, 18.0);
    double cx(int i) => i * cw + cw / 2;

    // ---- main price panel ----
    final mainH = mainHeight;
    // lo/hi (padded, including Bollinger + pending-order line) are supplied by
    // the widget via _computeRange so gesture math and painting stay in sync.
    final span = (hi - lo).abs() < 1e-12 ? 1.0 : (hi - lo);
    double my(double p) => mainH * (hi - p) / span;

    final gridPaint = Paint()
      ..color = grid.withOpacity(0.5)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final yy = mainH * i / 4;
      canvas.drawLine(Offset(0, yy), Offset(plotW, yy), gridPaint);
      _text(canvas, fmtPrice(hi - (hi - lo) * i / 4, market),
          Offset(plotW + 4, yy - 6), textColor, 9);
    }

    // Bollinger bands (behind candles).
    if (data.boll != null) {
      _line(canvas, data.boll!.upper, my, cx, _bollColor.withOpacity(0.7), 1);
      _line(canvas, data.boll!.lower, my, cx, _bollColor.withOpacity(0.7), 1);
      _line(canvas, data.boll!.mid, my, cx, _bollColor.withOpacity(0.4), 1);
    }

    // Candles.
    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final x = cx(i);
      final bull = c.c >= c.o;
      final col = bull ? up : down;
      canvas.drawLine(Offset(x, my(c.h)), Offset(x, my(c.l)),
          Paint()..color = col..strokeWidth = 1);
      final top = my(bull ? c.c : c.o);
      final bot = my(bull ? c.o : c.c);
      canvas.drawRect(
          Rect.fromLTRB(x - bodyW / 2, top, x + bodyW / 2,
              bot < top + 1 ? top + 1 : bot),
          Paint()..color = col);
    }

    // MA overlays.
    if (data.ma != null) {
      for (var k = 0; k < data.ma!.length; k++) {
        _line(canvas, data.ma![k], my, cx, _maColors[k % _maColors.length], 1.4);
      }
    }
    if (data.ema != null) _line(canvas, data.ema!, my, cx, _emaColor, 1.4);
    if (data.wma != null) _line(canvas, data.wma!, my, cx, _wmaColor, 1.4);
    if (data.vwap != null) _line(canvas, data.vwap!, my, cx, _vwapColor, 1.6);

    // Last price line.
    final last = candles.last;
    final lastY = my(last.c);
    final lastCol = last.c >= last.o ? up : down;
    _dashedH(canvas, lastY, plotW, lastCol);
    canvas.drawRect(Rect.fromLTWH(plotW, lastY - 8, _rightAxis, 16),
        Paint()..color = lastCol);
    _text(canvas, fmtPrice(last.c, market), Offset(plotW + 3, lastY - 6),
        Colors.white, 9, bold: true);

    // Pending-order price line (from the ticket): a solid coloured line with a
    // right-edge tag so the user sees exactly where their limit/stop sits.
    if (orderLine != null && orderLine!.isFinite && orderLine! > 0) {
      final oy = my(orderLine!);
      final oc = orderUp ? up : down;
      canvas.drawLine(Offset(0, oy), Offset(plotW, oy),
          Paint()..color = oc..strokeWidth = 1.2);
      canvas.drawRect(Rect.fromLTWH(plotW, oy - 8, _rightAxis, 16),
          Paint()..color = oc);
      _text(canvas, fmtPrice(orderLine!, market), Offset(plotW + 3, oy - 6),
          Colors.white, 9, bold: true);
    }

    // User-drawn shapes (horizontal + trend lines) from the left rail.
    _drawUserShapes(canvas, my, plotW);

    // ---- sub-panels ----
    var top = mainH + _subGap;
    if (data.vol != null) {
      _volPanel(canvas, top, plotW, cx, bodyW);
      top += _subH + _subGap;
    }
    if (data.rsi != null) {
      _rsiPanel(canvas, top, plotW, cx);
      top += _subH + _subGap;
    }
    if (data.macd != null) {
      _macdPanel(canvas, top, plotW, cx, bodyW);
      top += _subH + _subGap;
    }
    if (data.stoch != null) {
      _stochPanel(canvas, top, plotW, cx);
      top += _subH + _subGap;
    }
    if (data.atr != null) {
      _atrPanel(canvas, top, plotW, cx);
      top += _subH + _subGap;
    }
    if (data.obv != null) {
      _obvPanel(canvas, top, plotW, cx);
      top += _subH + _subGap;
    }

    // Time axis at the very bottom.
    final labelEvery = (n / 4).ceil();
    for (var i = 0; i < n; i += labelEvery) {
      _text(canvas, _timeLabel(candles[i].t),
          Offset(cx(i) - 14, size.height - _bottomAxis + 2), textColor, 9);
    }

    // Crosshair across everything.
    if (cross != null && cross! >= 0 && cross! < n) {
      final x = cx(cross!);
      final p = Paint()
        ..color = textColor.withOpacity(0.6)
        ..strokeWidth = 1;
      _dashedV(canvas, x, 0, size.height - _bottomAxis, p);
      final cyc = my(candles[cross!].c);
      _dashedH(canvas, cyc, plotW, textColor.withOpacity(0.6));
    }
  }

  // ---- sub-panels ----------------------------------------------------------

  void _volPanel(Canvas canvas, double top, double plotW,
      double Function(int) cx, double bodyW) {
    final vol = data.vol!;
    var mx = 0.0;
    for (final v in vol) {
      if (v > mx) mx = v;
    }
    if (mx <= 0) mx = 1;
    _panelFrame(canvas, top, plotW, 'Vol');
    for (var i = 0; i < candles.length; i++) {
      final h = (vol[i] / mx) * (_subH - 12);
      final col = (candles[i].c >= candles[i].o ? up : down).withOpacity(0.5);
      canvas.drawRect(
          Rect.fromLTWH(cx(i) - bodyW / 2, top + _subH - h, bodyW, h),
          Paint()..color = col);
    }
  }

  void _rsiPanel(Canvas canvas, double top, double plotW,
      double Function(int) cx) {
    _panelFrame(canvas, top, plotW, 'RSI');
    double y(double v) => top + (_subH) * (1 - v / 100);
    // 30 / 70 guides.
    for (final lvl in [30.0, 70.0]) {
      _dashedH2(canvas, y(lvl), plotW, grid.withOpacity(0.7));
      _text(canvas, lvl.toStringAsFixed(0), Offset(plotW + 4, y(lvl) - 6),
          textColor, 8);
    }
    _lineAbs(canvas, data.rsi!, y, cx, _rsiColor, 1.2);
  }

  void _macdPanel(Canvas canvas, double top, double plotW,
      double Function(int) cx, double bodyW) {
    _panelFrame(canvas, top, plotW, 'MACD');
    final m = data.macd!;
    var mx = 1e-9;
    for (var i = 0; i < candles.length; i++) {
      for (final v in [m.macd[i], m.signal[i], m.hist[i]]) {
        if (v != null && v.abs() > mx) mx = v.abs();
      }
    }
    double y(double v) => top + _subH / 2 - (v / mx) * (_subH / 2 - 4);
    // Histogram.
    for (var i = 0; i < candles.length; i++) {
      final h = m.hist[i];
      if (h == null) continue;
      final y0 = y(0), y1 = y(h);
      final col = (h >= 0 ? up : down).withOpacity(0.5);
      canvas.drawRect(
          Rect.fromLTRB(cx(i) - bodyW / 2, h >= 0 ? y1 : y0,
              cx(i) + bodyW / 2, h >= 0 ? y0 : y1),
          Paint()..color = col);
    }
    _lineAbs(canvas, m.macd, y, cx, _macdLine, 1.2);
    _lineAbs(canvas, m.signal, y, cx, _signalLine, 1.2);
  }

  void _stochPanel(Canvas canvas, double top, double plotW,
      double Function(int) cx) {
    _panelFrame(canvas, top, plotW, 'Stoch');
    final s = data.stoch!;
    double y(double v) => top + _subH * (1 - v / 100);
    for (final lvl in [20.0, 80.0]) {
      _dashedH2(canvas, y(lvl), plotW, grid.withOpacity(0.7));
      _text(canvas, lvl.toStringAsFixed(0), Offset(plotW + 4, y(lvl) - 6),
          textColor, 8);
    }
    _lineAbs(canvas, s.k, y, cx, _stochK, 1.2);
    _lineAbs(canvas, s.d, y, cx, _stochD, 1.2);
  }

  void _atrPanel(Canvas canvas, double top, double plotW,
      double Function(int) cx) {
    _panelFrame(canvas, top, plotW, 'ATR');
    final a = data.atr!;
    var mx = 1e-9;
    for (final v in a) {
      if (v != null && v > mx) mx = v;
    }
    double y(double v) => top + _subH - (v / mx) * (_subH - 6);
    _text(canvas, fmtPrice(mx, market), Offset(plotW + 4, top + 2), textColor, 8);
    _lineAbs(canvas, a, y, cx, _atrColor, 1.3);
  }

  void _obvPanel(Canvas canvas, double top, double plotW,
      double Function(int) cx) {
    _panelFrame(canvas, top, plotW, 'OBV');
    final o = data.obv!;
    var mn = double.infinity, mx = -double.infinity;
    for (final v in o) {
      if (v == null) continue;
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    if (!(mx > mn)) {
      mn = (mn.isFinite ? mn : 0) - 1;
      mx = mn + 2;
    }
    final span = mx - mn;
    double y(double v) => top + _subH - ((v - mn) / span) * (_subH - 6);
    _lineAbs(canvas, o, y, cx, _obvColor, 1.3);
  }

  /// Paints the user's persistent horizontal / trend lines (and the in-progress
  /// trend preview) over the main price panel.
  void _drawUserShapes(
      Canvas canvas, double Function(double) my, double plotW) {
    final linePaint = Paint()
      ..color = _drawColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (final h in hlines) {
      final y = my(h.price);
      canvas.drawLine(Offset(0, y), Offset(plotW, y), linePaint);
      canvas.drawRect(Rect.fromLTWH(plotW, y - 8, _rightAxis, 16),
          Paint()..color = _drawColor);
      _text(canvas, fmtPrice(h.price, market), Offset(plotW + 3, y - 6),
          Colors.white, 9, bold: true);
    }
    void trend(_TrendLine t, double opacity) {
      canvas.drawLine(
          Offset(t.fx1 * plotW, my(t.p1)),
          Offset(t.fx2 * plotW, my(t.p2)),
          Paint()
            ..color = _drawColor.withOpacity(opacity)
            ..strokeWidth = 1.4
            ..style = PaintingStyle.stroke);
    }

    for (final t in trends) {
      trend(t, 1);
    }
    if (trendPreview != null) trend(trendPreview!, 0.6);
  }

  void _panelFrame(Canvas canvas, double top, double plotW, String label) {
    canvas.drawLine(Offset(0, top), Offset(plotW, top),
        Paint()..color = grid.withOpacity(0.5)..strokeWidth = 1);
    _text(canvas, label, Offset(2, top + 2), textColor, 8);
  }

  // ---- drawing helpers -----------------------------------------------------

  void _line(Canvas canvas, List<double?> series, double Function(double) y,
      double Function(int) cx, Color color, double w) {
    _lineAbs(canvas, series, (v) => y(v), cx, color, w);
  }

  void _lineAbs(Canvas canvas, List<double?> series, double Function(double) y,
      double Function(int) cx, Color color, double w) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = w
      ..style = PaintingStyle.stroke;
    final path = Path();
    var started = false;
    for (var i = 0; i < series.length; i++) {
      final v = series[i];
      if (v == null) {
        started = false;
        continue;
      }
      final p = Offset(cx(i), y(v));
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);
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

  void _dashedH(Canvas canvas, double y, double w, Color color) =>
      _dashedH2(canvas, y, w, color);

  void _dashedH2(Canvas canvas, double y, double w, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0, gap = 3.0;
    var x = 0.0;
    while (x < w) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, w), y), paint);
      x += dash + gap;
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
  bool shouldRepaint(covariant _CandlePainter old) => true;
}
