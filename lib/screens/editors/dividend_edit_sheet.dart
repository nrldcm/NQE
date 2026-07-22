// Create / edit a dividend receipt.
import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../util.dart';
import '../../format.dart';
import 'editor_scaffold.dart';

Future<bool> showDividendEditor(
  BuildContext context, {
  required String accountId,
  String currency = 'PHP',
  Dividend? existing,
}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DividendEditor(
        accountId: accountId, currency: currency, existing: existing),
  );
  return res ?? false;
}

class _DividendEditor extends StatefulWidget {
  final String accountId;
  final String currency;
  final Dividend? existing;
  const _DividendEditor(
      {required this.accountId, required this.currency, this.existing});

  @override
  State<_DividendEditor> createState() => _DividendEditorState();
}

class _DividendEditorState extends State<_DividendEditor> {
  late final TextEditingController _stock;
  late final TextEditingController _shares;
  late final TextEditingController _rate;
  late final TextEditingController _net;
  late final TextEditingController _remarks;
  String _date = todayIso();

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _stock = TextEditingController(text: d?.stock ?? '');
    _shares = TextEditingController(text: d == null ? '' : _n(d.shares));
    _rate = TextEditingController(text: d == null ? '' : _n(d.divRate));
    _net = TextEditingController(text: d == null ? '' : _n(d.netAmount));
    _remarks = TextEditingController(text: d?.remarks ?? '');
    _date = d?.date ?? todayIso();
    _shares.addListener(_autoNet);
    _rate.addListener(_autoNet);
  }

  void _autoNet() {
    // Auto-fill net = shares * rate if the user hasn't typed a net yet.
    if (widget.existing != null) return;
    final sh = double.tryParse(_shares.text) ?? 0;
    final r = double.tryParse(_rate.text) ?? 0;
    if (sh > 0 && r > 0) {
      _net.text = _n(sh * r);
    }
    setState(() {});
  }

  String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _stock.dispose();
    _shares.dispose();
    _rate.dispose();
    _net.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final d = widget.existing ??
        Dividend(
            id: uid(),
            accountId: widget.accountId,
            date: _date,
            createdAt: nowIso());
    d.date = _date;
    d.stock = _stock.text.trim().toUpperCase();
    d.shares = double.tryParse(_shares.text.trim()) ?? 0;
    d.divRate = double.tryParse(_rate.text.trim()) ?? 0;
    d.netAmount = double.tryParse(_net.text.trim()) ?? 0;
    d.remarks = _remarks.text.trim();
    await LedgerDb.instance.upsertDividend(d);
    await appState.load();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final d = widget.existing;
    if (d == null) return;
    final ok = await confirmDelete(
        context, 'Delete dividend?', 'This entry will be removed.');
    if (!ok) return;
    await LedgerDb.instance.deleteDividend(d.id);
    await appState.load();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return EditorScaffold(
      title: widget.existing == null ? 'New dividend' : 'Edit dividend',
      onSave: _save,
      onDelete: widget.existing == null ? null : _delete,
      children: [
        DatePickerField(
            label: 'Date',
            isoDate: _date,
            onChanged: (v) => setState(() => _date = v)),
        EditorField(label: 'Stock code', controller: _stock),
        Row(children: [
          Expanded(
            child: EditorField(
                label: 'Shares',
                controller: _shares,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: EditorField(
                label: 'Rate / share',
                controller: _rate,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
          ),
        ]),
        EditorField(
            label: 'Net amount (${widget.currency})',
            controller: _net,
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        EditorField(label: 'Remarks', controller: _remarks, maxLines: 2),
      ],
    );
  }
}
