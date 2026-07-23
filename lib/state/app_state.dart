// Central app state: the account list plus freshly-computed metrics for the
// dashboard. Small dataset, so we recompute everything on each refresh — simple
// and always consistent.
import 'package:flutter/foundation.dart';

import '../calc.dart';
import '../db/database.dart';
import '../models.dart';

/// Global, app-wide state singleton. Screens rebuild via ListenableBuilder.
final AppState appState = AppState();

class AppState extends ChangeNotifier {
  final _db = LedgerDb.instance;

  bool loading = true;
  List<Account> accounts = [];
  List<PerfMonth> perfMonths = [];
  final Map<String, AccountMetrics> _metrics = {};

  double totalAumPhp = 0;
  double totalRealizedPhp = 0;
  int totalClosedTrades = 0;
  int totalWins = 0;

  AccountMetrics? metricsFor(String id) => _metrics[id];

  double get overallWinRate =>
      totalClosedTrades == 0 ? 0 : totalWins / totalClosedTrades;

  Future<void> load() async {
    loading = true;
    notifyListeners();

    accounts = await _db.accounts();
    perfMonths = await _db.perfMonths();
    _metrics.clear();
    double aum = 0, realized = 0;
    int closed = 0, wins = 0;

    for (final a in accounts) {
      final cf = await _db.cashflows(a.id);
      final tr = await _db.trades(a.id);
      final dv = await _db.dividends(a.id);
      final m = computeAccountMetrics(a, cf, tr, dv);
      _metrics[a.id] = m;
      aum += m.equityPhp;
      realized += m.realizedPnl * a.fxToPhp;
      closed += m.closedTrades;
      wins += m.wins;
    }

    totalAumPhp = aum;
    totalRealizedPhp = realized;
    totalClosedTrades = closed;
    totalWins = wins;
    loading = false;
    notifyListeners();
  }

  // ---- Monthly performance --------------------------------------------------
  Future<void> savePerfMonth(PerfMonth m) async {
    await _db.upsertPerfMonth(m);
    perfMonths = await _db.perfMonths();
    notifyListeners();
  }

  Future<void> deletePerfMonth(String id) async {
    await _db.deletePerfMonth(id);
    perfMonths = await _db.perfMonths();
    notifyListeners();
  }
}
