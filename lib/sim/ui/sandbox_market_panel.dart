// Browse & search instruments across PSE stocks, Forex and Crypto with live
// simulated/real quotes. Tap a row to select it for the trade ticket; star it
// to add to the watchlist.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../sim_market.dart';
import '../sim_models.dart';
import '../sim_state.dart';
import 'sandbox_common.dart';

class SandboxMarketPanel extends StatefulWidget {
  final String? selected;
  final ValueChanged<String> onSelect;

  /// Compact mode hides the big header (used inside the desktop left column).
  final bool compact;
  const SandboxMarketPanel({
    super.key,
    required this.onSelect,
    this.selected,
    this.compact = false,
  });

  @override
  State<SandboxMarketPanel> createState() => _SandboxMarketPanelState();
}

class _SandboxMarketPanelState extends State<SandboxMarketPanel> {
  final _searchCtrl = TextEditingController();
  SimMarket? _filter; // null = all
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SimSymbol> get _results =>
      searchInstruments(_query, market: _filter, limit: 100).toList();

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final results = _results;
    // NB: symbols are subscribed once by SandboxScreen (off-build) — never
    // subscribe here, since PriceEngine.subscribe notifies synchronously and
    // would trigger setState-during-build.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search symbol or name…',
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          // Allow click-and-drag (mouse/trackpad) to scroll the pills on
          // desktop — a plain horizontal ListView otherwise only scrolls by
          // wheel there, hiding the later filters (Indices / Commodities).
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
              scrollbars: false,
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chip('All', _filter == null,
                    () => setState(() => _filter = null)),
                for (final m in SimMarket.values)
                  _chip(marketLabel(m), _filter == m,
                      () => setState(() => _filter = m),
                      color: marketColor(m)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListenableBuilder(
            // simState notifies on every price tick AND on watch changes, so
            // both live quotes and the star toggle repaint immediately.
            listenable: simState,
            builder: (context, _) {
              if (results.isEmpty) {
                return Center(
                  child: Text('No instruments match “$_query”.',
                      style: TextStyle(color: pal.textLo, fontSize: 13)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                itemCount: results.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: pal.line.withOpacity(0.6)),
                itemBuilder: (context, i) =>
                    _row(context, results[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, SimSymbol s) {
    final pal = context.nqe;
    final q = simState.price.quote(s.symbol);
    final price = q?.price ?? seedPriceFor(s.symbol);
    final chg = q?.changePct ?? 0;
    final selected = widget.selected == s.symbol;
    final watched = simState.watch.any((w) => w.symbol == s.symbol);

    return InkWell(
      onTap: () => widget.onSelect(s.symbol),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? pal.textHi.withOpacity(0.06) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            MarketBadge(s.market, dense: true),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.symbol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: pal.textHi,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: pal.textLo, fontSize: 11)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FlashPrice(
                  price: price,
                  market: s.market,
                  tag: s.symbol,
                  style: TextStyle(
                      color: pal.textHi,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
                Text(signedPctStr(chg),
                    style: TextStyle(
                        color: NqeColors.pnl(chg),
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(watched ? Icons.star : Icons.star_border,
                  size: 18, color: watched ? const Color(0xFFF3B23B) : pal.textLo),
              onPressed: () {
                if (watched) {
                  final w = simState.watch.firstWhere((w) => w.symbol == s.symbol);
                  simState.removeWatch(w.id);
                } else {
                  simState.addWatch(s.symbol, s.market);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap, {Color? color}) {
    final pal = context.nqe;
    final c = color ?? pal.textHi;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? c.withOpacity(0.14) : pal.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? c.withOpacity(0.5) : pal.line),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? c : pal.textLo,
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
        ),
      ),
    );
  }
}
