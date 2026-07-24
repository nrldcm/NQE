// TradingView / Binance-style candlestick chart for the Sandbox: a timeframe
// selector (1m · 5m · 15m · 1H · 4H · 1D · 1W · 1M), a live-forming candle, a
// price axis, a dashed last-price line, a draggable crosshair with an OHLC
// read-out, and toggleable technical indicators — MA / EMA / Bollinger overlays
// plus Volume, RSI and MACD sub-panels. Real Binance candles for crypto on the
// Live feed; a realistic simulated series otherwise.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';

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

/// Left-rail drawing tools (TradingView-style).
enum _DrawTool { cursor, trend, ray, hline, vline, rect, fib, brush, text }

bool _isDrawTool(_DrawTool t) => t != _DrawTool.cursor;

/// A user-drawn shape. Every anchor is stored in (fx, price) space —
/// fx = fraction of the plot width [0..1], price = value on the main axis — so
/// the shape tracks the chart's transform as new candles arrive and the axis
/// rescales. Interpretation of [pts] by [type]:
///  • hline  → 1 anchor, only its price matters (spans full width)
///  • vline  → 1 anchor, only its fx matters (spans full height)
///  • trend/ray/rect/fib → 2 anchors (endpoints / opposite corners)
///  • brush  → N anchors (free-hand polyline)
///  • text   → 1 anchor + [label]
class _Shape {
  final _DrawTool type;
  final List<Offset> pts; // Offset(fx, price)
  String label;
  _Shape(this.type, this.pts, {this.label = ''});
  _Shape copy() => _Shape(type, [for (final p in pts) p], label: label);

  Map<String, Object?> toJson() => {
        't': type.index,
        'l': label,
        'p': [
          for (final o in pts) [o.dx, o.dy]
        ],
      };

  static _Shape? fromJson(Map<String, Object?> m) {
    final ti = (m['t'] as num?)?.toInt() ?? -1;
    if (ti < 0 || ti >= _DrawTool.values.length) return null;
    final raw = (m['p'] as List?) ?? const [];
    final pts = <Offset>[
      for (final e in raw)
        if (e is List && e.length >= 2)
          Offset((e[0] as num).toDouble(), (e[1] as num).toDouble()),
    ];
    if (pts.isEmpty) return null;
    return _Shape(_DrawTool.values[ti], pts, label: (m['l'] ?? '').toString());
  }
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
  final List<_Shape> _shapes = [];
  _Shape? _preview; // shape being drawn right now
  int _selected = -1; // index into _shapes of the selected shape (-1 = none)
  int _grab = -2; // -2 none, -1 whole-shape move, >=0 = dragging that endpoint
  Offset? _dragLast; // last drag point in (fx, price) space
  bool _magnet = false; // snap anchors to the nearest candle O/H/L/C
  bool _locked = false; // lock: block create / move / delete
  bool _hidden = false; // hide all drawings
  // Cached plot geometry from the last build, so gestures can map screen
  // positions to price / fractional-x exactly like the painter does.
  double _lo = 0, _hi = 1, _plotW = 1;
  List<SimCandle> _lastCandles = const [];

  // ---- drawing persistence (per symbol) ------------------------------------
  // Drawings are saved keyed by symbol, so each stock/coin/pair keeps its own
  // lines/levels/annotations across symbol switches and app restarts.
  String get _drawKey => 'sandbox.draw.${widget.symbol}';

  @override
  void initState() {
    super.initState();
    _loadShapes();
  }

  @override
  void didUpdateWidget(covariant SandboxCandleChart old) {
    super.didUpdateWidget(old);
    if (old.symbol != widget.symbol) {
      // Switched instrument — drop the current drawings and load this one's.
      _shapes.clear();
      _preview = null;
      _selected = -1;
      _loadShapes();
    }
  }

  Future<void> _loadShapes() async {
    final key = _drawKey; // capture before the await (symbol may switch)
    try {
      final prefs = await SharedPreferences.getInstance();
      // Bail if the symbol changed while we were awaiting — else we'd paint the
      // old symbol's drawings onto the new one.
      if (!mounted || key != _drawKey) return;
      final raw = prefs.getString(key);
      final loaded = <_Shape>[];
      if (raw != null && raw.isNotEmpty) {
        for (final e in (jsonDecode(raw) as List)) {
          final s = _Shape.fromJson(Map<String, Object?>.from(e as Map));
          if (s != null) loaded.add(s);
        }
      }
      setState(() {
        _shapes
          ..clear()
          ..addAll(loaded);
      });
    } catch (_) {/* corrupt / missing — start blank */}
  }

  Future<void> _saveShapes() async {
    // Snapshot the key + payload BEFORE the async gap, so a symbol switch can't
    // write this symbol's shapes under the next symbol's key.
    final key = _drawKey;
    final payload =
        _shapes.isEmpty ? null : jsonEncode([for (final s in _shapes) s.toJson()]);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (payload == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, payload);
      }
    } catch (_) {/* best-effort */}
  }

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
    _lastCandles = candles;

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
    // Reserve a bottom band for the time axis so its labels don't overlap the
    // last sub-panel / the main panel's bottom candles.
    final totalHeight = widget.height + _subCount * 68.0 + 18;

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
                  final painter = CustomPaint(
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
                      shapes: _hidden ? const [] : _shapes,
                      preview: _hidden ? null : _preview,
                      selected: _hidden ? -1 : _selected,
                    ),
                  );
                  return Stack(
                    children: [
                      _buildGesture(painter, width, candles.length),
                      Positioned(left: 0, top: 0, child: _drawingRail(context)),
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

  // Inverse mappings (data → screen), matching the painter, for hit-testing.
  double _yFromPrice(double p) {
    final span = (_hi - _lo).abs() < 1e-12 ? 1.0 : (_hi - _lo);
    return widget.height * (_hi - p) / span;
  }

  double _xFromFx(double fx) => fx * _plotW;

  Offset _toScreen(Offset dataPt) =>
      Offset(_xFromFx(dataPt.dx), _yFromPrice(dataPt.dy));

  /// A tap/drag point in (fx, price) space — optionally magnet-snapped to the
  /// nearest candle open/high/low/close at that bar.
  Offset _toData(Offset p) {
    var fx = _fxFromX(p.dx);
    var price = _priceFromY(p.dy);
    if (_magnet && _lastCandles.isNotEmpty) {
      final i = (fx * _lastCandles.length).floor().clamp(0, _lastCandles.length - 1);
      final c = _lastCandles[i];
      double best = c.c;
      for (final v in [c.o, c.h, c.l, c.c]) {
        if ((v - price).abs() < (best - price).abs()) best = v;
      }
      price = best;
    }
    return Offset(fx, price);
  }

  // ---- gesture routing -----------------------------------------------------

  /// The chart's gesture layer depends on the mode:
  ///  • a draw tool → full pan/tap to CREATE a shape;
  ///  • cursor with a selected shape → full pan to MOVE it / drag a handle;
  ///  • cursor, nothing selected → tap to select + horizontal-drag crosshair
  ///    (so a vertical swipe still scrolls the surrounding page).
  Widget _buildGesture(Widget painter, double width, int n) {
    if (_isDrawTool(_tool)) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _onDrawTap(d.localPosition),
        onPanStart: (d) => _onDrawStart(d.localPosition),
        onPanUpdate: (d) => _onDrawUpdate(d.localPosition),
        onPanEnd: (_) => _onDrawEnd(),
        child: painter,
      );
    }
    if (_selected >= 0) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _onCursorTap(d.localPosition),
        onPanStart: (d) => _onMoveStart(d.localPosition),
        onPanUpdate: (d) => _onMoveUpdate(d.localPosition),
        onPanEnd: (_) {
          _dragLast = null;
          _saveShapes(); // persist the new position/shape
        },
        child: painter,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _onCursorTap(d.localPosition),
      onHorizontalDragStart: (d) => _updateCross(d.localPosition.dx, width, n),
      onHorizontalDragUpdate: (d) => _updateCross(d.localPosition.dx, width, n),
      onHorizontalDragEnd: (_) => setState(() => _cross = null),
      child: painter,
    );
  }

  // ---- create a shape ------------------------------------------------------

  void _onDrawTap(Offset p) {
    if (_locked || p.dy > widget.height) return;
    final d = _toData(p);
    switch (_tool) {
      case _DrawTool.hline:
        _commit(_Shape(_DrawTool.hline, [d]));
      case _DrawTool.vline:
        _commit(_Shape(_DrawTool.vline, [d]));
      case _DrawTool.text:
        _addText(d);
      default:
        break; // the rest are drawn with a drag
    }
  }

  void _onDrawStart(Offset p) {
    if (_locked || p.dy > widget.height) return;
    final d = _toData(p);
    switch (_tool) {
      case _DrawTool.trend:
      case _DrawTool.ray:
      case _DrawTool.rect:
      case _DrawTool.fib:
        setState(() => _preview = _Shape(_tool, [d, d]));
      case _DrawTool.brush:
        setState(() => _preview = _Shape(_DrawTool.brush, [d]));
      default:
        break;
    }
  }

  void _onDrawUpdate(Offset p) {
    final pv = _preview;
    if (pv == null) return;
    final d = _toData(p);
    setState(() {
      if (pv.type == _DrawTool.brush) {
        pv.pts.add(d);
      } else {
        pv.pts[1] = d;
      }
    });
  }

  void _onDrawEnd() {
    final pv = _preview;
    if (pv == null) return;
    setState(() {
      _shapes.add(pv);
      _preview = null;
      _selected = _shapes.length - 1;
      _tool = _DrawTool.cursor; // one shape per pick, like TradingView
    });
    _saveShapes();
  }

  Future<void> _addText(Offset d) async {
    final ctrl = TextEditingController();
    final s = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add text'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Label'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text),
              child: const Text('Add')),
        ],
      ),
    );
    if (s != null && s.trim().isNotEmpty) {
      _commit(_Shape(_DrawTool.text, [d], label: s.trim()));
    }
  }

  void _commit(_Shape s) {
    setState(() {
      _shapes.add(s);
      _selected = _shapes.length - 1;
      _tool = _DrawTool.cursor;
    });
    _saveShapes();
  }

  // ---- select / move -------------------------------------------------------

  void _onCursorTap(Offset p) {
    // Hit-test existing shapes first; a hit selects it, otherwise place the
    // crosshair and deselect.
    final hit = _hitTest(p);
    if (hit >= 0) {
      setState(() {
        _selected = hit;
        _cross = null;
      });
    } else {
      setState(() => _selected = -1);
      final n = _lastCandles.length;
      if (n > 0) _updateCross(p.dx, _plotW + 58.0, n);
    }
  }

  void _onMoveStart(Offset p) {
    if (_locked || _selected < 0 || _selected >= _shapes.length) return;
    final s = _shapes[_selected];
    // Grab the nearest endpoint handle if close to one, else move the whole
    // shape.
    _grab = -1;
    for (var i = 0; i < s.pts.length; i++) {
      if ((_toScreen(s.pts[i]) - p).distance <= 14) {
        _grab = i;
        break;
      }
    }
    // Only start moving if the drag actually began on the shape (a handle or
    // its body); otherwise deselect so an empty drag doesn't drag it around.
    if (_grab < 0 && !_shapeHit(s, p)) {
      setState(() => _selected = -1);
      _dragLast = null;
      return;
    }
    _dragLast = _toData(p);
  }

  void _onMoveUpdate(Offset p) {
    if (_locked || _selected < 0 || _dragLast == null) return;
    final s = _shapes[_selected];
    final now = _toData(p);
    final dfx = now.dx - _dragLast!.dx;
    final dp = now.dy - _dragLast!.dy;
    setState(() {
      if (_grab >= 0 && _grab < s.pts.length) {
        s.pts[_grab] = now; // drag a single endpoint to that position
      } else {
        for (var i = 0; i < s.pts.length; i++) {
          s.pts[i] = Offset(s.pts[i].dx + dfx, s.pts[i].dy + dp);
        }
      }
    });
    _dragLast = now;
  }

  /// Distance-based hit test: returns the index of the shape under [p] (within
  /// ~12px), searching newest-first so the top-most is picked.
  int _hitTest(Offset p) {
    for (var i = _shapes.length - 1; i >= 0; i--) {
      if (_shapeHit(_shapes[i], p)) return i;
    }
    return -1;
  }

  bool _shapeHit(_Shape s, Offset p) {
    const tol = 12.0;
    switch (s.type) {
      case _DrawTool.hline:
        return (p.dy - _yFromPrice(s.pts[0].dy)).abs() <= tol;
      case _DrawTool.vline:
        return (p.dx - _xFromFx(s.pts[0].dx)).abs() <= tol;
      case _DrawTool.text:
        return (_toScreen(s.pts[0]) - p).distance <= 22;
      case _DrawTool.rect:
        final a = _toScreen(s.pts[0]), b = _toScreen(s.pts[1]);
        final r = Rect.fromPoints(a, b).inflate(tol);
        final inner = Rect.fromPoints(a, b).deflate(tol);
        return r.contains(p) && !inner.contains(p);
      case _DrawTool.fib:
        final a = _toScreen(s.pts[0]), b = _toScreen(s.pts[1]);
        if (p.dx < a.dx - tol && p.dx < b.dx - tol) return false;
        for (final lvl in const [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0]) {
          final y = a.dy + (b.dy - a.dy) * lvl;
          if ((p.dy - y).abs() <= tol) return true;
        }
        return false;
      case _DrawTool.brush:
        for (var i = 0; i + 1 < s.pts.length; i++) {
          if (_distToSeg(p, _toScreen(s.pts[i]), _toScreen(s.pts[i + 1])) <=
              tol) {
            return true;
          }
        }
        return false;
      default: // trend / ray
        return _distToSeg(p, _toScreen(s.pts[0]), _toScreen(s.pts[1])) <= tol;
    }
  }

  double _distToSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-9) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
  }

  void _deleteSelected() {
    if (_selected < 0 || _selected >= _shapes.length) return;
    setState(() {
      _shapes.removeAt(_selected);
      _selected = -1;
    });
    _saveShapes();
  }

  /// TradingView-style vertical rail of drawing tools on the chart's left edge.
  Widget _drawingRail(BuildContext context) {
    final pal = context.nqe;

    Widget tool(_DrawTool t, IconData icon, String tip) {
      final active = _tool == t;
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: () => setState(() => _tool = t),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            decoration: BoxDecoration(
              color: active ? _drawColor.withOpacity(0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: active ? _drawColor : Colors.transparent, width: 1),
            ),
            child: Icon(icon, size: 15, color: active ? _drawColor : pal.textLo),
          ),
        ),
      );
    }

    Widget toggle(bool on, IconData icon, String tip, VoidCallback onTap) {
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            decoration: BoxDecoration(
              color: on ? NqeColors.gain.withOpacity(0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon,
                size: 15, color: on ? NqeColors.gain : pal.textLo),
          ),
        ),
      );
    }

    Widget divider() => Container(
          width: 16,
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 2.5),
          color: pal.line,
        );

    final hasShapes = _shapes.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(left: 2, top: 2),
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      decoration: BoxDecoration(
        color: pal.bg.withOpacity(0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tool(_DrawTool.cursor, Icons.near_me_outlined, 'Cursor / crosshair'),
          tool(_DrawTool.trend, Icons.trending_up, 'Trend line'),
          tool(_DrawTool.ray, Icons.north_east, 'Ray'),
          tool(_DrawTool.hline, Icons.horizontal_rule, 'Horizontal line'),
          tool(_DrawTool.vline, Icons.straighten, 'Vertical line'),
          tool(_DrawTool.rect, Icons.crop_square, 'Rectangle'),
          tool(_DrawTool.fib, Icons.stacked_line_chart, 'Fib retracement'),
          tool(_DrawTool.brush, Icons.gesture, 'Brush'),
          tool(_DrawTool.text, Icons.title, 'Text'),
          divider(),
          toggle(_magnet, Icons.attractions_outlined, 'Magnet (snap to OHLC)',
              () => setState(() => _magnet = !_magnet)),
          toggle(_locked, _locked ? Icons.lock_outline : Icons.lock_open,
              _locked ? 'Locked' : 'Lock drawings',
              () => setState(() => _locked = !_locked)),
          toggle(
              _hidden,
              _hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              _hidden ? 'Drawings hidden' : 'Hide drawings',
              () => setState(() => _hidden = !_hidden)),
          divider(),
          Tooltip(
            message: _selected >= 0 ? 'Delete selected' : 'Clear all drawings',
            child: InkWell(
              onTap: !hasShapes
                  ? null
                  : () {
                      if (_selected >= 0) {
                        _deleteSelected();
                      } else {
                        setState(() {
                          _shapes.clear();
                          _preview = null;
                          _selected = -1;
                        });
                        _saveShapes();
                      }
                    },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.symmetric(vertical: 1.5),
                child: Icon(Icons.delete_outline,
                    size: 15,
                    color:
                        hasShapes ? pal.textLo : pal.textLo.withOpacity(0.35)),
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

  /// User-drawn shapes from the left drawing-tools rail (+ the one being drawn,
  /// and the index of the currently-selected shape for its handles).
  final List<_Shape> shapes;
  final _Shape? preview;
  final int selected;

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
    this.shapes = const [],
    this.preview,
    this.selected = -1,
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
  static const _fibLevels = [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0];

  void _drawUserShapes(
      Canvas canvas, double Function(double) my, double plotW) {
    double sx(double fx) => fx * plotW;
    for (var i = 0; i < shapes.length; i++) {
      _paintShape(canvas, shapes[i], my, sx, plotW, 1.0, i == selected);
    }
    if (preview != null) {
      _paintShape(canvas, preview!, my, sx, plotW, 0.6, false);
    }
  }

  void _paintShape(Canvas canvas, _Shape s, double Function(double) my,
      double Function(double) sx, double plotW, double opacity, bool sel) {
    final col = _drawColor.withOpacity(opacity);
    final stroke = Paint()
      ..color = col
      ..strokeWidth = sel ? 2.0 : 1.4
      ..style = PaintingStyle.stroke;
    final pts = s.pts;

    switch (s.type) {
      case _DrawTool.hline:
        final y = my(pts[0].dy);
        canvas.drawLine(Offset(0, y), Offset(plotW, y), stroke);
        canvas.drawRect(Rect.fromLTWH(plotW, y - 8, _rightAxis, 16),
            Paint()..color = col);
        _text(canvas, fmtPrice(pts[0].dy, market), Offset(plotW + 3, y - 6),
            Colors.white, 9, bold: true);
      case _DrawTool.vline:
        final x = sx(pts[0].dx);
        canvas.drawLine(Offset(x, 0), Offset(x, mainHeight), stroke);
      case _DrawTool.trend:
        canvas.drawLine(Offset(sx(pts[0].dx), my(pts[0].dy)),
            Offset(sx(pts[1].dx), my(pts[1].dy)), stroke);
      case _DrawTool.ray:
        final a = Offset(sx(pts[0].dx), my(pts[0].dy));
        final b = Offset(sx(pts[1].dx), my(pts[1].dy));
        final d = b - a;
        // Extend past b to the plot's right edge.
        final t = d.dx.abs() < 1e-6 ? 1.0 : (plotW - a.dx) / d.dx;
        final end = t > 1 ? a + d * t : b;
        canvas.drawLine(a, end, stroke);
      case _DrawTool.rect:
        final r = Rect.fromPoints(Offset(sx(pts[0].dx), my(pts[0].dy)),
            Offset(sx(pts[1].dx), my(pts[1].dy)));
        canvas.drawRect(r, Paint()..color = _drawColor.withOpacity(0.08 * opacity));
        canvas.drawRect(r, stroke);
      case _DrawTool.fib:
        final x0 = sx(pts[0].dx), x1 = sx(pts[1].dx);
        final lft = x0 < x1 ? x0 : x1;
        final rgt = x0 < x1 ? x1 : x0;
        for (final lvl in _fibLevels) {
          final price = pts[0].dy + (pts[1].dy - pts[0].dy) * lvl;
          final y = my(price);
          canvas.drawLine(Offset(lft, y), Offset(rgt, y),
              Paint()
                ..color = col.withOpacity(0.7 * opacity)
                ..strokeWidth = 1);
          _text(canvas, '${(lvl * 100).toStringAsFixed(1)}%  ${fmtPrice(price, market)}',
              Offset(lft + 2, y - 11), _drawColor.withOpacity(opacity), 8);
        }
        canvas.drawLine(Offset(x0, my(pts[0].dy)), Offset(x1, my(pts[1].dy)),
            stroke..strokeWidth = 1);
      case _DrawTool.brush:
        final path = Path();
        for (var i = 0; i < pts.length; i++) {
          final o = Offset(sx(pts[i].dx), my(pts[i].dy));
          if (i == 0) {
            path.moveTo(o.dx, o.dy);
          } else {
            path.lineTo(o.dx, o.dy);
          }
        }
        canvas.drawPath(path, stroke);
      case _DrawTool.text:
        final o = Offset(sx(pts[0].dx), my(pts[0].dy));
        _text(canvas, s.label, Offset(o.dx + 4, o.dy - 6),
            _drawColor.withOpacity(opacity), 12, bold: true);
        canvas.drawCircle(o, 3, Paint()..color = col);
      case _DrawTool.cursor:
        break;
    }

    // Selection handles — small squares at each anchor of the active shape.
    if (sel) {
      final hp = Paint()..color = Colors.white;
      final hb = Paint()
        ..color = _drawColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      List<Offset> handles;
      switch (s.type) {
        case _DrawTool.hline:
          handles = [Offset(plotW / 2, my(pts[0].dy))];
        case _DrawTool.vline:
          handles = [Offset(sx(pts[0].dx), mainHeight / 2)];
        case _DrawTool.brush:
          handles = const [];
        default:
          handles = [for (final p in pts) Offset(sx(p.dx), my(p.dy))];
      }
      for (final h in handles) {
        final r = Rect.fromCenter(center: h, width: 8, height: 8);
        canvas.drawRect(r, hp);
        canvas.drawRect(r, hb);
      }
    }
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
