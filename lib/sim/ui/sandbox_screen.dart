// Simulation Trading (Sandbox) — the trading workspace. Real-time, isolated
// paper trading across PSE stocks, Forex and Crypto with Spot + Margin.
//
// Layout is fully responsive: a phone gets a summary header + tabbed sections
// (Trade / Positions / History / Markets); a wide desktop gets a three-column
// terminal (markets · chart+book · order ticket). Everything streams live from
// [simState]; in-app notifications flash as they arrive.
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../sim_models.dart';
import '../sim_market.dart';
import '../sim_state.dart';
import 'sandbox_analytics_panel.dart';
import 'sandbox_candle_chart.dart';
import 'sandbox_common.dart';
import 'sandbox_market_panel.dart';
import 'sandbox_notices.dart';
import 'sandbox_positions_panel.dart';
import 'sandbox_trade_ticket.dart';

class SandboxScreen extends StatefulWidget {
  const SandboxScreen({super.key});

  @override
  State<SandboxScreen> createState() => _SandboxScreenState();
}

class _SandboxScreenState extends State<SandboxScreen>
    with SingleTickerProviderStateMixin {
  String _symbol = 'BTCUSDT';
  SimNotice? _shownNotice;
  TabController? _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    simState.init();
    // Subscribe the whole catalogue once, off-build (batched, single notify),
    // so market rows show live quotes without ever subscribing during build.
    simState.price.subscribeAll(kInstruments.map((e) => e.symbol));
    simState.price.subscribe(_symbol);
    // Seed so a notice that fired while we were away isn't re-flashed on mount.
    _shownNotice = simState.lastNotice;
    simState.addListener(_onTick);
  }

  @override
  void dispose() {
    simState.removeListener(_onTick);
    _tabs?.dispose();
    super.dispose();
  }

  void _onTick() {
    // The candle chart advances itself from simState on each tick; here we only
    // surface any new trade notification. No setState — the top-level
    // ListenableBuilder(simState) already rebuilds this screen on the same
    // notification. One rebuild per tick.
    _maybeFlashNotice();
  }

  void _maybeFlashNotice() {
    final n = simState.lastNotice;
    if (n == null || identical(n, _shownNotice)) return;
    _shownNotice = n;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 2200),
        backgroundColor: noticeColor(n.type),
        content: Row(
          children: [
            Icon(noticeIcon(n.type), color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                  Text(n.message,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ));
    });
  }

  void _select(String symbol) {
    if (symbol == _symbol) return;
    simState.price.subscribe(symbol);
    setState(() => _symbol = symbol);
  }

  SimMarket get _market =>
      instrumentFor(_symbol)?.market ?? SimMarket.crypto;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: simState,
      builder: (context, _) {
        if (simState.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 1000
              ? _desktop(context)
              : _mobile(context),
        );
      },
    );
  }

  // ---- mobile --------------------------------------------------------------

  Widget _mobile(BuildContext context) {
    final pal = context.nqe;
    return Column(
      children: [
        _Header(onSelect: _select),
        Material(
          color: pal.bg,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: pal.textHi,
            unselectedLabelColor: pal.textLo,
            indicatorColor: pal.textHi,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: const [
              Tab(text: 'Trade'),
              Tab(text: 'Positions'),
              Tab(text: 'History'),
              Tab(text: 'Markets'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _tradeTab(context),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SandboxPositionsPanel(),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SandboxAnalyticsPanel(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SandboxMarketPanel(
                  selected: _symbol,
                  onSelect: (s) {
                    _select(s);
                    _tabs?.animateTo(0);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tradeTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SymbolBar(symbol: _symbol, market: _market),
        const SizedBox(height: 10),
        SimCard(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: SandboxCandleChart(
              symbol: _symbol, market: _market, height: 220),
        ),
        const SizedBox(height: 12),
        SandboxTradeTicket(symbol: _symbol),
      ],
    );
  }

  // ---- desktop -------------------------------------------------------------

  Widget _desktop(BuildContext context) {
    final pal = context.nqe;
    return Column(
      children: [
        _Header(onSelect: _select),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left — markets
              SizedBox(
                width: 320,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
                  child: SandboxMarketPanel(
                      selected: _symbol, onSelect: _select, compact: true),
                ),
              ),
              VerticalDivider(width: 1, color: pal.line),
              // Center — chart + book
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SymbolBar(symbol: _symbol, market: _market),
                      const SizedBox(height: 12),
                      SimCard(
                        padding: const EdgeInsets.fromLTRB(10, 12, 12, 8),
                        child: SandboxCandleChart(
                            symbol: _symbol, market: _market, height: 300),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SandboxPositionsPanel(onSelect: _select),
                      ),
                    ],
                  ),
                ),
              ),
              VerticalDivider(width: 1, color: pal.line),
              // Right — order ticket + analytics
              SizedBox(
                width: 340,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
                  child: Column(
                    children: [
                      SandboxTradeTicket(symbol: _symbol),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 520,
                        child: SandboxAnalyticsPanel(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Top summary + controls (feed toggle, reset, notifications).
class _Header extends StatelessWidget {
  final ValueChanged<String> onSelect;
  const _Header({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final equity = simState.equity;
    final unreal = simState.unrealized;
    final cash = simState.freeCash;
    final cur = simState.currency;
    final live = simState.price.mode == FeedMode.live;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border(bottom: BorderSide(color: pal.line)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, size: 20, color: pal.textHi),
              const SizedBox(width: 8),
              Text('Sandbox',
                  style: TextStyle(
                      color: pal.textHi,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: pal.textHi.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('PAPER',
                    style: TextStyle(
                        color: pal.textLo,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
              const Spacer(),
              // Feed toggle
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => simState
                    .setFeedMode(live ? FeedMode.simulated : FeedMode.live),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (live ? NqeColors.gain : pal.textLo)
                        .withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: live ? NqeColors.gain : pal.textLo,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(live ? 'Live' : 'Simulated',
                          style: TextStyle(
                              color: live ? NqeColors.gain : pal.textLo,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SandboxNoticesButton(),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: pal.textHi),
                onSelected: (v) {
                  if (v == 'reset') _confirmReset(context);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'reset',
                    child: Row(
                      children: [
                        Icon(Icons.restart_alt, size: 18),
                        SizedBox(width: 10),
                        Text('Reset account'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _metric(context, 'Equity', simMoney(equity, currency: cur),
                  pal.textHi),
              _metric(context, 'Unrealized P/L',
                  simSignedMoney(unreal, currency: cur), NqeColors.pnl(unreal)),
              _metric(context, 'Free cash', simMoney(cash, currency: cur),
                  pal.textHi),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value, Color c) {
    final pal = context.nqe;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: pal.textLo, fontSize: 10, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    color: c, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset sandbox?'),
        content: const Text(
            'This closes all positions and orders and restores your virtual '
            'balance to the starting cash. Trade history is kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) simState.resetAccount();
  }
}

/// Selected instrument summary bar: name, live price and % change.
class _SymbolBar extends StatelessWidget {
  final String symbol;
  final SimMarket market;
  const _SymbolBar({required this.symbol, required this.market});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final q = simState.price.quote(symbol);
    final price = q?.price ?? seedPriceFor(symbol);
    final chg = q?.changePct ?? 0;
    final inst = instrumentFor(symbol);
    return Row(
      children: [
        MarketBadge(market),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(symbol,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: pal.textHi,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              if (inst != null)
                Text(inst.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: pal.textLo, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FlashPrice(
              price: price,
              market: market,
              tag: symbol,
              style: TextStyle(
                  color: pal.textHi,
                  fontSize: 20,
                  fontWeight: FontWeight.w800),
            ),
            Text(signedPctStr(chg),
                style: TextStyle(
                    color: NqeColors.pnl(chg),
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}
