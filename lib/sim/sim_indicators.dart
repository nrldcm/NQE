// Technical-indicator math for the Sandbox chart (TradingView / Binance style):
// moving averages, EMA, Bollinger Bands, RSI, MACD and a volume proxy. Pure and
// unit-testable — every series is returned aligned to the input length, with
// `null` where there isn't enough history yet.
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
