// Create / edit a deposit or withdrawal.
import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../util.dart';
import 'editor_scaffold.dart';

Future<bool> showCashflowEditor(
  BuildContext context, {
  required String accountId,
  String currency = 'PHP',
  double fxToPhp = 1,
  Cashflow? existing,
}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CashflowEditor(
      accountId: accountId,
      currency: currency,
      fxToPhp: fxToPhp,
      existing: existing,
    ),
  );
  return res ?? false;
}

class _CashflowEditor extends StatefulWidget {
  final String accountId;
  final String currency;
  final double fxToPhp;
  final Cashflow? existing;
  const _CashflowEditor({
    required this.accountId,
    required this.currency,
    required this.fxToPhp,
    this.existing,
  });

  @override
  State<_CashflowEditor> createState() => _CashflowEditorState();
}

class _CashflowEditorState extends State<_CashflowEditor> {
  late final TextEditingController _amount;
  late final TextEditingController _fx;
  late final TextEditingController _remarks;
  String _date = todayIso();
  String _type = 'deposit';

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _amount = TextEditingController(text: c == null ? '' : _n(c.amount));
    _fx = TextEditingController(
        text: c == null ? _n(widget.fxToPhp) : _n(c.fxRate));
    _remarks = TextEditingController(text: c?.remarks ?? '');
    _date = c?.date ?? todayIso();
    _type = c?.type ?? 'deposit';
    _amount.addListener(() => setState(() {}));
    _fx.addListener(() => setState(() {}));
  }

  String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _amount.dispose();
    _fx.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amt = double.tryParse(_amount.text.trim()) ?? 0;
    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter an amount greater than 0')));
      return;
    }
    final c = widget.existing ??
        Cashflow(
            id: uid(),
            accountId: widget.accountId,
            date: _date,
            type: _type,
            createdAt: nowIso());
    c.date = _date;
    c.type = _type;
    c.amount = amt;
    c.fxRate =
        widget.currency == 'PHP' ? 1 : (double.tryParse(_fx.text.trim()) ?? 1);
    c.remarks = _remarks.text.trim();
    await LedgerDb.instance.upsertCashflow(c);
    await appState.load();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final c = widget.existing;
    if (c == null) return;
    final ok = await confirmDelete(context, 'Delete entry?', 'This cashflow will be removed.');
    if (!ok) return;
    await LedgerDb.instance.deleteCashflow(c.id);
    await appState.load();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final amt = double.tryParse(_amount.text.trim()) ?? 0;
    final fx = double.tryParse(_fx.text.trim()) ?? 1;
    return EditorScaffold(
      title: widget.existing == null ? 'New cashflow' : 'Edit cashflow',
      onSave: _save,
      onDelete: widget.existing == null ? null : _delete,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'deposit',
                label: Text('Deposit'),
                icon: Icon(Icons.south_west)),
            ButtonSegment(
                value: 'withdrawal',
                label: Text('Withdraw'),
                icon: Icon(Icons.north_east)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        const SizedBox(height: 16),
        DatePickerField(
            label: 'Date',
            isoDate: _date,
            onChanged: (v) => setState(() => _date = v)),
        EditorField(
            label: 'Amount (${widget.currency})',
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        if (widget.currency != 'PHP') ...[
          EditorField(
              label: 'FX rate → PHP',
              controller: _fx,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true)),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('≈ ${money(amt * fx, currency: 'PHP')}',
                style: TextStyle(color: pal.textLo, fontSize: 13)),
          ),
        ],
        EditorField(label: 'Remarks', controller: _remarks, maxLines: 2),
      ],
    );
  }
}
