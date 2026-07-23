// Technical-indicator math for the Sandbox chart (TradingView / Binance style):
// moving averages (SMA/EMA/WMA), VWAP, Bollinger Bands, RSI, MACD, Stochastic,
// ATR, OBV and a volume proxy. Pure and unit-testable — every series is returned
// aligned to the input length, with `null` where there isn't enough history yet.
import 'dart:math';

import 'sim_candles.dart';

/// Simple moving average.
List<double?> sma(List<double> v, int period) {
  final out = List<double?>.filled(v.length, null);
  if (period <= 0) return out;
  var sum = 0.0;
  for (var i = 0; i < v.length; i++) {
    sum += v[i];
    if (i >= period) sum -= v[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

/// Exponential moving average.
List<double?> ema(List<double> v, int period) {
  final out = List<double?>.filled(v.length, null);
  if (period <= 0 || v.isEmpty) return out;
  final k = 2 / (period + 1);
  double? prev;
  var sum = 0.0;
  for (var i = 0; i < v.length; i++) {
    if (i < period) {
      sum += v[i];
      if (i == period - 1) {
        prev = sum / period;
        out[i] = prev;
      }
    } else {
      prev = v[i] * k + prev! * (1 - k);
      out[i] = prev;
    }
  }
  return out;
}

/// Bollinger Bands (middle SMA, upper, lower) at [mult] standard deviations.
({List<double?> mid, List<double?> upper, List<double?> lower}) bollinger(
    List<double> v,
    {int period = 20,
    double mult = 2}) {
  final mid = sma(v, period);
  final upper = List<double?>.filled(v.length, null);
  final lower = List<double?>.filled(v.length, null);
  for (var i = period - 1; i < v.length; i++) {
    final m = mid[i];
    if (m == null) continue;
    var sq = 0.0;
    for (var j = i - period + 1; j <= i; j++) {
      final d = v[j] - m;
      sq += d * d;
    }
    final sd = sqrt(sq / period);
    upper[i] = m + mult * sd;
    lower[i] = m - mult * sd;
  }
  return (mid: mid, upper: upper, lower: lower);
}

/// Relative Strength Index (Wilder smoothing).
List<double?> rsi(List<double> v, {int period = 14}) {
  final out = List<double?>.filled(v.length, null);
  if (v.length <= period) return out;
  var gain = 0.0, loss = 0.0;
  for (var i = 1; i <= period; i++) {
    final ch = v[i] - v[i - 1];
    if (ch >= 0) {
      gain += ch;
    } else {
      loss -= ch;
    }
  }
  gain /= period;
  loss /= period;
  out[period] = loss == 0 ? 100 : 100 - 100 / (1 + gain / loss);
  for (var i = period + 1; i < v.length; i++) {
    final ch = v[i] - v[i - 1];
    final g = ch > 0 ? ch : 0.0;
    final l = ch < 0 ? -ch : 0.0;
    gain = (gain * (period - 1) + g) / period;
    loss = (loss * (period - 1) + l) / period;
    out[i] = loss == 0 ? 100 : 100 - 100 / (1 + gain / loss);
  }
  return out;
}

/// MACD line, signal line and histogram.
({List<double?> macd, List<double?> signal, List<double?> hist}) macd(
    List<double> v,
    {int fast = 12,
    int slow = 26,
    int signalPeriod = 9}) {
  final ef = ema(v, fast);
  final es = ema(v, slow);
  final macdLine = List<double?>.filled(v.length, null);
  for (var i = 0; i < v.length; i++) {
    if (ef[i] != null && es[i] != null) macdLine[i] = ef[i]! - es[i]!;
  }
  // Signal = EMA of the (compact) MACD line.
  final compact = <double>[];
  final idx = <int>[];
  for (var i = 0; i < v.length; i++) {
    if (macdLine[i] != null) {
      compact.add(macdLine[i]!);
      idx.add(i);
    }
  }
  final sigCompact = ema(compact, signalPeriod);
  final signal = List<double?>.filled(v.length, null);
  for (var j = 0; j < idx.length; j++) {
    signal[idx[j]] = sigCompact[j];
  }
  final hist = List<double?>.filled(v.length, null);
  for (var i = 0; i < v.length; i++) {
    if (macdLine[i] != null && signal[i] != null) {
      hist[i] = macdLine[i]! - signal[i]!;
    }
  }
  return (macd: macdLine, signal: signal, hist: hist);
}

/// A plausible volume series derived from each candle's range/body (there's no
/// real order-book volume in the simulation), stable per candle time.
List<double> volumeProxy(List<SimCandle> candles) {
  final out = <double>[];
  for (final c in candles) {
    final range = (c.h - c.l).abs();
    final body = (c.c - c.o).abs();
    final base = c.c == 0 ? 1.0 : (range + body) / c.c;
    // Deterministic wiggle from the bucket time so bars differ but don't flicker.
    final wiggle = 0.6 + ((c.t ~/ 60000) % 40) / 40.0;
    out.add(base * 1000 * wiggle + 1);
  }
  return out;
}

/// Weighted moving average — linear weights 1..period (most recent weighted
/// heaviest). Null-padded until [period] samples exist.
List<double?> wma(List<double> v, int period) {
  final out = List<double?>.filled(v.length, null);
  if (period <= 0) return out;
  final denom = period * (period + 1) / 2;
  for (var i = period - 1; i < v.length; i++) {
    var num = 0.0;
    for (var j = 0; j < period; j++) {
      num += v[i - period + 1 + j] * (j + 1);
    }
    out[i] = num / denom;
  }
  return out;
}

/// Volume-weighted average price, accumulated across the visible series (a
/// running session VWAP). Uses the typical price (H+L+C)/3 and the supplied
/// [volume] series (e.g. [volumeProxy]). Aligned to the candle length.
List<double?> vwap(List<SimCandle> candles, List<double> volume) {
  final out = List<double?>.filled(candles.length, null);
  var cumPv = 0.0, cumV = 0.0;
  for (var i = 0; i < candles.length; i++) {
    final c = candles[i];
    final tp = (c.h + c.l + c.c) / 3;
    final vol = i < volume.length ? volume[i] : 0.0;
    cumPv += tp * vol;
    cumV += vol;
    out[i] = cumV > 0 ? cumPv / cumV : tp;
  }
  return out;
}

/// Stochastic oscillator: %K over [kPeriod] and %D (SMA of %K over [dPeriod]),
/// both on a 0..100 scale. Null-padded through the warm-up window.
({List<double?> k, List<double?> d}) stochastic(List<SimCandle> candles,
    {int kPeriod = 14, int dPeriod = 3}) {
  final n = candles.length;
  final k = List<double?>.filled(n, null);
  if (kPeriod <= 0) return (k: k, d: List<double?>.filled(n, null));
  for (var i = kPeriod - 1; i < n; i++) {
    var lo = double.infinity, hi = -double.infinity;
    for (var j = i - kPeriod + 1; j <= i; j++) {
      if (candles[j].l < lo) lo = candles[j].l;
      if (candles[j].h > hi) hi = candles[j].h;
    }
    final range = hi - lo;
    k[i] = range <= 0 ? 50.0 : (candles[i].c - lo) / range * 100;
  }
  final d = List<double?>.filled(n, null);
  if (dPeriod > 0) {
    for (var i = 0; i < n; i++) {
      if (i < kPeriod - 1 + dPeriod - 1) continue;
      var sum = 0.0;
      var ok = true;
      for (var j = i - dPeriod + 1; j <= i; j++) {
        final kv = k[j];
        if (kv == null) {
          ok = false;
          break;
        }
        sum += kv;
      }
      if (ok) d[i] = sum / dPeriod;
    }
  }
  return (k: k, d: d);
}

/// Average True Range (Wilder smoothing) over [period]. Null through the
/// warm-up; the first value is the simple mean of the first [period] true
/// ranges, then Wilder-smoothed.
List<double?> atr(List<SimCandle> candles, {int period = 14}) {
  final n = candles.length;
  final out = List<double?>.filled(n, null);
  if (period <= 0 || n <= period) return out;
  final tr = List<double>.filled(n, 0);
  tr[0] = (candles[0].h - candles[0].l).abs();
  for (var i = 1; i < n; i++) {
    final h = candles[i].h, l = candles[i].l, pc = candles[i - 1].c;
    tr[i] = max(h - l, max((h - pc).abs(), (l - pc).abs()));
  }
  var sum = 0.0;
  for (var i = 1; i <= period; i++) {
    sum += tr[i];
  }
  var prev = sum / period;
  out[period] = prev;
  for (var i = period + 1; i < n; i++) {
    prev = (prev * (period - 1) + tr[i]) / period;
    out[i] = prev;
  }
  return out;
}

/// On-Balance Volume: a running total that adds the candle's [volume] on an
/// up-close and subtracts it on a down-close. Starts at 0 on the first candle.
List<double?> obv(List<SimCandle> candles, List<double> volume) {
  final n = candles.length;
  final out = List<double?>.filled(n, null);
  if (n == 0) return out;
  var v = 0.0;
  out[0] = 0.0;
  for (var i = 1; i < n; i++) {
    final vol = i < volume.length ? volume[i] : 0.0;
    if (candles[i].c > candles[i - 1].c) {
      v += vol;
    } else if (candles[i].c < candles[i - 1].c) {
      v -= vol;
    }
    out[i] = v;
  }
  return out;
}
