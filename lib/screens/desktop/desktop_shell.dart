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

    // Paired + unlocked. Gate the workspace on a live link: once the connection
    // gives up (disconnected), fall back to a reconnect / re-pair screen so a
    // stale, unsynced desktop can't be mistaken for a live one.
    return ListenableBuilder(
      listenable: SyncClient.instance,
      builder: (context, _) {
        if (SyncClient.instance.state == SyncConn.disconnected) {
          return _ReconnectGate(
            message: SyncClient.instance.statusMessage,
            onRetry: () => SyncClient.instance.reconnect(),
            onRepair: () {
              // Send the user back to the pairing gate to re-pair the device.
              setState(() {
                _paired = false;
                _unlocked = false;
              });
            },
          );
        }
        return const DesktopShell();
      },
    );
  }
}

/// Shown on the desktop when the link to the phone has dropped: it keeps
/// auto-reconnecting in the background, and offers a manual retry or a jump back
/// to the re-pair gate.
class _ReconnectGate extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onRepair;
  const _ReconnectGate({
    required this.message,
    required this.onRetry,
    required this.onRepair,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link_off, size: 48, color: pal.textLo),
                const SizedBox(height: 18),
                Text('Disconnected from phone',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: pal.textHi,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  message ??
                      'The desktop lost its link to the phone. It keeps trying '
                          'to reconnect automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pal.textLo, fontSize: 13),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(pal.textLo)),
                    ),
                    const SizedBox(width: 10),
                    Text('Reconnecting…',
                        style: TextStyle(color: pal.textLo, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Try now'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: pal.textHi,
                          side: BorderSide(color: pal.line),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onRepair,
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: const Text('Re-pair device'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    // Binance-style: a slim top navigation bar, and the workspace below it
    // spanning the FULL width — so the chart and data panels get every pixel.
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopNav(
              index: _index,
              onChanged: (i) => setState(() => _index = i),
            ),
            Divider(height: 1, thickness: 1, color: pal.line),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: KeyedSubtree(
                  key: ValueKey<int>(_index),
                  child: _panel(_index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim horizontal navigation bar (Binance-style): logo, the section tabs, and
/// the live connection glyph — all in one compact row so the body below spans
/// the full width and height.
class _TopNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _TopNav({required this.index, required this.onChanged});

  static const List<(IconData, IconData, String)> _items = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Home'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet,
        'Books'),
    (Icons.candlestick_chart_outlined, Icons.candlestick_chart, 'Live'),
    (Icons.science_outlined, Icons.science, 'Trade'),
    (Icons.insights_outlined, Icons.insights, 'Stats'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Container(
      height: 52,
      color: pal.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          NqeLogo(scale: 0.19, showTagline: false),
          const SizedBox(width: 18),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _NavItem(
                icon: _items[i].$1,
                selectedIcon: _items[i].$2,
                label: _items[i].$3,
                selected: i == index,
                onTap: () => onChanged(i),
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final c = selected ? pal.textHi : pal.textLo;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? pal.textHi.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? selectedIcon : icon, size: 17, color: c),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: c,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
