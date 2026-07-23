// Monthly Performance tracker — a manually-maintained table of each month's
// start/end balance and wire-out, with P&L, % change, cumulative TWR and
// drawdown all derived. Mirrors the fund's monthly P&L spreadsheet. Data syncs
// with the phone like the rest of the ledger.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

final _n0 = NumberFormat('#,##0');
final _n2 = NumberFormat('#,##0.##');

String _money(double v) => '\$${_n0.format(v)}';
String _pct(double v) => '${v >= 0 ? '' : '-'}${_n0.format(v.abs())}%';

/// One computed table row (a stored month plus its derived cumulative TWR).
class _Row {
  final PerfMonth m;
  final double twrPct; // cumulative time-weighted return through this month
  _Row(this.m, this.twrPct);
}

class PerformanceScreen extends StatelessWidget {
  const PerformanceScreen({super.key});

  List<_Row> _rows() {
    var factor = 1.0;
    final out = <_Row>[];
    for (final m in appState.perfMonths) {
      factor *= (1 + m.pctChange / 100);
      out.add(_Row(m, (factor - 1) * 100));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        title: const Text('Monthly Performance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add month',
            onPressed: () => _edit(context, null),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final rows = _rows();
          if (rows.isEmpty) {
            return Center(
              child: EmptyState(
                icon: Icons.calendar_month_outlined,
                title: 'No months yet',
                subtitle: 'Add a month with its start & end balance',
                action: FilledButton.icon(
                  onPressed: () => _edit(context, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add month'),
                ),
              ),
            );
          }
          final totalPnl = rows.fold<double>(0, (s, r) => s + r.m.pnl);
          final totalWire = rows.fold<double>(0, (s, r) => s + r.m.wireOut);
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _headerRow(pal),
                  for (final r in rows)
                    InkWell(
                      onTap: () => _edit(context, r.m),
                      child: _dataRow(pal, r),
                    ),
                  _totalsRow(pal, totalPnl, totalWire),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- column widths --------------------------------------------------------
  static const _wMonth = 132.0;
  static const _wBal = 112.0;
  static const _wPnl = 104.0;
  static const _wPct = 72.0;
  static const _wTwr = 92.0;
  static const _wWire = 112.0;
  static const _wDd = 66.0;

  Widget _cell(double w, Widget child,
          {Color? bg, Alignment align = Alignment.centerRight}) =>
      Container(
        width: w,
        height: 40,
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: bg),
        child: child,
      );

  Widget _txt(String s, Color c, {FontWeight w = FontWeight.w600}) =>
      Text(s,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c, fontSize: 12.5, fontWeight: w));

  Widget _headerRow(NqePalette pal) {
    Widget h(double w, String s, {Alignment a = Alignment.centerRight}) =>
        _cell(w, _txt(s, pal.textLo, w: FontWeight.w700), align: a);
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border(bottom: BorderSide(color: pal.line)),
      ),
      child: Row(children: [
        h(_wMonth, 'Month', a: Alignment.centerLeft),
        h(_wBal, 'Start'),
        h(_wBal, 'End'),
        h(_wPnl, 'P&L'),
        h(_wPct, '% chg'),
        h(_wTwr, 'TWR'),
        h(_wWire, 'Wire out'),
        h(_wDd, 'DD'),
      ]),
    );
  }

  Widget _dataRow(NqePalette pal, _Row r) {
    final m = r.m;
    final pnlC = m.pnl >= 0 ? NqeColors.gain : NqeColors.loss;
    // Wire-out cell tint: yellow for a withdrawal (money out), green for a
    // deposit (money in) — matching the reference sheet.
    final wire = m.wireOut;
    final wireBg = wire == 0
        ? null
        : (wire > 0
            ? const Color(0xFFFFE24D).withOpacity(0.30)
            : NqeColors.gain.withOpacity(0.20));
    final ddPct = m.endBal == 0 ? 0.0 : -(wire) / m.endBal * 100;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.line.withOpacity(0.5))),
      ),
      child: Row(children: [
        _cell(_wMonth, _txt(m.title.isEmpty ? '—' : m.title, pal.textHi),
            align: Alignment.centerLeft),
        _cell(_wBal, _txt(_money(m.startBal), pal.textHi)),
        _cell(_wBal, _txt(_money(m.endBal), pal.textHi)),
        _cell(_wPnl, _txt(_money(m.pnl), pnlC, w: FontWeight.w700)),
        _cell(_wPct, _txt(_pct(m.pctChange), pnlC)),
        _cell(_wTwr, _txt(_pct(r.twrPct), pal.textLo)),
        _cell(_wWire, _txt(wire == 0 ? '—' : _money(wire), pal.textHi),
            bg: wireBg),
        _cell(_wDd, _txt(wire == 0 ? '—' : _pct(ddPct), pal.textLo)),
      ]),
    );
  }

  Widget _totalsRow(NqePalette pal, double pnl, double wire) {
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border(top: BorderSide(color: pal.line, width: 1.5)),
      ),
      child: Row(children: [
        _cell(_wMonth, _txt('Total', pal.textHi, w: FontWeight.w800),
            align: Alignment.centerLeft),
        _cell(_wBal, const SizedBox()),
        _cell(_wBal, const SizedBox()),
        _cell(_wPnl,
            _txt(_money(pnl), NqeColors.pnl(pnl), w: FontWeight.w800)),
        _cell(_wPct, const SizedBox()),
        _cell(_wTwr, const SizedBox()),
        _cell(_wWire, _txt(_money(wire), pal.textHi, w: FontWeight.w800)),
        _cell(_wDd, const SizedBox()),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, PerfMonth? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PerfEditor(existing: existing),
    );
  }
}

class _PerfEditor extends StatefulWidget {
  final PerfMonth? existing;
  const _PerfEditor({this.existing});

  @override
  State<_PerfEditor> createState() => _PerfEditorState();
}

class _PerfEditorState extends State<_PerfEditor> {
  late final TextEditingController _title;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _wire;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _start = TextEditingController(text: e == null ? '' : _n2.format(e.startBal));
    _end = TextEditingController(text: e == null ? '' : _n2.format(e.endBal));
    _wire = TextEditingController(
        text: (e == null || e.wireOut == 0) ? '' : _n2.format(e.wireOut));
  }

  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _end.dispose();
    _wire.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a month label.')));
      return;
    }
    final e = widget.existing;
    final m = PerfMonth(
      id: e?.id ?? uid(),
      title: title,
      sortKey: e?.sortKey ?? appState.perfMonths.length,
      startBal: _num(_start),
      endBal: _num(_end),
      wireOut: _num(_wire),
      createdAt: e?.createdAt ?? nowIso(),
    );
    await appState.savePerfMonth(m);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    await appState.deletePerfMonth(e.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: pal.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: pal.line,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(widget.existing == null ? 'Add month' : 'Edit month',
                style: TextStyle(
                    color: pal.textHi,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Month (e.g. January 2025)', isDense: true),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _numField(_start, 'Start balance')),
              const SizedBox(width: 12),
              Expanded(child: _numField(_end, 'End balance')),
            ]),
            const SizedBox(height: 12),
            _numField(_wire, 'Wire out  (+ withdrawal, − deposit)'),
            const SizedBox(height: 20),
            Row(children: [
              if (widget.existing != null)
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: NqeColors.loss),
                ),
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]')),
        ],
        decoration: InputDecoration(labelText: label, isDense: true),
      );
}
