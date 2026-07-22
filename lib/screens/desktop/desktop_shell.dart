// Desktop shell — the same NQE app in "client mode". A fluid, responsive
// layout with a left NavigationRail (Dashboard / Books / Stats / Sync) and a
// top bar carrying the app title and a live LAN-sync connection glyph. The body
// reuses the existing mobile screens verbatim so there is a single source of
// truth for the presentation. Light/dark follows the shared themeController.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../sync/sync_client.dart';
import '../../theme.dart';
import '../../widgets/connection_watcher.dart';
import '../../widgets/nqe_logo.dart';
import '../books_screen.dart';
import '../dashboard_screen.dart';
import '../stats_screen.dart';
import 'desktop_lock.dart';
import 'sync_panel.dart';

/// Root desktop application. Mirrors [NqeApp] but targets the desktop shell and
/// carries the desktop-specific title. Theme is driven by [themeController].
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

/// Loads app state, kicks off LAN auto-connect and gates on the app lock before
/// revealing the shell. Fails CLOSED — a configured lock is always shown first.
class _DesktopBootstrap extends StatefulWidget {
  const _DesktopBootstrap();

  @override
  State<_DesktopBootstrap> createState() => _DesktopBootstrapState();
}

class _DesktopBootstrapState extends State<_DesktopBootstrap> {
  bool _ready = false;
  bool _locked = false;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    bool locked = false;
    try {
      // Populate the reused screens.
      await appState.load();
    } catch (_) {
      // Non-fatal — the shell will simply show empty state.
    }

    try {
      // Auto-connect to the paired mobile if a pairing URI was saved before.
      // Await the load so the decision is deterministic (the constructor's
      // hydrate is fire-and-forget and may not have completed yet).
      final hasPairing = await SyncClient.instance.loadSaved();
      if (hasPairing) {
        // Fire-and-forget — the connection state surfaces via ConnectionWatcher.
        unawaited(SyncClient.instance.connect());
      }
    } catch (_) {
      // Ignore — sync is best-effort.
    }

    try {
      locked = await AuthService.instance.lockEnabled() &&
          await AuthService.instance.hasUsableFactor();
    } catch (_) {
      locked = false;
    }

    if (!mounted) return;
    setState(() {
      _locked = locked;
      _ready = true;
    });
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

    if (_locked && !_unlocked) {
      return DesktopLock(
        onUnlocked: () => setState(() => _unlocked = true),
      );
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

  static const _titles = ['Dashboard', 'Books', 'Statistics', 'Sync'];

  Widget _panel(int i) {
    switch (i) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const BooksScreen();
      case 2:
        return const StatsScreen();
      default:
        return const SyncPanel();
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
            // Give the rail room to show labels on wider windows.
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
          label: Text('Dashboard'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: Text('Books'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights),
          label: Text('Stats'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.sync_outlined),
          selectedIcon: Icon(Icons.sync),
          label: Text('Sync'),
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
          // Live connection glyph — rebuilds as the sync state changes.
          ListenableBuilder(
            listenable: SyncClient.instance,
            builder: (context, _) =>
                ConnectionWatcher(SyncClient.instance.state),
          ),
        ],
      ),
    );
  }
}
