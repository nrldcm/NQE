// Portfolio dashboard — total AUM, allocation, and a list of trading books.
import 'package:flutter/material.dart';

import '../calc.dart';
import '../format.dart';
import '../models.dart';
import '../sim/ui/sandbox_books.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/nqe_logo.dart';
import 'account_detail_screen.dart';
import 'editors/account_edit_sheet.dart';
import 'stats_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: () => appState.load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _Header(),
                const SizedBox(height: 20),
                _HeroCard(),
                const SizedBox(height: 12),
                // Detailed per-account trading statistics live here in the
                // overview (the Performance tab is the monthly summary).
                Material(
                  color: pal.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const StatsScreen())),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: pal.line),
                      ),
                      child: Row(children: [
                        Icon(Icons.insights, size: 20, color: pal.textHi),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Trading statistics',
                                  style: TextStyle(
                                      color: pal.textHi,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text('Per-book charts & breakdown',
                                  style: TextStyle(
                                      color: pal.textLo, fontSize: 12)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 20, color: pal.textLo),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (appState.accounts.isNotEmpty) ...[
                  AllocationDonut(
                    appState.accounts
                        .map((a) => appState.metricsFor(a.id))
                        .whereType<AccountMetrics>()
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                ],
                SectionTitle(
                  'Books',
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    color: pal.textHi,
                    tooltip: 'New book',
                    onPressed: () => showAccountEditor(context),
                  ),
                ),
                const SizedBox(height: 4),
                // The simulation book (view-only) always sits at the top of the
                // Home books list too, so the Sandbox surfaces from Home.
                const SandboxBooksTile(),
                if (appState.accounts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: EmptyState(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'No real books yet',
                      subtitle: 'Create your first trading book',
                      action: FilledButton.icon(
                        onPressed: () => showAccountEditor(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New book'),
                      ),
                    ),
                  )
                else
                  ...appState.accounts.map((a) => _BookRow(account: a)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: NqeLogo(scale: 0.32, showTagline: false),
          ),
        ),
        Opacity(
          opacity: 0.7,
          child: WillongByline(scale: 0.9, color: pal.textLo),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ASSETS UNDER MANAGEMENT',
            style: TextStyle(
              color: pal.textLo,
              fontSize: 11,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              money(appState.totalAumPhp, currency: 'PHP'),
              maxLines: 1,
              style: TextStyle(
                color: pal.textHi,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _InlineStat(
                  label: 'REALIZED P/L',
                  value: signedMoney(appState.totalRealizedPhp),
                  valueColor: NqeColors.pnl(appState.totalRealizedPhp),
                ),
              ),
              Container(width: 1, height: 34, color: pal.line),
              Expanded(
                child: _InlineStat(
                  label: 'WIN RATE',
                  value: pct(appState.overallWinRate),
                  valueColor: pal.textHi,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _InlineStat({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: pal.textLo,
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: valueColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _BookRow extends StatelessWidget {
  final Account account;
  const _BookRow({required this.account});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final a = account;
    final m = appState.metricsFor(a.id);
    final equity = m?.equity ?? 0;
    final realized = m?.realizedPnl ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AccountDetailScreen(accountId: a.id),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: pal.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(a.color),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pal.textHi,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (a.broker.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          a.broker,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: pal.textLo, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          money(equity, currency: a.currency),
                          maxLines: 1,
                          style: TextStyle(
                            color: pal.textHi,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: PnlText(
                          realized,
                          signedMoney(realized, currency: a.currency),
                          size: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
