// Open positions (live P/L, ROI, liquidation) with one-tap close, plus the
// pending-order book with cancel. Real-time via [simState].
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/common.dart';
import '../sim_models.dart';
import '../sim_state.dart';
import 'sandbox_common.dart';

class SandboxPositionsPanel extends StatelessWidget {
  final ValueChanged<String>? onSelect;
  const SandboxPositionsPanel({super.key, this.onSelect});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: simState,
      builder: (context, _) {
        final positions = simState.positions;
        final orders = simState.openOrders;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SectionTitle('Open Positions'),
            if (positions.isEmpty)
              _empty(context, Icons.pie_chart_outline, 'No open positions',
                  'Place a trade to open one.')
            else
              ...positions.map((p) => _PositionTile(p, onSelect: onSelect)),
            const SizedBox(height: 14),
            SectionTitle('Pending Orders',
                trailing: orders.isEmpty
                    ? null
                    : Text('${orders.length}',
                        style: TextStyle(
                            color: context.nqe.textLo,
                            fontWeight: FontWeight.w700))),
            if (orders.isEmpty)
              _empty(context, Icons.receipt_long_outlined, 'No pending orders',
                  'Limit, stop and take-profit orders show here.')
            else
              ...orders.map((o) => _OrderTile(o)),
          ],
        );
      },
    );
  }

  Widget _empty(BuildContext c, IconData i, String t, String s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SimCard(
          child: Row(
            children: [
              Icon(i, color: c.nqe.textLo, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t,
                        style: TextStyle(
                            color: c.nqe.textHi, fontWeight: FontWeight.w600)),
                    Text(s, style: TextStyle(color: c.nqe.textLo, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _PositionTile extends StatelessWidget {
  final SimPosition pos;
  final ValueChanged<String>? onSelect;
  const _PositionTile(this.pos, {this.onSelect});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final price = simState.priceOf(pos.symbol);
    // Convert the P/L into the account base currency (e.g. USD-quoted crypto
    // → PHP); ROI is currency-independent.
    final pnl = pos.unrealizedPnl(price) * simState.fxOf(pos.symbol);
    final roi = pos.roiPct(price);
    final long = pos.side == PositionSide.long;
    final sideColor = long ? NqeColors.gain : NqeColors.loss;
    final liq = pos.liquidationPrice;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onSelect == null ? null : () => onSelect!(pos.symbol),
        child: SimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MarketBadge(pos.market, dense: true),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(pos.symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: pal.textHi,
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: sideColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '${long ? 'LONG' : 'SHORT'}'
                      '${pos.mode == TradeMode.margin ? ' ${pos.leverage.toStringAsFixed(0)}x' : ''}',
                      style: TextStyle(
                          color: sideColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                            simSignedMoney(pnl, currency: simState.currency),
                            maxLines: 1,
                            style: TextStyle(
                                color: NqeColors.pnl(pnl),
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                      ),
                      Text(signedPctStr(roi),
                          style: TextStyle(
                              color: NqeColors.pnl(pnl),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _kv(context, 'Qty', fmtQty(pos.qty)),
                  _kv(context, 'Entry', fmtPrice(pos.avgPrice, pos.market)),
                  _kv(context, 'Mark', fmtPrice(price, pos.market)),
                  if (liq != null)
                    _kv(context, 'Liq.', fmtPrice(liq, pos.market),
                        color: NqeColors.loss),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmClose(context),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Close position'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pal.textHi,
                        side: BorderSide(color: pal.line),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClose(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Close position?'),
        content: Text(
            'Market-close your ${pos.symbol} position at the current price.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Close')),
        ],
      ),
    );
    if (ok == true) {
      final err = await simState.closePosition(pos);
      if (err != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(err), backgroundColor: NqeColors.loss));
      }
    }
  }

  Widget _kv(BuildContext context, String k, String v, {Color? color}) {
    final pal = context.nqe;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: pal.textLo, fontSize: 9, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(v,
                maxLines: 1,
                style: TextStyle(
                    color: color ?? pal.textHi,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final SimOrder order;
  const _OrderTile(this.order);

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final buy = order.side == OrderSide.buy;
    final trigger = order.limitPrice ?? order.stopPrice;
    final typeLabel = switch (order.type) {
      OrderType.limit => 'Limit',
      OrderType.stop => 'Stop',
      OrderType.takeProfit => 'Take-profit',
      OrderType.market => 'Market',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SimCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(buy ? Icons.arrow_upward : Icons.arrow_downward,
                size: 18, color: buy ? NqeColors.gain : NqeColors.loss),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${order.symbol}  ·  $typeLabel',
                      style: TextStyle(
                          color: pal.textHi, fontWeight: FontWeight.w700)),
                  Text(
                    '${buy ? 'Buy' : 'Sell'} ${fmtQty(order.qty)}'
                    '${trigger != null ? ' @ ${fmtPrice(trigger, order.market)}' : ''}'
                    '${order.mode == TradeMode.margin ? ' · ${order.leverage.toStringAsFixed(0)}x' : ''}',
                    style: TextStyle(color: pal.textLo, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: NqeColors.loss,
              onPressed: () => simState.cancelOrder(order.id),
            ),
          ],
        ),
      ),
    );
  }
}
