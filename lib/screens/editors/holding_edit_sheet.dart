// Create / edit a portfolio holding / goal-share target (dividend books).
import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../util.dart';
import 'editor_scaffold.dart';

Future<bool> showHoldingEditor(
  BuildContext context, {
  required String accountId,
  Holding? existing,
}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _HoldingEditor(accountId: accountId, existing: existing),
  );
  return res ?? false;
}

class _HoldingEditor extends StatefulWidget {
  final String accountId;
  final Holding? existing;
  const _HoldingEditor({required this.accountId, this.existing});

  @override
  State<_HoldingEditor> createState() => _HoldingEditorState();
}

class _HoldingEditorState extends State<_HoldingEditor> {
  late final TextEditingController _stock;
  late final TextEditingController _goal;
  late final TextEditingController _current;
  late final TextEditingController _avg;

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    _stock = TextEditingController(text: h?.stock ?? '');
    _goal = TextEditingController(text: h == null ? '' : _n(h.goalShares));
    _current = TextEditingController(text: h == null ? '' : _n(h.currentShares));
    _avg = TextEditingController(text: h == null ? '' : _n(h.avgPrice));
  }

  String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _stock.dispose();
    _goal.dispose();
    _current.dispose();
    _avg.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final h = widget.existing ??
        Holding(id: uid(), accountId: widget.accountId, createdAt: nowIso());
    h.stock = _stock.text.trim().toUpperCase();
    h.goalShares = double.tryParse(_goal.text.trim()) ?? 0;
    h.currentShares = double.tryParse(_current.text.trim()) ?? 0;
    h.avgPrice = double.tryParse(_avg.text.trim()) ?? 0;
    await LedgerDb.instance.upsertHolding(h);
    await appState.load();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final h = widget.existing;
    if (h == null) return;
    final ok = await confirmDelete(
        context, 'Delete holding?', 'This target will be removed.');
    if (!ok) return;
    await LedgerDb.instance.deleteHolding(h.id);
    await appState.load();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return EditorScaffold(
      title: widget.existing == null ? 'New holding' : 'Edit holding',
      onSave: _save,
      onDelete: widget.existing == null ? null : _delete,
      children: [
        EditorField(label: 'Stock code', controller: _stock),
        Row(children: [
          Expanded(
            child: EditorField(
                label: 'Goal shares',
                controller: _goal,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: EditorField(
                label: 'Current shares',
                controller: _current,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
          ),
        ]),
        EditorField(
            label: 'Average price',
            controller: _avg,
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      ],
    );
  }
}
