// Desktop shell — the NQE app in "client mode", with full feature parity with
// the phone: Home / Books / Live / Stats / Settings, plus a live LAN-sync glyph
// in the top bar. First run shows secure QR pairing; after that the app gates
// on the (phone-mirrored) PIN lock before revealing the shell. The body reuses
// the existing mobile screens verbatim so there is a single source of truth for
// the presentation. Light/dark follows the shared themeController.
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../sim/sim_state.dart';
import '../../sim/ui/sandbox_screen.dart';
import '../../state/app_state.dart';
import '../../sync/sync_client.dart';
import '../../theme.dart';
import '../../widgets/connection_watcher.dart';
import '../../widgets/nqe_logo.dart';
import '../books_screen.dart';
import '../dashboard_screen.dart';
import '../settings_screen.dart';
import '../stats_screen.dart';
import 'desktop_live.dart';
import 'desktop_lock.dart';
import 'pairing_screen.dart';

/// Root desktop application. Mirrors [NqeApp] but targets the desktop shell.
class DesktopApp extends StatelessWidget {
  const DesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'NQE Desktop',
          debugShowCheckedModeBanner: false,
          theme: buildNqeTheme(Brightness.light),
          darkTheme: buildNqeTheme(Brightness.dark),
          themeMode: themeController.mode,
          home: const _DesktopBootstrap(),
        );
      },
    );
  }
}

/// Loads state, then routes: not-paired → pairing; paired + locked → lock;
/// otherwise → the shell. Fails CLOSED on the lock.
class _DesktopBootstrap extends StatefulWidget {
  const _DesktopBootstrap();

  @override
  State<_DesktopBootstrap> createState() => _DesktopBootstrapState();
}

class _DesktopBootstrapState extends State<_DesktopBootstrap> {
  bool _ready = false;
  bool _paired = false;
  bool _locked = false;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await appState.load();
    } catch (_) {
      // Non-fatal — the shell will simply show empty state.
    }

    bool paired = false;
    try {
      paired = await SyncClient.instance.isPaired();
    } catch (_) {
      paired = false;
    }

    // A paired desktop mirrors the phone's Sandbox engine (it displays synced
    // state and forwards orders) so the two devices can never diverge.
    simState.mirror = paired;

    if (paired) {
      // Auto-connect to the paired phone; state surfaces via ConnectionWatcher.
      try {
        SyncClient.instance.connect();
      } catch (_) {/* best-effort */}
    }

    bool locked = false;
    try {
      locked = paired &&
          await AuthService.instance.lockEnabled() &&
          await AuthService.instance.hasUsableFactor();
    } catch (_) {
      // Fail CLOSED: if we can't verify the lock on a paired desktop, require
      // an unlock rather than exposing the ledger. (A paired desktop that has a
      // lock configured always has the mirrored PIN, so this can't lock the
      // user out; an unpaired desktop goes to pairing, never here.)
      locked = paired;
    }

    if (!mounted) return;
    setState(() {
      _paired = paired;
      _locked = locked;
      _ready = true;
    });
  }

  void _onPaired() {
    // Now paired → this desktop mirrors the phone's Sandbox.
    simState.mirror = true;
    // Re-run boot so the lock (now mirrored from the phone) is applied.
    setState(() {
      _ready = false;
      _unlocked = false;
    });
    _boot();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    if (!_ready) {
      return Scaffold(
        backgroundColor: pal.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NqeLogo(scale: 0.6),
              const SizedBox(height: 24),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(pal.textLo),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_paired) {
      return DesktopPairingScreen(onPaired: _onPaired);
    }

    if (_locked && !_unlocked) {
      return DesktopLock(onUnlocked: () => setState(() => _unlocked = true));
    }
    return const DesktopShell();
  }
}

/// The main desktop workspace: a rail on the left, a slim top bar with the live
/// connection glyph, and a fluid body that swaps between the reused screens.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _index = 0;

  static const _titles = [
    'Dashboard',
    'Books',
    'Live',
    'Sandbox',
    'Statistics',
    'Settings'
  ];

  Widget _panel(int i) {
    switch (i) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const BooksScreen();
      case 2:
        return const DesktopLiveScreen();
      case 3:
        return const SandboxScreen();
      case 4:
        return const StatsScreen();
      default:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final extended = constraints.maxWidth >= 1100;
            return Row(
              children: [
                _NavRail(
                  index: _index,
                  extended: extended,
                  onChanged: (i) => setState(() => _index = i),
                ),
                VerticalDivider(width: 1, thickness: 1, color: pal.line),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(title: _titles[_index]),
                      Divider(height: 1, thickness: 1, color: pal.line),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: child,
                          ),
                          child: KeyedSubtree(
                            key: ValueKey<int>(_index),
                            child: _panel(_index),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  final int index;
  final bool extended;
  final ValueChanged<int> onChanged;
  const _NavRail({
    required this.index,
    required this.extended,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return NavigationRail(
      selectedIndex: index,
      onDestinationSelected: onChanged,
      extended: extended,
      backgroundColor: pal.surface,
      labelType:
          extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      groupAlignment: -0.9,
      selectedIconTheme: IconThemeData(color: pal.textHi),
      unselectedIconTheme: IconThemeData(color: pal.textLo),
      selectedLabelTextStyle:
          TextStyle(color: pal.textHi, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: TextStyle(color: pal.textLo),
      indicatorColor: pal.textHi.withOpacity(0.10),
      leading: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: extended ? 16 : 8,
          vertical: 18,
        ),
        child: NqeLogo(scale: extended ? 0.28 : 0.18, showTagline: false),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: Text('Home'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: Text('Books'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.candlestick_chart_outlined),
          selectedIcon: Icon(Icons.candlestick_chart),
          label: Text('Live'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.science_outlined),
          selectedIcon: Icon(Icons.science),
          label: Text('Sandbox'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights),
          label: Text('Stats'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings'),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  const _TopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Container(
      height: 56,
      color: pal.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: pal.textHi,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: SyncClient.instance,
            builder: (context, _) => ConnectionWatcher(
              SyncClient.instance.state,
              attempt: SyncClient.instance.attempt,
            ),
          ),
        ],
      ),
    );
  }
}
