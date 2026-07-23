// Create / edit a trade journal entry, with live P&L preview.
import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../format.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../util.dart';
import 'editor_scaffold.dart';

Future<bool> showTradeEditor(
  BuildContext context, {
  required String accountId,
  String currency = 'PHP',
  Trade? existing,
}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TradeEditor(
        accountId: accountId, currency: currency, existing: existing),
  );
  return res ?? false;
}

class _TradeEditor extends StatefulWidget {
  final String accountId;
  final String currency;
  final Trade? existing;
  const _TradeEditor(
      {required this.accountId, required this.currency, this.existing});

  @override
  State<_TradeEditor> createState() => _TradeEditorState();
}

class _TradeEditorState extends State<_TradeEditor> {
  late final TextEditingController _stock;
  late final TextEditingController _shares;
  late final TextEditingController _buy;
  late final TextEditingController _sell;
  late final TextEditingController _fees;
  late final TextEditingController _holding;
  late final TextEditingController _setup;
  late final TextEditingController _remarks;
  String _date = todayIso();
  bool _closed = true;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _stock = TextEditingController(text: t?.stock ?? '');
    _shares = TextEditingController(text: t == null ? '' : _n(t.shares));
    _buy = TextEditingController(text: t == null ? '' : _n(t.buyPrice));
    _sell = TextEditingController(
        text: t?.sellPrice == null ? '' : _n(t!.sellPrice!));
    _fees = TextEditingController(text: t == null ? '' : _n(t.fees));
    _holding = TextEditingController(text: t?.holdingPeriod ?? '');
    _setup = TextEditingController(text: t?.setup ?? '');
    _remarks = TextEditingController(text: t?.remarks ?? '');
    _date = t?.date ?? todayIso();
    _closed = t == null ? true : !t.isOpen;
    for (final c in [_shares, _buy, _sell, _fees]) {
      c.addListener(() => setState(() {}));
    }
  }

  String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double get _pnlPreview {
    final sh = double.tryParse(_shares.text) ?? 0;
    final b = double.tryParse(_buy.text) ?? 0;
    final s = double.tryParse(_sell.text) ?? 0;
    final f = double.tryParse(_fees.text) ?? 0;
    if (!_closed || _sell.text.trim().isEmpty) return 0;
    return (s - b) * sh - f;
  }

  @override
  void dispose() {
    for (final c in [
      _stock, _shares, _buy, _sell, _fees, _holding, _setup, _remarks
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final stock = _stock.text.trim();
    if (stock.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Stock code is required')));
      return;
    }
    final t = widget.existing ??
        Trade(
            id: uid(),
            accountId: widget.accountId,
            date: _date,
            createdAt: nowIso());
    t.date = _date;
    t.stock = stock.toUpperCase();
    t.shares = double.tryParse(_shares.text.trim()) ?? 0;
    t.buyPrice = double.tryParse(_buy.text.trim()) ?? 0;
    t.sellPrice =
        _closed && _sell.text.trim().isNotEmpty ? double.tryParse(_sell.text.trim()) : null;
    t.fees = double.tryParse(_fees.text.trim()) ?? 0;
    t.holdingPeriod = _holding.text.trim();
    t.setup = _setup.text.trim();
    t.remarks = _remarks.text.trim();
    t.status = (_closed && t.sellPrice != null) ? 'closed' : 'open';
    await LedgerDb.instance.upsertTrade(t);
    await appState.load();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final t = widget.existing;
    if (t == null) return;
    final ok = await confirmDelete(
        context, 'Delete trade?', '${t.stock} entry will be removed.');
    if (!ok) return;
    await LedgerDb.instance.deleteTrade(t.id);
    await appState.load();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final pnl = _pnlPreview;
    return EditorScaffold(
      title: widget.existing == null ? 'New trade' : 'Edit trade',
      onSave: _save,
      onDelete: widget.existing == null ? null : _delete,
      children: [
        DatePickerField(
            label: 'Date',
            isoDate: _date,
            onChanged: (v) => setState(() => _date = v)),
        EditorSymbolField(label: 'Stock code', controller: _stock),
        EditorField(
            label: 'Shares / Qty',
            controller: _shares,
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        Row(children: [
          Expanded(
            child: EditorField(
                label: 'Buy price',
                controller: _buy,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: EditorField(
                label: 'Sell price',
                controller: _sell,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
          ),
        ]),
        Row(children: [
          Expanded(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Position closed',
                  style: TextStyle(color: pal.textHi, fontSize: 14)),
              value: _closed,
              onChanged: (v) => setState(() => _closed = v),
            ),
          ),
        ]),
        EditorField(
            label: 'Fees',
            controller: _fees,
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        if (_closed && _sell.text.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NqeColors.pnl(pnl).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NqeColors.pnl(pnl).withOpacity(0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Profit / Loss',
                    style: TextStyle(color: pal.textLo, fontSize: 13)),
                Text(signedMoney(pnl, currency: widget.currency),
                    style: TextStyle(
                        color: NqeColors.pnl(pnl),
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        EditorField(label: 'Holding period', controller: _holding),
        EditorField(label: 'Setup', controller: _setup),
        EditorField(label: 'Remarks / lessons', controller: _remarks, maxLines: 3),
      ],
    );
  }
}
