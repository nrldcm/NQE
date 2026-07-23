// Statistics — per-account trading performance: summary metrics, monthly P&L
// and equity charts, plus a spreadsheet-style monthly breakdown table.
import 'package:flutter/material.dart';

import '../calc.dart';
import '../db/database.dart';
import '../format.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'performance_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String? _selectedId;

  // Simple single-entry cache so we don't re-query the DB on every rebuild.
  String? _cacheId;
  Future<_StatsData>? _cache;

  Future<_StatsData> _dataFor(String accountId) {
    if (_cacheId != accountId || _cache == null) {
      _cacheId = accountId;
      _cache = _fetch(accountId);
    }
    return _cache!;
  }

  Future<_StatsData> _fetch(String accountId) async {
    final db = LedgerDb.instance;
    final cashflows = await db.cashflows(accountId);
    final trades = await db.trades(accountId);
    return _StatsData(cashflows: cashflows, trades: trades);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Monthly Performance',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PerformanceScreen())),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final accounts = appState.accounts;

          if (accounts.isEmpty) {
            if (appState.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            return const EmptyState(
              icon: Icons.bar_chart,
              title: 'No data yet',
              subtitle: 'Add a book and some trades first',
            );
          }

          // Resolve the effective selection (default to the first account).
          Account account = accounts.firstWhere(
            (a) => a.id == _selectedId,
            orElse: () => accounts.first,
          );

          return Column(
            children: [
              _AccountChips(
                accounts: accounts,
                value: account.id,
                onChanged: (id) => setState(() => _selectedId = id),
              ),
              Expanded(
                child: FutureBuilder<_StatsData>(
                  future: _dataFor(account.id),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done ||
                        !snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _StatsBody(account: account, data: snap.data!);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatsData {
  final List<Cashflow> cashflows;
  final List<Trade> trades;
  const _StatsData({required this.cashflows, required this.trades});
}

/// Always-visible, horizontally-scrollable account picker (chips). Avoids the
/// dropdown-menu scroll quirk where top items could scroll out of reach.
class _AccountChips extends StatelessWidget {
  final List<Account> accounts;
  final String value;
  final ValueChanged<String> onChanged;
  const _AccountChips({
    required this.accounts,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        itemCount: accounts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final a = accounts[i];
          final selected = a.id == value;
          return GestureDetector(
            onTap: () => onChanged(a.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? pal.surface2 : pal.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? pal.textHi : pal.line,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: Color(a.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    a.name,
                    style: TextStyle(
                      color: selected ? pal.textHi : pal.textLo,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  final Account account;
  final _StatsData data;
  const _StatsBody({required this.account, required this.data});

  @override
  Widget build(BuildContext context) {
    final a = account;
    final metrics = computeAccountMetrics(
      a,
      data.cashflows,
      data.trades,
      const <Dividend>[],
    );
    final months = monthlyStats(a, data.cashflows, data.trades);
    final curve = equityCurve(a, data.trades, cashflows: data.cashflows);

    // Best / worst month by realised P&L.
    MonthStat? best;
    MonthStat? worst;
    for (final s in months) {
      if (best == null || s.pnl > best.pnl) best = s;
      if (worst == null || s.pnl < worst.pnl) worst = s;
    }

    // Uniform, equal-size cards (grid) — never uneven rows.
    // Order: Closed trades | Win rate  (top),  Realized P/L | Best month.
    final cards = <Widget>[
      StatCard(
        label: 'Closed trades',
        value: '${metrics.closedTrades}',
        sub: '${metrics.openTrades} open',
        icon: Icons.check_circle_outline,
      ),
      StatCard(
        label: 'Win rate',
        value: pct(metrics.winRate),
        sub: '${metrics.wins}W / ${metrics.losses}L',
        icon: Icons.percent,
      ),
      StatCard(
        label: 'Realized P/L',
        value: signedMoney(metrics.realizedPnl, currency: a.currency),
        valueColor: NqeColors.pnl(metrics.realizedPnl),
        icon: Icons.trending_up,
      ),
      StatCard(
        label: 'Best month',
        value: best == null || best.pnl == 0
            ? '—'
            : signedMoney(best.pnl, currency: a.currency),
        sub: best == null || best.pnl == 0 ? null : best.label,
        valueColor: best == null ? null : NqeColors.pnl(best.pnl),
        icon: Icons.emoji_events_outlined,
      ),
      if (worst != null && worst.pnl < 0)
        StatCard(
          label: 'Worst month',
          value: signedMoney(worst.pnl, currency: a.currency),
          sub: worst.label,
          valueColor: NqeColors.pnl(worst.pnl),
          icon: Icons.trending_down,
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.55,
          children: cards,
        ),
        const SizedBox(height: 20),
        MonthlyPnlChart(months),
        const SizedBox(height: 16),
        EquityCurveChart(curve, currency: a.currency),
        const SizedBox(height: 20),
        SectionTitle('Monthly breakdown'),
        const SizedBox(height: 8),
        _MonthlyTable(account: a, months: months),
      ],
    );
  }
}

class _MonthlyTable extends StatelessWidget {
  final Account account;
  final List<MonthStat> months;
  const _MonthlyTable({required this.account, required this.months});

  static const double _wMonth = 78;
  static const double _wNum = 108;
  static const double _wPct = 84;

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;

    if (months.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.line),
        ),
        child: Center(
          child: Text('No monthly data yet',
              style: TextStyle(color: pal.textLo)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerRow(pal),
            for (final s in months) _dataRow(context, s),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(NqePalette pal) {
    TextStyle style = TextStyle(
      color: pal.textLo,
      fontSize: 11,
      letterSpacing: 0.6,
      fontWeight: FontWeight.w700,
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.line)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
      child: Row(
        children: [
          _cell('MONTH', _wMonth, style, Alignment.centerLeft),
          _cell('START', _wNum, style, Alignment.centerRight),
          _cell('END', _wNum, style, Alignment.centerRight),
          _cell('P&L', _wNum, style, Alignment.centerRight),
          _cell('RETURN%', _wPct, style, Alignment.centerRight),
          _cell('TWR%', _wPct, style, Alignment.centerRight),
        ],
      ),
    );
  }

  Widget _dataRow(BuildContext context, MonthStat s) {
    final pal = context.nqe;
    final cur = account.currency;
    final base = TextStyle(color: pal.textHi, fontSize: 13);
    final lo = TextStyle(color: pal.textLo, fontSize: 13);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.line.withOpacity(0.6))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
      child: Row(
        children: [
          _cell(
            s.label,
            _wMonth,
            base.copyWith(fontWeight: FontWeight.w700),
            Alignment.centerLeft,
          ),
          _cell(money(s.startCap, currency: cur), _wNum, lo,
              Alignment.centerRight),
          _cell(money(s.endCap, currency: cur), _wNum, base,
              Alignment.centerRight),
          _cell(
            signedMoney(s.pnl, currency: cur),
            _wNum,
            base.copyWith(
                color: NqeColors.pnl(s.pnl), fontWeight: FontWeight.w700),
            Alignment.centerRight,
          ),
          _cell(signedPct(s.ret), _wPct, lo, Alignment.centerRight),
          _cell(
            signedPct(s.twr),
            _wPct,
            base.copyWith(
                color: NqeColors.pnl(s.twr), fontWeight: FontWeight.w700),
            Alignment.centerRight,
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, double width, TextStyle style, Alignment align) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: align,
        child: Text(text, style: style, maxLines: 1),
      ),
    );
  }
}
