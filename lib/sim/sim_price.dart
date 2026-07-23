// Sandbox price engine. Two feeds:
//   * simulated — a per-symbol random walk seeded from the catalogue, so it runs
//     fully offline for practice;
//   * live — best-effort real quotes (crypto via Binance public ticker, FX via a
//     public endpoint); anything it can't fetch falls back to the simulated
//     value, so the engine never stalls.
//
// The walk is driven by an injectable [Random] and a manual [tick]/[step] so
// tests are deterministic (no timers, no network).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'sim_market.dart';
import 'sim_models.dart';

class PriceEngine extends ChangeNotifier {
  PriceEngine({Random? random, this.tickInterval = const Duration(seconds: 1)})
      : _rng = random ?? Random();

  final Random _rng;
  final Duration tickInterval;

  FeedMode mode = FeedMode.simulated;

  final Map<String, double> _price = {};
  final Map<String, double> _prevClose = {};
  final Map<String, int> _lastLive = {}; // ms of last successful live quote
  final Set<String> _subs = {};
  Timer? _timer;
  bool _fetching = false;

  /// How long a live quote is considered "fresh". Past this (e.g. offline), the
  /// symbol falls back to the random walk so its price is never frozen and
  /// pending orders can still fill.
  static const int _liveStaleMs = 8000;

  double? price(String symbol) => _price[symbol.toUpperCase()];

  SimQuote? quote(String symbol) {
    final s = symbol.toUpperCase();
    final p = _price[s];
    if (p == null) return null;
    return SimQuote(s, p, _prevClose[s] ?? p, _nowMs());
  }

  List<String> get subscriptions => _subs.toList();

  /// Ensure a symbol has a price and is tracked. Seeds from the catalogue.
  void subscribe(String symbol) {
    final s = symbol.toUpperCase();
    if (_subs.add(s)) {
      final seed = seedPriceFor(s);
      _price.putIfAbsent(s, () => seed);
      _prevClose.putIfAbsent(s, () => seed);
      notifyListeners();
    }
  }

  /// Subscribe a batch of symbols with a single [notifyListeners] at the end,
  /// so it's safe to call outside build without a notify-per-symbol storm.
  void subscribeAll(Iterable<String> symbols) {
    var added = false;
    for (final raw in symbols) {
      final s = raw.toUpperCase();
      if (_subs.add(s)) {
        final seed = seedPriceFor(s);
        _price.putIfAbsent(s, () => seed);
        _prevClose.putIfAbsent(s, () => seed);
        added = true;
      }
    }
    if (added) notifyListeners();
  }

  void unsubscribe(String symbol) => _subs.remove(symbol.toUpperCase());

  /// Advance every subscribed symbol one simulated step. Public for tests.
  /// In live mode, symbols that have a real provider (crypto) are NOT walked —
  /// they're set by [_fetchLive] to the real price, so the chart and the fill
  /// engine agree exactly.
  void step() {
    final live = mode == FeedMode.live;
    final now = _nowMs();
    for (final s in _subs) {
      // In live mode, crypto is driven by the real fetch — but only while that
      // quote is fresh. If it's stale/missing (offline), fall through and walk
      // so the price is never frozen and orders can still fill.
      if (live &&
          instrumentFor(s)?.market == SimMarket.crypto &&
          now - (_lastLive[s] ?? 0) < _liveStaleMs) {
        continue;
      }
      final cur = _price[s] ?? seedPriceFor(s);
      _price[s] = _nextPrice(s, cur);
    }
    notifyListeners();
  }

  /// One engine tick: simulated always walks; live additionally kicks a
  /// best-effort fetch whose results override on arrival.
  Future<void> tick() async {
    step();
    if (mode == FeedMode.live) {
      unawaited(_fetchLive());
    }
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Roll the "previous close" baseline to the current price (e.g. at day start
  /// or on reset) so % change resets.
  void rollPrevClose() {
    for (final s in _subs) {
      _prevClose[s] = _price[s] ?? _prevClose[s] ?? seedPriceFor(s);
    }
    notifyListeners();
  }

  double _nextPrice(String symbol, double cur) {
    // Volatility scaled by market; small drift ~0.
    final inst = instrumentFor(symbol);
    final vol = switch (inst?.market) {
      SimMarket.crypto => 0.010, // ~1% per tick
      SimMarket.forex => 0.0015,
      _ => 0.004, // stocks
    };
    final shock = _gaussian() * vol;
    var next = cur * (1 + shock);
    if (!next.isFinite || next <= 0) next = cur;
    // Keep sane bounds so a long run can't explode/round to zero.
    final seed = inst?.seedPrice ?? cur;
    next = next.clamp(seed * 0.05, seed * 20);
    return next;
  }

  // Box–Muller-ish gaussian from the injected RNG.
  double _gaussian() {
    final u1 = (_rng.nextDouble()).clamp(1e-9, 1.0);
    final u2 = _rng.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  Future<void> _fetchLive() async {
    if (_fetching) return;
    _fetching = true;
    try {
      // Only crypto has a wired live provider; fetch them concurrently so the
      // feed keeps up with the tick instead of serializing timeouts.
      final crypto = _subs
          .where((s) => instrumentFor(s)?.market == SimMarket.crypto)
          .toList();
      final results = await Future.wait(
          crypto.map((s) => _binancePrice(s)),
          eagerError: false);
      for (var i = 0; i < crypto.length; i++) {
        final live = results[i];
        if (live != null && live.isFinite && live > 0) {
          _price[crypto[i]] = live;
          _lastLive[crypto[i]] = _nowMs();
        }
      }
      // FX / stocks keep their simulated value so the engine never stalls.
      notifyListeners();
    } catch (_) {
      // Best-effort; ignore and keep simulated values.
    } finally {
      _fetching = false;
    }
  }

  Future<double?> _binancePrice(String symbol) async {
    HttpClient? c;
    try {
      c = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await c
          .getUrl(Uri.https('api.binance.com', '/api/v3/ticker/price',
              {'symbol': symbol}))
          .timeout(const Duration(seconds: 4));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));
      final map = jsonDecode(body) as Map<String, dynamic>;
      return double.tryParse('${map['price']}');
    } catch (_) {
      return null;
    } finally {
      c?.close(force: true);
    }
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
