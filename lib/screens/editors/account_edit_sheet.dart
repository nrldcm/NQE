// Create / edit an account ("book"). Returns true if anything was saved.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../db/database.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../util.dart';
import 'editor_scaffold.dart';

const List<int> kAccountColors = [
  0xFF111111,
  0xFF1F6FEB,
  0xFF2EA043,
  0xFFE3B341,
  0xFFDB61A2,
  0xFFF0883E,
  0xFF8957E5,
  0xFF39C5CF,
];

Future<bool> showAccountEditor(BuildContext context, {Account? existing}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AccountEditor(existing: existing),
  );
  return res ?? false;
}

class _AccountEditor extends StatefulWidget {
  final Account? existing;
  const _AccountEditor({this.existing});

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  late final TextEditingController _name;
  late final TextEditingController _broker;
  late final TextEditingController _capital;
  late final TextEditingController _fx;
  String _currency = 'PHP';
  AccountKind _kind = AccountKind.trading;
  int _color = kAccountColors.first;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _name = TextEditingController(text: a?.name ?? '');
    _broker = TextEditingController(text: a?.broker ?? '');
    _capital = TextEditingController(
        text: a == null ? '' : _trim(a.startingCapital));
    _fx = TextEditingController(text: a == null ? '1' : _trim(a.fxToPhp));
    _currency = a?.currency ?? 'PHP';
    _kind = a?.kind ?? AccountKind.trading;
    _color = a?.color ?? kAccountColors.first;
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _name.dispose();
    _broker.dispose();
    _capital.dispose();
    _fx.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account name is required')));
      return;
    }
    final a = widget.existing ??
        Account(id: uid(), name: name, createdAt: nowIso());
    a.name = name;
    a.broker = _broker.text.trim();
    a.currency = _currency;
    a.kind = _kind;
    a.startingCapital = double.tryParse(_capital.text.trim()) ?? 0;
    a.fxToPhp = _currency == 'PHP'
        ? 1
        : (double.tryParse(_fx.text.trim()) ?? 1);
    a.color = _color;
    if (widget.existing == null) {
      a.sortOrder = appState.accounts.length;
    }
    await LedgerDb.instance.upsertAccount(a);
    await appState.load();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final a = widget.existing;
    if (a == null) return;
    final ok = await confirmDelete(context,
        'Delete "${a.name}"?', 'All its trades, cashflows and dividends will be removed.');
    if (!ok) return;
    await LedgerDb.instance.deleteAccount(a.id);
    await appState.load();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return EditorScaffold(
      title: widget.existing == null ? 'New book' : 'Edit book',
      onSave: _save,
      onDelete: widget.existing == null ? null : _delete,
      children: [
        EditorField(label: 'Name', controller: _name),
        EditorField(label: 'Broker', controller: _broker),
        const SizedBox(height: 4),
        Text('Type', style: TextStyle(color: pal.textLo, fontSize: 13)),
        const SizedBox(height: 8),
        SegmentedButton<AccountKind>(
          segments: const [
            ButtonSegment(
                value: AccountKind.trading,
                label: Text('Trading'),
                icon: Icon(Icons.candlestick_chart)),
            ButtonSegment(
                value: AccountKind.dividend,
                label: Text('Dividend'),
                icon: Icon(Icons.savings)),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: EditorDropdown<String>(
                label: 'Currency',
                value: _currency,
                items: const ['PHP', 'EUR', 'USD', 'GBP'],
                onChanged: (v) => setState(() => _currency = v ?? 'PHP'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: EditorField(
                label: 'Starting capital',
                controller: _capital,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
        if (_currency != 'PHP') ...[
          const SizedBox(height: 12),
          EditorField(
            label: 'FX rate → PHP (1 $_currency = ? PHP)',
            controller: _fx,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
        const SizedBox(height: 16),
        Text('Colour', style: TextStyle(color: pal.textLo, fontSize: 13)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: kAccountColors.map((c) {
            final sel = c == _color;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _color = c);
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: sel ? pal.textHi : pal.line,
                    width: sel ? 3 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
