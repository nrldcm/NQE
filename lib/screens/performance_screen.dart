// Monthly Performance — a manually-maintained monthly summary of the fund
// (the manager tracks by month, not per-trade). Each row: start/end balance,
// wire-out and its own currency. Derived: P&L, % change, cumulative TWR (from
// inception), a "time period" cumulative that resets at a marked month, and
// drawdown. A year selector filters the table to one year; a comparison strip
// summarises each year. Data syncs with the phone like the rest of the ledger.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

const List<String> kPerfCurrencies = ['USD', 'EUR', 'PHP'];
const List<String> kMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

final _n2 = NumberFormat('#,##0.##');
String _money(double v, String cur) => money(v, currency: cur, decimals: 0);
String _pct(double v) =>
    '${v >= 0 ? '' : '-'}${NumberFormat('#,##0').format(v.abs())}%';

/// A month plus its derived cumulative columns.
class _Row {
  final PerfMonth m;
  final double twrPct; // cumulative TWR from inception
  final double periodPnl; // cumulative P&L since the last period marker
  final double periodTwrPct; // cumulative TWR since the last period marker
  _Row(this.m, this.twrPct, this.periodPnl, this.periodTwrPct);
}

class PerformanceScreen extends StatefulWidget {
  /// When true the screen is embedded as a tab body (no its own AppBar back
  /// button styling changes needed — it still shows a title bar).
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  int? _year; // selected year filter (null → default to latest)

  /// Compute every row's cumulative columns across the FULL ordered list (% is
  /// currency-independent, so the TWR compounding is valid regardless of the
  /// per-row currency); the caller then filters which year to display.
  List<_Row> _allRows() {
    var instFactor = 1.0;
    var periodFactor = 1.0;
    var periodPnl = 0.0;
    final out = <_Row>[];
    for (final m in appState.perfMonths) {
      if (m.periodStart) {
        periodFactor = 1.0;
        periodPnl = 0.0;
      }
      final r = 1 + m.pctChange / 100;
      instFactor *= r;
      periodFactor *= r;
      periodPnl += m.pnl;
      out.add(_Row(m, (instFactor - 1) * 100, periodPnl,
          (periodFactor - 1) * 100));
    }
    return out;
  }

  List<int> _availableYears() {
    final ys = appState.perfMonths.map((m) => m.sortKey ~/ 100).toSet();
    ys.add(DateTime.now().year);
    final list = ys.where((y) => y > 0).toList()..sort();
    return list;
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
          final years = _availableYears();
          final year = (_year != null && years.contains(_year))
              ? _year!
              : years.last;
          final all = _allRows();
          final rows =
              all.where((r) => r.m.sortKey ~/ 100 == year).toList();
          return Column(
            children: [
              _yearBar(pal, years, year),
              Divider(height: 1, color: pal.line),
              if (all.isNotEmpty) _yearSummary(pal, all),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: EmptyState(
                          icon: Icons.calendar_month_outlined,
                          title: 'No $year months yet',
                          subtitle: 'Add a month with its start & end balance',
                          action: FilledButton.icon(
                            onPressed: () => _edit(context, null),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add month'),
                          ),
                        ),
                      )
                    : _list(pal, rows),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _yearBar(NqePalette pal, List<int> years, int sel) {
    return Container(
      color: pal.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SizedBox(
        height: 34,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          }),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final y in years) ...[
                _yearChip(pal, y, y == sel),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _yearChip(NqePalette pal, int y, bool sel) => InkWell(
        onTap: () => setState(() => _year = y),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: sel ? pal.textHi.withOpacity(0.12) : pal.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: sel ? pal.textHi.withOpacity(0.4) : pal.line),
          ),
          child: Text('$y',
              style: TextStyle(
                  color: sel ? pal.textHi : pal.textLo,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ),
      );

  // ---- per-year comparison summary -----------------------------------------
  Widget _yearSummary(NqePalette pal, List<_Row> all) {
    final byYear = <int, List<_Row>>{};
    for (final r in all) {
      (byYear[r.m.sortKey ~/ 100] ??= []).add(r);
    }
    final years = byYear.keys.toList()..sort();
    final cards = <Widget>[];
    double? prevTwr;
    for (final y in years) {
      final rs = byYear[y]!;
      var f = 1.0;
      for (final r in rs) {
        f *= (1 + r.m.pctChange / 100);
      }
      final twr = (f - 1) * 100;
      // P&L + wire summed per currency (amounts can't cross currencies).
      final pnlByCur = <String, double>{};
      for (final r in rs) {
        pnlByCur[r.m.currency] =
            (pnlByCur[r.m.currency] ?? 0) + r.m.pnl;
      }
      cards.add(_yearCard(
          pal, y, twr, pnlByCur, prevTwr == null ? null : twr - prevTwr));
      prevTwr = twr;
    }
    return Container(
      color: pal.bg,
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
            child: Text('YEAR COMPARISON',
                style: TextStyle(
                    color: pal.textLo,
                    fontSize: 10.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            height: 130,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              children: [
                for (final c in cards)
                  Padding(
                      padding: const EdgeInsets.only(right: 10), child: c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _yearCard(NqePalette pal, int year, double twr,
      Map<String, double> pnlByCur, double? dTwr) {
    // Delta pill vs previous year (TWR — unitless, always comparable). Fixed
    // width and a "— —" placeholder keep every card exactly the same size.
    final Widget pill;
    if (dTwr == null) {
      pill = _pillBox(pal.textLo.withOpacity(0.12), '— —', pal.textLo);
    } else {
      pill = _pillBox(NqeColors.pnl(dTwr).withOpacity(0.16),
          '${dTwr >= 0 ? '▲' : '▼'} ${_pct(dTwr.abs())}', NqeColors.pnl(dTwr));
    }
    final curs = pnlByCur.keys.toList();
    return SizedBox(
      width: 182,
      height: 108,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$year',
                    style: TextStyle(
                        color: pal.textHi,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                pill,
              ],
            ),
            const SizedBox(height: 6),
            Text('TWR ${_pct(twr)}',
                style: TextStyle(
                    color: NqeColors.pnl(twr),
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            // P&L per currency (usually one line).
            for (final c in curs.take(2))
              Text('${_money(pnlByCur[c]!, c)} P&L',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: NqeColors.pnl(pnlByCur[c]!),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _pillBox(Color bg, String s, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(s,
            style:
                TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w800)),
      );

  // ---- the month cards ------------------------------------------------------
  // Each month is a self-contained card that shows every column stacked, so the
  // whole record is readable at a glance without a horizontal table swipe.
  Widget _list(NqePalette pal, List<_Row> rows) {
    // Totals per currency for the displayed year.
    final pnlByCur = <String, double>{};
    final wireByCur = <String, double>{};
    for (final r in rows) {
      pnlByCur[r.m.currency] = (pnlByCur[r.m.currency] ?? 0) + r.m.pnl;
      wireByCur[r.m.currency] = (wireByCur[r.m.currency] ?? 0) + r.m.wireOut;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        for (final r in rows) _monthCard(pal, r),
        const SizedBox(height: 2),
        for (final c in pnlByCur.keys)
          _totalCard(pal, c, pnlByCur[c]!, wireByCur[c] ?? 0),
      ],
    );
  }

  Widget _monthCard(NqePalette pal, _Row r) {
    final m = r.m;
    final cur = m.currency;
    final pnlC = NqeColors.pnl(m.pnl);
    final chgC = NqeColors.pnl(m.pctChange);
    final wire = m.wireOut;
    final ddPct = m.endBal == 0 ? 0.0 : -(wire) / m.endBal * 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _edit(context, m),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: m.periodStart
                      ? pal.textHi.withOpacity(0.35)
                      : pal.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(m.title.isEmpty ? '—' : m.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: pal.textHi,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: pal.surface2,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(currencySymbol(cur),
                        style: TextStyle(
                            color: pal.textLo,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                  const Spacer(),
                  _pillBox(
                      chgC.withOpacity(0.16),
                      '${m.pctChange >= 0 ? '▲' : '▼'} ${_pct(m.pctChange.abs())}',
                      chgC),
                ]),
                if (m.periodStart) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.flag_outlined,
                        size: 13, color: pal.textHi.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Text('New time period',
                        style: TextStyle(
                            color: pal.textHi.withOpacity(0.7),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                  ]),
                ],
                const SizedBox(height: 14),
                _statRow([
                  _stat(pal, 'Start', _money(m.startBal, cur), pal.textHi),
                  _stat(pal, 'End', _money(m.endBal, cur), pal.textHi),
                ]),
                const SizedBox(height: 14),
                _statRow([
                  _stat(pal, 'P&L', _money(m.pnl, cur), pnlC),
                  _stat(pal, 'TWR · inception', _pct(r.twrPct),
                      NqeColors.pnl(r.twrPct)),
                ]),
                const SizedBox(height: 14),
                _statRow([
                  _stat(pal, 'Period P&L', _money(r.periodPnl, cur),
                      NqeColors.pnl(r.periodPnl)),
                  _stat(pal, 'Period TWR', _pct(r.periodTwrPct),
                      NqeColors.pnl(r.periodTwrPct)),
                ]),
                const SizedBox(height: 14),
                _statRow([
                  _stat(pal, 'Wire out',
                      wire == 0 ? '—' : _money(wire, cur),
                      wire == 0 ? pal.textLo : pal.textHi),
                  _stat(pal, 'Drawdown', wire == 0 ? '—' : _pct(ddPct),
                      pal.textLo),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statRow(List<Widget> cells) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final c in cells) Expanded(child: c)],
      );

  Widget _stat(NqePalette pal, String label, String value, Color valueColor) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: pal.textLo,
                  fontSize: 11,
                  letterSpacing: 0.2,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ],
      );

  Widget _totalCard(NqePalette pal, String cur, double pnl, double wire) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: pal.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.line),
          ),
          child: Row(children: [
            Text('Total ($cur)',
                style: TextStyle(
                    color: pal.textHi,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_money(pnl, cur),
                  style: TextStyle(
                      color: NqeColors.pnl(pnl),
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('Wire ${_money(wire, cur)}',
                  style: TextStyle(
                      color: pal.textLo,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      );

  Future<void> _edit(BuildContext context, PerfMonth? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PerfEditor(
          existing: existing, defaultYear: _year ?? DateTime.now().year),
    );
  }
}

class _PerfEditor extends StatefulWidget {
  final PerfMonth? existing;
  final int defaultYear;
  const _PerfEditor({this.existing, required this.defaultYear});

  @override
  State<_PerfEditor> createState() => _PerfEditorState();
}

class _PerfEditorState extends State<_PerfEditor> {
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _wire;
  late int _year;
  late int _monthIdx;
  late String _cur;
  late bool _periodStart;

  List<int> get _years {
    final now = DateTime.now().year;
    final set = <int>{for (var y = 2025; y <= now; y++) y, _year};
    return set.toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _start = TextEditingController(text: e == null ? '' : _n2.format(e.startBal));
    _end = TextEditingController(text: e == null ? '' : _n2.format(e.endBal));
    _wire = TextEditingController(
        text: (e == null || e.wireOut == 0) ? '' : _n2.format(e.wireOut));
    _cur = e?.currency ?? 'USD';
    _periodStart = e?.periodStart ?? false;
    final now = DateTime.now();
    if (e != null && e.sortKey >= 100) {
      _year = e.sortKey ~/ 100;
      _monthIdx = ((e.sortKey % 100) - 1).clamp(0, 11);
    } else {
      _year = widget.defaultYear;
      _monthIdx = now.month - 1;
    }
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _wire.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  Future<void> _save() async {
    final e = widget.existing;
    final m = PerfMonth(
      id: e?.id ?? uid(),
      title: '${kMonths[_monthIdx]} $_year',
      currency: _cur,
      sortKey: _year * 100 + (_monthIdx + 1),
      startBal: _num(_start),
      endBal: _num(_end),
      wireOut: _num(_wire),
      periodStart: _periodStart,
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
        child: SingleChildScrollView(
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
                      color: pal.line, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  Text(widget.existing == null ? 'Add month' : 'Edit month',
                      style: TextStyle(
                          color: pal.textHi,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  for (final c in kPerfCurrencies)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: InkWell(
                        onTap: () => setState(() => _cur = c),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: c == _cur
                                ? pal.textHi.withOpacity(0.12)
                                : pal.surface2,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: c == _cur
                                    ? pal.textHi.withOpacity(0.4)
                                    : pal.line),
                          ),
                          child: Text(currencySymbol(c),
                              style: TextStyle(
                                  color: c == _cur ? pal.textHi : pal.textLo,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    value: _monthIdx,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Month', isDense: true),
                    items: [
                      for (var i = 0; i < kMonths.length; i++)
                        DropdownMenuItem(value: i, child: Text(kMonths[i])),
                    ],
                    onChanged: (v) => setState(() => _monthIdx = v ?? _monthIdx),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    value: _year,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Year', isDense: true),
                    items: [
                      for (final y in _years)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (v) => setState(() => _year = v ?? _year),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _numField(_start, 'Start balance')),
                const SizedBox(width: 12),
                Expanded(child: _numField(_end, 'End balance')),
              ]),
              const SizedBox(height: 12),
              _numField(_wire, 'Wire out  (+ withdrawal, − deposit)'),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _periodStart,
                onChanged: (v) => setState(() => _periodStart = v),
                title: Text('Start a new time period here',
                    style: TextStyle(color: pal.textHi, fontSize: 14)),
                subtitle: Text('Period P&L / TWR reset from this month',
                    style: TextStyle(color: pal.textLo, fontSize: 12)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                if (widget.existing != null)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style:
                        TextButton.styleFrom(foregroundColor: NqeColors.loss),
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ]),
            ],
          ),
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
