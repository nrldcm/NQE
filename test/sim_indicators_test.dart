// Unit tests for the Sandbox chart indicators (SMA/EMA/RSI/MACD/Bollinger).
import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/sim/sim_indicators.dart';

void main() {
  test('SMA aligns and averages a trailing window', () {
    final s = sma([1, 2, 3, 4, 5], 3);
    expect(s[0], isNull);
    expect(s[1], isNull);
    expect(s[2], closeTo(2, 1e-9));
    expect(s[3], closeTo(3, 1e-9));
    expect(s[4], closeTo(4, 1e-9));
  });

  test('EMA is null before the seed period, then defined', () {
    final e = ema([1, 2, 3, 4, 5, 6], 3);
    expect(e.take(2), everyElement(isNull));
    expect(e[2], isNotNull); // seed = SMA of first 3
    expect(e.last, isNotNull);
  });

  test('RSI is ~100 on a straight uptrend and ~0 on a downtrend', () {
    final up = List<double>.generate(30, (i) => (i + 1).toDouble());
    final down = List<double>.generate(30, (i) => (30 - i).toDouble());
    expect(rsi(up).last, closeTo(100, 1e-6));
    expect(rsi(down).last, closeTo(0, 1e-6));
  });

  test('MACD series are all aligned to the input length', () {
    final v = List<double>.generate(60, (i) => 100 + (i % 7) - 3.0);
    final m = macd(v);
    expect(m.macd.length, v.length);
    expect(m.signal.length, v.length);
    expect(m.hist.length, v.length);
  });

  test('Bollinger middle band equals the SMA and bands straddle it', () {
    final v = List<double>.generate(40, (i) => 50 + (i % 5).toDouble());
    final b = bollinger(v, period: 20);
    final s = sma(v, 20);
    for (var i = 19; i < v.length; i++) {
      expect(b.mid[i], closeTo(s[i]!, 1e-9));
      expect(b.upper[i]! >= b.mid[i]!, isTrue);
      expect(b.lower[i]! <= b.mid[i]!, isTrue);
    }
  });
}
