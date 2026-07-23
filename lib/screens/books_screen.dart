// Books list — every trading / dividend book with equity and return at a glance.
import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../sim/ui/sandbox_books.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_detail_screen.dart';
import 'editors/account_edit_sheet.dart';

class BooksScreen extends StatelessWidget {
  const BooksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        title: const Text('Books'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New book',
            onPressed: () => showAccountEditor(context),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final accounts = appState.accounts;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // The simulation book (view-only) always sits at the top.
              const SandboxBooksTile(),
              if (accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
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
                ...accounts.map((a) => _BookTile(account: a)),
            ],
          );
        },
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final Account account;
  const _BookTile({required this.account});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final a = account;
    final m = appState.metricsFor(a.id);
    final equity = m?.equity ?? 0;
    final returnPct = m?.returnPct ?? 0;
    final isDividend = a.kind == AccountKind.dividend;

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
          onLongPress: () => showAccountEditor(context, existing: a),
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              a.name,
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
                          Pill(
                            isDividend ? 'Dividend' : 'Trading',
                            color: isDividend ? NqeColors.gain : pal.textLo,
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        a.broker.isEmpty
                            ? a.currency
                            : '${a.broker} · ${a.currency}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: pal.textLo, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
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
                      PnlText(returnPct, signedPct(returnPct), size: 12),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.edit_outlined, size: 18, color: pal.textLo),
                  tooltip: 'Edit',
                  onPressed: () => showAccountEditor(context, existing: a),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
