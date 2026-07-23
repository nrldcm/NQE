// Sandbox performance analytics + the executed-trade blotter (ledger). All
// isolated to the simulation account.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme.dart';
import '../../widgets/common.dart';
import '../sim_models.dart';
import '../sim_state.dart';
import 'sandbox_common.dart';

class SandboxAnalyticsPanel extends StatelessWidget {
  const SandboxAnalyticsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: simState,
      builder: (context, _) {
        final acc = simState.account;
        final trades = simState.trades;
        final closed = trades.where((t) => t.realizedPnl != 0).toList();
        final wins = closed.where((t) => t.realizedPnl > 0).length;
        final winRate = closed.isEmpty ? 0.0 : wins / closed.length * 100;
        final fees = trades.fold<double>(0, (s, t) => s + t.fee);
        final equity = simState.equity;
        final start = acc?.startingCash ?? 0;
        final totalRet = start == 0 ? 0.0 : (equity - start) / start * 100;
        final cur = simState.currency;

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SectionTitle('Overview'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.8,
              children: [
                StatCard(
                    label: 'Equity',
                    value: simMoney(equity, currency: cur),
                    icon: Icons.account_balance_wallet_outlined),
                StatCard(
                  label: 'Total return',
                  value: signedPctStr(totalRet),
                  valueColor: NqeColors.pnl(totalRet),
                  icon: Icons.trending_up,
                ),
                StatCard(
                  label: 'Realized P/L',
                  value: simSignedMoney(acc?.realizedPnl ?? 0, currency: cur),
                  valueColor: NqeColors.pnl(acc?.realizedPnl ?? 0),
                  icon: Icons.paid_outlined,
                ),
                StatCard(
                  label: 'Win rate',
                  value: closed.isEmpty ? '—' : '${winRate.toStringAsFixed(0)}%',
                  sub: '${closed.length} closed',
                  icon: Icons.emoji_events_outlined,
                ),
                StatCard(
                    label: 'Fees paid',
                    value: simMoney(fees, currency: cur),
                    icon: Icons.receipt_outlined),
                StatCard(
                    label: 'Total trades',
                    value: '${trades.length}',
                    icon: Icons.swap_horiz),
              ],
            ),
            const SizedBox(height: 8),
            const SectionTitle('Trade History'),
            if (trades.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: EmptyState(
                  icon: Icons.history,
                  title: 'No trades yet',
                  subtitle: 'Your executed fills appear here.',
                ),
              )
            else
              ...trades.map((t) => _TradeRow(t)),
          ],
        );
      },
    );
  }
}

class _TradeRow extends StatelessWidget {
  final SimTrade t;
  const _TradeRow(this.t);

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final buy = t.side == OrderSide.buy;
    final time = DateTime.fromMillisecondsSinceEpoch(t.tsMs);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SimCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (buy ? NqeColors.gain : NqeColors.loss).withOpacity(0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(buy ? Icons.south_west : Icons.north_east,
                  size: 16, color: buy ? NqeColors.gain : NqeColors.loss),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${buy ? 'Buy' : 'Sell'} ${t.symbol}',
                          style: TextStyle(
                              color: pal.textHi, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      if (t.mode == TradeMode.margin)
                        Text('MARGIN',
                            style: TextStyle(
                                color: pal.textLo,
                                fontSize: 9,
                                fontWeight: FontWeight.w800)),
                    ],
                  ),
                  Text(
                    '${fmtQty(t.qty)} @ ${fmtPrice(t.price, t.market)} · '
                    '${DateFormat('MMM d, HH:mm').format(time)}',
                    style: TextStyle(color: pal.textLo, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (t.realizedPnl != 0)
              Text(simSignedMoney(t.realizedPnl, currency: simState.currency),
                  style: TextStyle(
                      color: NqeColors.pnl(t.realizedPnl),
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
