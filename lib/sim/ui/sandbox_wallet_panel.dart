// The Sandbox "Wallet" — Free Cash is the wallet balance. From here you can
// Top Up (add virtual cash) or Cash Out (withdraw), like funding a real
// account, except every peso here is simulated. Deposits/withdrawals adjust
// the deposit basis too, so they never masquerade as trading P&L.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../sim_state.dart';
import 'sandbox_common.dart';

class SandboxWalletPanel extends StatelessWidget {
  const SandboxWalletPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: simState,
      builder: (context, _) {
        final pal = context.nqe;
        final cur = simState.currency;
        final free = simState.freeCash;
        final equity = simState.equity;
        final invested = (equity - free).clamp(0, double.infinity).toDouble();
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            SimCard(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          size: 18, color: pal.textHi),
                      const SizedBox(width: 8),
                      Text('WALLET · FREE CASH',
                          style: TextStyle(
                              color: pal.textLo,
                              fontSize: 11,
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      simMoney(free, currency: cur),
                      maxLines: 1,
                      style: TextStyle(
                          color: pal.textHi,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _stat(context, 'Equity', simMoney(equity, currency: cur)),
                      Container(width: 1, height: 32, color: pal.line),
                      _stat(context, 'In positions',
                          simMoney(invested, currency: cur)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => sandboxTopUp(context),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Top Up'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              free > 0 ? () => sandboxCashOut(context) : null,
                          icon: const Icon(Icons.arrow_outward, size: 18),
                          label: const Text('Cash Out'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: pal.textLo),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Virtual funds — simulation only. Top-ups and cash-outs '
                    'adjust your Free Cash without affecting your Total Return.',
                    style: TextStyle(color: pal.textLo, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final pal = context.nqe;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 2, right: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                    color: pal.textLo, fontSize: 10, letterSpacing: 0.6)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: TextStyle(
                      color: pal.textHi,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

}

/// Open the Top Up dialog and apply the deposit. Shared by the Wallet panel
/// and the Sandbox header menu (desktop).
Future<void> sandboxTopUp(BuildContext context) async {
  final amount = await _amountDialog(
    context,
    title: 'Top Up Wallet',
    cta: 'Add funds',
    presets: const [10000, 50000, 100000, 1000000],
  );
  if (amount != null) await simState.topUp(amount);
}

/// Open the Cash Out dialog and apply the withdrawal (capped at Free Cash).
Future<void> sandboxCashOut(BuildContext context) async {
  final max = simState.freeCash;
  if (max <= 0) return;
  final amount = await _amountDialog(
    context,
    title: 'Cash Out',
    cta: 'Withdraw',
    presets: const [10000, 50000, 100000],
    max: max,
  );
  if (amount != null) {
    final ok = await simState.cashOut(amount);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Amount exceeds your available Free Cash.')));
    }
  }
}

/// Shared amount-entry dialog with quick presets. When [max] is set (cash-out),
/// the field is capped and a "Max" chip fills it with the whole balance.
Future<double?> _amountDialog(
  BuildContext context, {
  required String title,
  required String cta,
  required List<double> presets,
  double? max,
}) {
  final cur = simState.currency;
  final ctrl = TextEditingController();
  return showDialog<double>(
    context: context,
    builder: (c) {
      final pal = c.nqe;
      return StatefulBuilder(builder: (c, setState) {
        double parsed() =>
            double.tryParse(ctrl.text.replaceAll(',', '').trim()) ?? 0;
        final v = parsed();
        final over = max != null && v > max;
        final valid = v > 0 && !over;
        void setAmt(double a) {
          ctrl.text = a == a.roundToDouble()
              ? a.toStringAsFixed(0)
              : a.toStringAsFixed(2);
          setState(() {});
        }

        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (max != null) ...[
                Text('Available: ${simMoney(max, currency: cur)}',
                    style: TextStyle(color: pal.textLo, fontSize: 12)),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixText: '${currencyGlyph(cur)} ',
                  hintText: '0.00',
                  errorText: over ? 'More than available' : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in presets)
                    ActionChip(
                      label: Text('+${compactAmount(p)}'),
                      onPressed: (max != null && p > max)
                          ? null
                          : () => setAmt(p),
                    ),
                  if (max != null && max > 0)
                    ActionChip(
                      label: const Text('Max'),
                      onPressed: () => setAmt(max),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: valid ? () => Navigator.pop(c, v) : null,
              child: Text(cta),
            ),
          ],
        );
      });
    },
  );
}

/// Currency glyph for a prefix (₱ for PHP, $ for USD, else the code).
String currencyGlyph(String cur) => switch (cur) {
      'PHP' => '₱',
      'USD' => '\$',
      _ => cur,
    };

/// Compact preset label, e.g. 10000 → "10K", 1000000 → "1M".
String compactAmount(double v) {
  if (v >= 1000000) {
    final m = v / 1000000;
    return '${m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1)}M';
  }
  if (v >= 1000) {
    final k = v / 1000;
    return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}K';
  }
  return v.toStringAsFixed(0);
}
