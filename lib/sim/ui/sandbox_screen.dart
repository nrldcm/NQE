// Simulation Trading (Sandbox) — the trading workspace. Real-time, isolated
// paper trading across PSE stocks, Forex and Crypto with Spot + Margin.
//
// Layout is fully responsive: a phone gets a summary header + tabbed sections
// (Trade / Positions / History / Markets); a wide desktop gets a three-column
// terminal (markets · chart+book · order ticket). Everything streams live from
// [simState]; in-app notifications flash as they arrive.
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/common.dart';
import '../sim_models.dart';
import '../sim_market.dart';
import '../sim_state.dart';
import 'sandbox_analytics_panel.dart';
import 'sandbox_chart_pane.dart';
import 'sandbox_common.dart';
import 'sandbox_market_panel.dart';
import 'sandbox_notices.dart';
import 'sandbox_positions_panel.dart';
import 'sandbox_trade_ticket.dart';
import 'sandbox_wallet_panel.dart';

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
    _tabs = TabController(length: 5, vsync: this);
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
              Tab(text: 'Wallet'),
              Tab(text: 'Positions'),
              Tab(text: 'Books'),
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
                child: SandboxWalletPanel(),
              ),
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
          child: SandboxChartPane(
              symbol: _symbol, market: _market, height: 240),
        ),
        const SizedBox(height: 12),
        SandboxTradeTicket(symbol: _symbol),
      ],
    );
  }

  // ---- desktop -------------------------------------------------------------

  // The desktop mirrors mobile's 5 tabs (Trade / Wallet / Positions / Books /
  // Markets) but each uses a wide, desktop-appropriate layout. Trade is the
  // main terminal (markets · chart · ticket) with the performance Overview
  // pinned as the top section of the workspace.
  Widget _desktop(BuildContext context) {
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
              Tab(text: 'Wallet'),
              Tab(text: 'Positions'),
              Tab(text: 'Books'),
              Tab(text: 'Markets'),
            ],
          ),
        ),
        Divider(height: 1, color: pal.line),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _desktopTradeTab(context),
              // Wallet — constrained + centred; a full-width wallet card reads
              // awkwardly stretched on a wide screen.
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SandboxWalletPanel(),
                  ),
                ),
              ),
              // Positions — full width.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SandboxPositionsPanel(onSelect: _select),
              ),
              // Books — the analytics + trade blotter, constrained + centred.
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SandboxAnalyticsPanel(),
                  ),
                ),
              ),
              // Markets — full width; selecting jumps to the Trade tab.
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

  // Trade tab — the wide three-column terminal: markets list · (Overview +
  // chart) · order ticket. The Overview strip is the top section of the centre
  // workspace, above the symbol bar and chart.
  Widget _desktopTradeTab(BuildContext context) {
    final pal = context.nqe;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left — markets
        SizedBox(
          width: 320,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
            child: SandboxMarketPanel(
                selected: _symbol, onSelect: _select, compact: true),
          ),
        ),
        VerticalDivider(width: 1, color: pal.line),
        // Center — Overview (top section) + symbol bar + chart
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _OverviewStrip(),
                const SizedBox(height: 14),
                _SymbolBar(symbol: _symbol, market: _market),
                const SizedBox(height: 12),
                SimCard(
                  padding: const EdgeInsets.fromLTRB(10, 12, 12, 8),
                  child: SandboxChartPane(
                      symbol: _symbol, market: _market, height: 360),
                ),
              ],
            ),
          ),
        ),
        VerticalDivider(width: 1, color: pal.line),
        // Right — order ticket
        SizedBox(
          width: 340,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
            child: SandboxTradeTicket(symbol: _symbol),
          ),
        ),
      ],
    );
  }
}

/// Compact performance Overview shown as the top section of the desktop Trade
/// workspace: the same summary metrics as the Books tab, laid out as a single
/// horizontal strip of stat cards. Reads [simState] directly — the screen's
/// top-level ListenableBuilder rebuilds it every tick.
class _OverviewStrip extends StatelessWidget {
  const _OverviewStrip();

  @override
  Widget build(BuildContext context) {
    final acc = simState.account;
    final trades = simState.trades;
    final closed = trades.where((t) => t.realizedPnl != 0).toList();
    final wins = closed.where((t) => t.realizedPnl > 0).length;
    final winRate = closed.isEmpty ? 0.0 : wins / closed.length * 100;
    final fees = trades.fold<double>(0, (s, t) => s + t.fee);
    final equity = simState.equity;
    final start = acc?.startingCash ?? 0;
    final totalRet = start == 0 ? 0.0 : (equity - start) / start * 100;
    final cur = simState.currency;

    final cards = <Widget>[
      StatCard(
          label: 'Equity',
          value: simMoney(equity, currency: cur),
          icon: Icons.account_balance_wallet_outlined),
      StatCard(
        label: 'Total return',
        value: signedPctStr(totalRet),
        valueColor: NqeColors.pnl(totalRet),
        icon: Icons.trending_up,
      ),
      StatCard(
        label: 'Realized P/L',
        value: simSignedMoney(acc?.realizedPnl ?? 0, currency: cur),
        valueColor: NqeColors.pnl(acc?.realizedPnl ?? 0),
        icon: Icons.paid_outlined,
      ),
      StatCard(
        label: 'Win rate',
        value: closed.isEmpty ? '—' : '${winRate.toStringAsFixed(0)}%',
        sub: '${closed.length} closed',
        icon: Icons.emoji_events_outlined,
      ),
      StatCard(
          label: 'Fees paid',
          value: simMoney(fees, currency: cur),
          icon: Icons.receipt_outlined),
      StatCard(
          label: 'Total trades',
          value: '${trades.length}',
          icon: Icons.swap_horiz),
    ];

    // Wrap (not a fixed 6-wide Row) so on a narrow center column the cards flow
    // to a second line and stay legible instead of being crushed to ~40px each.
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in cards) SizedBox(width: 158, child: c),
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
              const SizedBox(width: 6),
              // Tappable profile switcher — the active profile's name with a
              // dropdown chevron. Tapping opens the profile sheet (switch /
              // create / rename / delete). Always a simulation (no real
              // orders); the badge reflects only whether the data is live.
              Flexible(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openProfiles(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(simState.account?.name ?? 'Sandbox',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: pal.textHi,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                        ),
                        Icon(Icons.expand_more, size: 20, color: pal.textLo),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (live ? NqeColors.gain : pal.textLo).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(live ? 'LIVE DATA' : 'SIMULATION',
                    style: TextStyle(
                        color: live ? NqeColors.gain : pal.textLo,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
              const Spacer(),
              // Feed toggle
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _confirmFeedSwitch(context, toLive: !live),
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
                // Top up / Cash out live on the Wallet tab now, so the menu is
                // just the account reset.
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

  Future<void> _confirmFeedSwitch(BuildContext context,
      {required bool toLive}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(toLive ? 'Switch to Live data?' : 'Switch to Simulated?'),
        content: Text(toLive
            ? 'The chart and prices will use REAL market data. Your trades stay '
                'simulated — virtual money only, no real orders are placed.'
            : 'Prices will use an offline simulation for practice. Your account '
                'and positions are unchanged.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(toLive ? 'Go Live' : 'Simulate')),
        ],
      ),
    );
    if (ok == true) {
      simState.setFeedMode(toLive ? FeedMode.live : FeedMode.simulated);
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset sandbox?'),
        content: const Text(
            'This closes all positions and orders, clears your trade and order '
            'history, and restores your virtual balance to the starting cash. '
            'This cannot be undone.'),
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

  void _openProfiles(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProfileSheet(),
    );
  }
}

/// Bottom sheet listing sandbox profiles: tap to switch, plus create / rename /
/// delete. Each profile is its own isolated virtual account.
class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet();

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  bool _creating = false;
  final _name = TextEditingController();
  final _cash = TextEditingController(text: '1,000,000');
  String _cur = 'PHP';

  @override
  void dispose() {
    _name.dispose();
    _cash.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final cash = double.tryParse(_cash.text.replaceAll(',', '').trim()) ?? 0;
    await simState.createProfile(
      name: _name.text,
      currency: _cur,
      startingCash: cash,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return ListenableBuilder(
      listenable: simState,
      builder: (context, _) {
        final profiles = simState.profiles;
        final activeId = simState.activeId;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Container(
            decoration: BoxDecoration(
              color: pal.bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                          color: pal.line,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Row(
                    children: [
                      Text('Profiles',
                          style: TextStyle(
                              color: pal.textHi,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      const Spacer(),
                      if (!_creating)
                        TextButton.icon(
                          onPressed: () => setState(() => _creating = true),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('New'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_creating)
                    _createForm(pal)
                  else
                    for (final a in profiles)
                      _profileRow(pal, a, a.id == activeId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _profileRow(NqePalette pal, SimAccount a, bool active) {
    final eq = simState.equityOfProfile(a.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active ? pal.surface2 : pal.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await simState.switchProfile(a.id);
            if (mounted) Navigator.of(context).pop();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: active ? pal.textHi.withOpacity(0.4) : pal.line),
            ),
            child: Row(
              children: [
                Icon(active ? Icons.radio_button_checked : Icons.circle_outlined,
                    size: 18, color: active ? pal.textHi : pal.textLo),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: pal.textHi,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${simMoney(eq, currency: a.currency)} · ${a.currency}',
                          style: TextStyle(color: pal.textLo, fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, color: pal.textLo),
                  onSelected: (v) {
                    if (v == 'rename') _renameDialog(a);
                    if (v == 'delete') _deleteDialog(a);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    if (simState.profiles.length > 1)
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _createForm(NqePalette pal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Profile name', isDense: true),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('Currency',
                style: TextStyle(color: pal.textLo, fontSize: 13)),
            const Spacer(),
            for (final c in const ['PHP', 'USD', 'EUR'])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: InkWell(
                  onTap: () => setState(() => _cur = c),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
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
                    child: Text(c,
                        style: TextStyle(
                            color: c == _cur ? pal.textHi : pal.textLo,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _cash,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Starting cash', isDense: true),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
                onPressed: () => setState(() => _creating = false),
                child: const Text('Cancel')),
            const Spacer(),
            FilledButton(
                onPressed: _create, child: const Text('Create profile')),
          ],
        ),
      ],
    );
  }

  Future<void> _renameDialog(SimAccount a) async {
    final ctrl = TextEditingController(text: a.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rename profile'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await simState.renameProfile(a.id, name);
    }
  }

  Future<void> _deleteDialog(SimAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${a.name}"?'),
        content: const Text(
            'This permanently removes the profile and all its positions, '
            'orders and trade history. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: NqeColors.loss),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await simState.deleteProfile(a.id);
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
