// Candlestick (OHLC) series for the Sandbox chart — TradingView-style, with
// selectable timeframes. Two sources:
//   * simulated — a realistic random-walk series generated locally and anchored
//     to the current price, so every market/timeframe has a full chart offline;
//   * live — real Binance klines for crypto when the live feed is on.
// The newest candle keeps forming from live ticks (rolls to a new candle when
// the wall-clock crosses the timeframe bucket), exactly like a real exchange.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'sim_market.dart';
import 'sim_models.dart';

enum Timeframe { m1, m5, m15, h1, h4, d1, w1, mo1 }

extension TimeframeX on Timeframe {
  String get label => switch (this) {
        Timeframe.m1 => '1m',
        Timeframe.m5 => '5m',
        Timeframe.m15 => '15m',
        Timeframe.h1 => '1H',
        Timeframe.h4 => '4H',
        Timeframe.d1 => '1D',
        Timeframe.w1 => '1W',
        Timeframe.mo1 => '1M',
      };

  /// Bucket size in milliseconds.
  int get bucketMs => switch (this) {
        Timeframe.m1 => 60 * 1000,
        Timeframe.m5 => 5 * 60 * 1000,
        Timeframe.m15 => 15 * 60 * 1000,
        Timeframe.h1 => 60 * 60 * 1000,
        Timeframe.h4 => 4 * 60 * 60 * 1000,
        Timeframe.d1 => 24 * 60 * 60 * 1000,
        Timeframe.w1 => 7 * 24 * 60 * 60 * 1000,
        Timeframe.mo1 => 30 * 24 * 60 * 60 * 1000,
      };

  /// Binance kline interval string (crypto live feed).
  String get binance => switch (this) {
        Timeframe.m1 => '1m',
        Timeframe.m5 => '5m',
        Timeframe.m15 => '15m',
        Timeframe.h1 => '1h',
        Timeframe.h4 => '4h',
        Timeframe.d1 => '1d',
        Timeframe.w1 => '1w',
        Timeframe.mo1 => '1M',
      };

  /// How many candles to show.
  int get count => 120;
}

class SimCandle {
  final int t; // bucket open time (ms)
  double o;
  double h;
  double l;
  double c;
  SimCandle(this.t, this.o, this.h, this.l, this.c);
}

/// Builds, caches and live-updates candle series per (symbol, timeframe).
/// Held on [SimState] so it survives rebuilds.
class CandleStore {
  final Map<String, List<SimCandle>> _cache = {};
  final Set<String> _fetching = {};

  String _key(String symbol, Timeframe tf) => '${symbol.toUpperCase()}|${tf.name}';

  /// Return the cached series, generating a simulated one anchored at [price]
  /// on first request.
  List<SimCandle> series(String symbol, Timeframe tf, double price) {
    final k = _key(symbol, tf);
    return _cache[k] ??= _generate(symbol, tf, price);
  }

  /// Advance the newest candle from a fresh price tick (rolls over the bucket).
  void update(String symbol, Timeframe tf, double price) {
    final list = _cache[_key(symbol, tf)];
    if (list == null || list.isEmpty || !(price > 0)) return;
    final bucket = _bucketNow(tf);
    final last = list.last;
    if (bucket > last.t) {
      list.add(SimCandle(bucket, price, price, price, price));
      while (list.length > tf.count) {
        list.removeAt(0);
      }
    } else {
      last.c = price;
      if (price > last.h) last.h = price;
      if (price < last.l) last.l = price;
    }
  }

  /// Drop caches for a symbol (e.g. after a live-vs-simulated switch) so they
  /// regenerate against the active feed.
  void invalidate(String symbol) {
    _cache.removeWhere((k, _) => k.startsWith('${symbol.toUpperCase()}|'));
  }

  int _bucketNow(Timeframe tf) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now ~/ tf.bucketMs) * tf.bucketMs;
  }

  List<SimCandle> _generate(String symbol, Timeframe tf, double price) {
    final market = instrumentFor(symbol)?.market ?? SimMarket.crypto;
    final rng = Random('$symbol${tf.name}'.hashCode);
    final n = tf.count;
    final vol = _vol(market, tf);
    final anchor = price > 0 ? price : (instrumentFor(symbol)?.seedPrice ?? 100);

    // Walk the closes backward from the current price so the last candle lines
    // up with the live ticker, then build believable O/H/L around each close.
    final closes = List<double>.filled(n, anchor);
    for (var i = n - 2; i >= 0; i--) {
      final shock = _gauss(rng) * vol;
      var prev = closes[i + 1] / (1 + shock);
      if (!prev.isFinite || prev <= 0) prev = closes[i + 1];
      closes[i] = prev.clamp(anchor * 0.2, anchor * 5);
    }

    final bucket = _bucketNow(tf);
    final out = <SimCandle>[];
    for (var i = 0; i < n; i++) {
      final close = closes[i];
      final open = i == 0 ? close * (1 - _gauss(rng) * vol * 0.3) : closes[i - 1];
      final hi = max(open, close) * (1 + _gauss(rng).abs() * vol * 0.6);
      final lo = min(open, close) * (1 - _gauss(rng).abs() * vol * 0.6);
      final t = bucket - (n - 1 - i) * tf.bucketMs;
      out.add(SimCandle(t, open, hi, lo < 0 ? min(open, close) : lo, close));
    }
    // Pin the final candle's close to the exact live price.
    out.last.c = anchor;
    if (anchor > out.last.h) out.last.h = anchor;
    if (anchor < out.last.l) out.last.l = anchor;
    return out;
  }

  double _vol(SimMarket m, Timeframe tf) {
    final base = switch (m) {
      SimMarket.crypto => 0.018,
      SimMarket.forex => 0.0035,
      SimMarket.stocks => 0.011,
      SimMarket.indices => 0.008,
      SimMarket.commodities => 0.013,
    };
    final scale = switch (tf) {
      Timeframe.m1 => 0.3,
      Timeframe.m5 => 0.5,
      Timeframe.m15 => 0.7,
      Timeframe.h1 => 1.0,
      Timeframe.h4 => 1.6,
      Timeframe.d1 => 2.4,
      Timeframe.w1 => 4.0,
      Timeframe.mo1 => 6.5,
    };
    return base * scale;
  }

  double _gauss(Random r) {
    final u1 = r.nextDouble().clamp(1e-9, 1.0);
    final u2 = r.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  // ---- live klines (crypto) ------------------------------------------------

  /// Best-effort real candles from Binance for crypto symbols. On success the
  /// cache is swapped; the chart repaints on the next tick. Never throws.
  Future<void> fetchLive(String symbol, Timeframe tf) async {
    final k = _key(symbol, tf);
    if (_fetching.contains(k)) return;
    if (instrumentFor(symbol)?.market != SimMarket.crypto) return;
    _fetching.add(k);
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final uri = Uri.https('api.binance.com', '/api/v3/klines', {
        'symbol': symbol.toUpperCase(),
        'interval': tf.binance,
        'limit': '${tf.count}',
      });
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 5));
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 6));
      final rows = jsonDecode(body);
      if (rows is! List || rows.isEmpty) return;
      final out = <SimCandle>[];
      for (final r in rows) {
        if (r is! List || r.length < 5) continue;
        final t = (r[0] as num).toInt();
        final o = double.tryParse('${r[1]}') ?? 0;
        final h = double.tryParse('${r[2]}') ?? 0;
        final l = double.tryParse('${r[3]}') ?? 0;
        final c = double.tryParse('${r[4]}') ?? 0;
        if (o > 0 && h > 0 && l > 0 && c > 0) out.add(SimCandle(t, o, h, l, c));
      }
      if (out.length >= 2) _cache[k] = out;
    } catch (_) {
      // Best-effort — keep the simulated series.
    } finally {
      _fetching.remove(k);
      client?.close(force: true);
    }
  }
}
