// Pure calculation helpers shared by the dashboard, stats and charts.
import 'models.dart';

String monthKey(String isoDate) {
  // Expects yyyy-mm-dd; falls back gracefully.
  if (isoDate.length >= 7) return isoDate.substring(0, 7);
  return isoDate;
}

String monthLabel(String key) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final parts = key.split('-');
  if (parts.length < 2) return key;
  final m = int.tryParse(parts[1]) ?? 1;
  return '${names[(m - 1).clamp(0, 11)]} ${parts[0]}';
}

class AccountMetrics {
  final Account account;
  final double netCashflow; // account currency, signed
  final double realizedPnl; // closed trades, account currency
  final double dividends; // account currency
  final double equity; // account currency
  final double equityPhp; // reporting currency
  final int closedTrades;
  final int wins;
  final int losses;
  final int openTrades;

  AccountMetrics({
    required this.account,
    required this.netCashflow,
    required this.realizedPnl,
    required this.dividends,
    required this.equity,
    required this.equityPhp,
    required this.closedTrades,
    required this.wins,
    required this.losses,
    required this.openTrades,
  });

  double get winRate =>
      closedTrades == 0 ? 0 : wins / closedTrades;

  double get investedCapital => account.startingCapital + netCashflow;

  double get returnPct {
    final base = investedCapital;
    if (base == 0) return 0;
    return (realizedPnl + dividends) / base;
  }
}

AccountMetrics computeAccountMetrics(
  Account a,
  List<Cashflow> cashflows,
  List<Trade> trades,
  List<Dividend> dividends,
) {
  double net = 0;
  double netPhp = 0;
  for (final c in cashflows) {
    final sign = c.isDeposit ? 1 : -1;
    net += sign * c.amount;
    netPhp += sign * c.php;
  }
  double pnl = 0;
  int closed = 0, wins = 0, losses = 0, open = 0;
  for (final t in trades) {
    if (t.isOpen) {
      open++;
      continue;
    }
    closed++;
    pnl += t.pnl;
    if (t.pnl > 0) wins++;
    if (t.pnl < 0) losses++;
  }
  double div = 0;
  for (final d in dividends) {
    div += d.netAmount;
  }

  final equity = a.startingCapital + net + pnl + div;
  // PHP valuation: start capital & pnl & dividends via account fx; cashflows
  // use their own dated fx (falls back to fx=1 for PHP accounts).
  final equityPhp =
      a.startingCapital * a.fxToPhp + netPhp + pnl * a.fxToPhp + div * a.fxToPhp;

  return AccountMetrics(
    account: a,
    netCashflow: net,
    realizedPnl: pnl,
    dividends: div,
    equity: equity,
    equityPhp: equityPhp,
    closedTrades: closed,
    wins: wins,
    losses: losses,
    openTrades: open,
  );
}

class MonthStat {
  final String key;
  final double startCap;
  final double endCap;
  final double pnl;
  final double net; // deposits - withdrawals this month
  final double ret; // monthly return %
  final double twr; // cumulative time-weighted return %
  MonthStat(this.key, this.startCap, this.endCap, this.pnl, this.net, this.ret,
      this.twr);

  String get label => monthLabel(key);
}

/// Monthly P&L and time-weighted return, mirroring the spreadsheet's
/// Start / End / P&L / Return% / TWR% columns.
List<MonthStat> monthlyStats(
  Account a,
  List<Cashflow> cashflows,
  List<Trade> trades,
) {
  final months = <String>{};
  for (final t in trades) {
    if (!t.isOpen) months.add(monthKey(t.date));
  }
  for (final c in cashflows) {
    months.add(monthKey(c.date));
  }
  final sorted = months.toList()..sort();

  final out = <MonthStat>[];
  double running = a.startingCapital;
  double twrFactor = 1;
  for (final m in sorted) {
    double pnl = 0;
    for (final t in trades) {
      if (!t.isOpen && monthKey(t.date) == m) pnl += t.pnl;
    }
    double net = 0;
    for (final c in cashflows) {
      if (monthKey(c.date) == m) net += (c.isDeposit ? 1 : -1) * c.amount;
    }
    final startCap = running;
    final endCap = startCap + net + pnl;
    final ret = startCap > 0 ? pnl / startCap : 0.0;
    twrFactor *= (1 + ret);
    out.add(MonthStat(m, startCap, endCap, pnl, net, ret, twrFactor - 1));
    running = endCap;
  }
  return out;
}

class EquityPoint {
  final String date;
  final double equity;
  EquityPoint(this.date, this.equity);
}

/// Cumulative equity after each closed trade (for the equity curve chart).
List<EquityPoint> equityCurve(Account a, List<Trade> trades) {
  final closed = trades.where((t) => !t.isOpen).toList()
    ..sort((x, y) => x.date.compareTo(y.date));
  final pts = <EquityPoint>[EquityPoint(a.createdAt, a.startingCapital)];
  double eq = a.startingCapital;
  for (final t in closed) {
    eq += t.pnl;
    pts.add(EquityPoint(t.date, eq));
  }
  return pts;
}
