// Per-account detail view: overview stats, trades, cashflows and (for dividend
// books) dividends + holdings. All editing is delegated to the shared editors,
// which persist and refresh global state; this screen refreshes its own lists.
import 'package:flutter/material.dart';

import '../calc.dart';
import '../db/database.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'editors/account_edit_sheet.dart';
import 'editors/cashflow_edit_sheet.dart';
import 'editors/dividend_edit_sheet.dart';
import 'editors/holding_edit_sheet.dart';
import 'editors/trade_edit_sheet.dart';
import 'performance_screen.dart';

class AccountDetailScreen extends StatefulWidget {
  final String accountId;
  const AccountDetailScreen({super.key, required this.accountId});

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  Account? _account;
  List<Cashflow> _cashflows = const [];
  List<Trade> _trades = const [];
  List<Dividend> _dividends = const [];
  List<Holding> _holdings = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final db = LedgerDb.instance;
    final accounts = await db.accounts(includeArchived: true);
    if (!mounted) return;
    Account? acc;
    for (final a in accounts) {
      if (a.id == widget.accountId) {
        acc = a;
        break;
      }
    }
    if (acc == null) {
      // The account was deleted elsewhere — leave the screen.
      setState(() {
        _account = null;
        _loading = false;
      });
      return;
    }
    final cashflows = await db.cashflows(acc.id);
    final trades = await db.trades(acc.id);
    final dividends = await db.dividends(acc.id);
    final holdings = await db.holdings(acc.id);
    if (!mounted) return;
    setState(() {
      _account = acc;
      _cashflows = cashflows;
      _trades = trades;
      _dividends = dividends;
      _holdings = holdings;
      _loading = false;
    });
  }

  Future<bool> _accountStillExists() async {
    final accounts = await LedgerDb.instance.accounts(includeArchived: true);
    return accounts.any((a) => a.id == widget.accountId);
  }

  Future<void> _editAccount() async {
    final acc = _account;
    if (acc == null) return;
    final changed = await showAccountEditor(context, existing: acc);
    if (!changed) return;
    if (!mounted) return;
    final exists = await _accountStillExists();
    if (!mounted) return;
    if (!exists) {
      Navigator.pop(context);
      return;
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _loading
            ? const Center(
                key: ValueKey('loading'), child: CircularProgressIndicator())
            : _account == null
                ? _buildMissing(context)
                : _buildContent(context, _account!),
      ),
    );
  }

  Widget _buildMissing(BuildContext context) {
    return Scaffold(
      key: const ValueKey('missing'),
      backgroundColor: context.nqe.bg,
      appBar: AppBar(),
      body: const EmptyState(
        icon: Icons.help_outline,
        title: 'Account not found',
        subtitle: 'This book may have been deleted.',
      ),
    );
  }

  Widget _buildContent(BuildContext context, Account account) {
    final isDividend = account.kind == AccountKind.dividend;
    final tabs = <Tab>[
      const Tab(text: 'Overview'),
      const Tab(text: 'Trades'),
      const Tab(text: 'Cash'),
      if (isDividend) const Tab(text: 'Dividends'),
    ];
    final pal = context.nqe;

    return DefaultTabController(
      key: ValueKey('content-${account.id}'),
      length: tabs.length,
      child: Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: Color(account.color),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Flexible(
                child: Text(account.name, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Edit account',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _editAccount,
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: pal.textHi,
            unselectedLabelColor: pal.textLo,
            indicatorColor: pal.textHi,
            tabs: tabs,
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(
              account: account,
              cashflows: _cashflows,
              trades: _trades,
              dividends: _dividends,
            ),
            _TradesTab(
              account: account,
              trades: _trades,
              onChanged: _reload,
            ),
            _CashTab(
              account: account,
              cashflows: _cashflows,
              onChanged: _reload,
            ),
            if (isDividend)
              _DividendsTab(
                account: account,
                dividends: _dividends,
                holdings: _holdings,
                onChanged: _reload,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------
class _OverviewTab extends StatelessWidget {
  final Account account;
  final List<Cashflow> cashflows;
  final List<Trade> trades;
  final List<Dividend> dividends;
  const _OverviewTab({
    required this.account,
    required this.cashflows,
    required this.trades,
    required this.dividends,
  });

  @override
  Widget build(BuildContext context) {
    final m = computeAccountMetrics(account, cashflows, trades, dividends);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            StatCard(
              label: 'Equity',
              value: money(m.equity, currency: account.currency),
              icon: Icons.account_balance_wallet_outlined,
            ),
            StatCard(
              label: 'Realized P/L',
              value: signedMoney(m.realizedPnl, currency: account.currency),
              valueColor: NqeColors.pnl(m.realizedPnl),
              icon: Icons.trending_up,
            ),
            StatCard(
              label: 'Win rate',
              value: pct(m.winRate),
              sub: '${m.wins}W · ${m.losses}L',
              icon: Icons.emoji_events_outlined,
            ),
            StatCard(
              label: 'Invested',
              value: money(m.investedCapital, currency: account.currency),
              icon: Icons.savings_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PerformanceCard(account: account),
        const SizedBox(height: 16),
        EquityCurveChart(
            equityCurve(account, trades,
                cashflows: cashflows, dividends: dividends),
            currency: account.currency),
        const SizedBox(height: 16),
        WinLossDonut(wins: m.wins, losses: m.losses),
      ],
    );
  }
}

/// Entry point to this book's own Monthly Performance tracker (its manually
/// maintained month-by-month summary), scoped to the account.
class _PerformanceCard extends StatelessWidget {
  final Account account;
  const _PerformanceCard({required this.account});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Material(
      color: pal.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PerformanceScreen(
              accountId: account.id, accountName: account.name),
        )),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.line),
          ),
          child: Row(children: [
            Icon(Icons.calendar_month_outlined, size: 20, color: pal.textHi),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly Performance',
                      style: TextStyle(
                          color: pal.textHi,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Month-by-month P&L, TWR & drawdown',
                      style: TextStyle(color: pal.textLo, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: pal.textLo),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trades
// ---------------------------------------------------------------------------
class _TradesTab extends StatelessWidget {
  final Account account;
  final List<Trade> trades;
  final Future<void> Function() onChanged;
  const _TradesTab({
    required this.account,
    required this.trades,
    required this.onChanged,
  });

  Future<void> _add(BuildContext context) async {
    final ok = await showTradeEditor(context,
        accountId: account.id, currency: account.currency);
    if (ok) await onChanged();
  }

  Future<void> _edit(BuildContext context, Trade t) async {
    final ok = await showTradeEditor(context,
        accountId: account.id, currency: account.currency, existing: t);
    if (ok) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...trades]..sort((a, b) => b.date.compareTo(a.date));
    return Column(
      children: [
        _AddBar(label: 'Add trade', onPressed: () => _add(context)),
        Expanded(
          child: sorted.isEmpty
              ? EmptyState(
                  icon: Icons.candlestick_chart_outlined,
                  title: 'No trades yet',
                  subtitle: 'Log your first position to start tracking P&L.',
                  action: FilledButton(
                    onPressed: () => _add(context),
                    child: const Text('Add trade'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) =>
                      _TradeRow(account: account, trade: sorted[i], onTap: () {
                    _edit(context, sorted[i]);
                  }),
                ),
        ),
      ],
    );
  }
}

class _TradeRow extends StatelessWidget {
  final Account account;
  final Trade trade;
  final VoidCallback onTap;
  const _TradeRow(
      {required this.account, required this.trade, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return _RowCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        trade.stock.isEmpty ? '—' : trade.stock,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pal.textHi,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (trade.setup.trim().isNotEmpty)
                      Flexible(child: Pill(trade.setup, color: pal.textLo)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${shortDate(trade.date)} · ${num2(trade.shares)} sh',
                  style: TextStyle(color: pal.textLo, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (trade.isOpen)
            Pill('OPEN', color: pal.textLo)
          else
            Text(
              signedMoney(trade.pnl, currency: account.currency),
              style: TextStyle(
                color: NqeColors.pnl(trade.pnl),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cash
// ---------------------------------------------------------------------------
class _CashTab extends StatelessWidget {
  final Account account;
  final List<Cashflow> cashflows;
  final Future<void> Function() onChanged;
  const _CashTab({
    required this.account,
    required this.cashflows,
    required this.onChanged,
  });

  Future<void> _add(BuildContext context) async {
    final ok = await showCashflowEditor(context,
        accountId: account.id,
        currency: account.currency,
        fxToPhp: account.fxToPhp);
    if (ok) await onChanged();
  }

  Future<void> _edit(BuildContext context, Cashflow c) async {
    final ok = await showCashflowEditor(context,
        accountId: account.id,
        currency: account.currency,
        fxToPhp: account.fxToPhp,
        existing: c);
    if (ok) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final sorted = [...cashflows]..sort((a, b) => b.date.compareTo(a.date));
    double net = 0;
    for (final c in cashflows) {
      net += (c.isDeposit ? 1 : -1) * c.amount;
    }
    return Column(
      children: [
        _AddBar(label: 'Add', onPressed: () => _add(context)),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('NET CASHFLOW',
                  style: TextStyle(
                    color: pal.textLo,
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  )),
              Text(
                money(net, currency: account.currency),
                style: TextStyle(
                  color: pal.textHi,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: sorted.isEmpty
              ? EmptyState(
                  icon: Icons.swap_vert,
                  title: 'No cashflows yet',
                  subtitle: 'Record deposits and withdrawals here.',
                  action: FilledButton(
                    onPressed: () => _add(context),
                    child: const Text('Add cashflow'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _CashRow(
                    account: account,
                    cashflow: sorted[i],
                    onTap: () => _edit(context, sorted[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _CashRow extends StatelessWidget {
  final Account account;
  final Cashflow cashflow;
  final VoidCallback onTap;
  const _CashRow(
      {required this.account, required this.cashflow, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final deposit = cashflow.isDeposit;
    final color = deposit ? NqeColors.gain : NqeColors.loss;
    return _RowCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              deposit ? Icons.south_west : Icons.north_east,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deposit ? 'Deposit' : 'Withdrawal',
                  style: TextStyle(
                    color: pal.textHi,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cashflow.remarks.trim().isEmpty
                      ? shortDate(cashflow.date)
                      : '${shortDate(cashflow.date)} · ${cashflow.remarks}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: pal.textLo, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${deposit ? '+' : '−'}${money(cashflow.amount, currency: account.currency)}',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dividends + Holdings (dividend books only)
// ---------------------------------------------------------------------------
class _DividendsTab extends StatelessWidget {
  final Account account;
  final List<Dividend> dividends;
  final List<Holding> holdings;
  final Future<void> Function() onChanged;
  const _DividendsTab({
    required this.account,
    required this.dividends,
    required this.holdings,
    required this.onChanged,
  });

  Future<void> _addDividend(BuildContext context) async {
    final ok = await showDividendEditor(context,
        accountId: account.id, currency: account.currency);
    if (ok) await onChanged();
  }

  Future<void> _editDividend(BuildContext context, Dividend d) async {
    final ok = await showDividendEditor(context,
        accountId: account.id, currency: account.currency, existing: d);
    if (ok) await onChanged();
  }

  Future<void> _addHolding(BuildContext context) async {
    final ok = await showHoldingEditor(context, accountId: account.id);
    if (ok) await onChanged();
  }

  Future<void> _editHolding(BuildContext context, Holding h) async {
    final ok =
        await showHoldingEditor(context, accountId: account.id, existing: h);
    if (ok) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final sortedDivs = [...dividends]..sort((a, b) => b.date.compareTo(a.date));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SectionTitle(
          'Holdings',
          trailing: TextButton.icon(
            onPressed: () => _addHolding(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ),
        if (holdings.isEmpty)
          _InlineEmpty(
            icon: Icons.flag_outlined,
            text: 'No holdings targets yet.',
          )
        else
          ...holdings.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _HoldingRow(
                  account: account,
                  holding: h,
                  onTap: () => _editHolding(context, h),
                ),
              )),
        const SizedBox(height: 12),
        SectionTitle(
          'Dividends',
          trailing: TextButton.icon(
            onPressed: () => _addDividend(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ),
        if (sortedDivs.isEmpty)
          _InlineEmpty(
            icon: Icons.paid_outlined,
            text: 'No dividends recorded yet.',
          )
        else
          ...sortedDivs.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DividendRow(
                  account: account,
                  dividend: d,
                  onTap: () => _editDividend(context, d),
                ),
              )),
      ],
    );
  }
}

class _HoldingRow extends StatelessWidget {
  final Account account;
  final Holding holding;
  final VoidCallback onTap;
  const _HoldingRow(
      {required this.account, required this.holding, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return _RowCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  holding.stock.isEmpty ? '—' : holding.stock,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: pal.textHi,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${num2(holding.currentShares)} / ${num2(holding.goalShares)}',
                style: TextStyle(color: pal.textLo, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: holding.progress,
              minHeight: 8,
              backgroundColor: pal.surface2,
              valueColor: const AlwaysStoppedAnimation(NqeColors.gain),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${pct(holding.progress, decimals: 0)} of goal',
            style: TextStyle(color: pal.textLo, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _DividendRow extends StatelessWidget {
  final Account account;
  final Dividend dividend;
  final VoidCallback onTap;
  const _DividendRow(
      {required this.account, required this.dividend, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return _RowCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dividend.stock.isEmpty ? '—' : dividend.stock,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: pal.textHi,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${shortDate(dividend.date)} · ${num2(dividend.shares)} sh',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: pal.textLo, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            money(dividend.netAmount, currency: account.currency),
            style: TextStyle(
              color: NqeColors.gain,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------
class _AddBar extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _AddBar({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.add, size: 18),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.nqe.textHi,
                side: BorderSide(color: context.nqe.line),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _RowCard({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Material(
      color: pal.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: pal.line),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InlineEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pal.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: pal.textLo),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: TextStyle(color: pal.textLo, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
