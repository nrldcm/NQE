import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'db/database.dart';
import 'services/auth_service.dart';
import 'services/error_log.dart';
import 'sim/sim_db.dart';
import 'sim/sim_state.dart';
import 'screens/desktop/desktop_shell.dart';
import 'screens/desktop_mode_gate.dart';
import 'screens/lock_screen.dart';
import 'screens/splash_screen.dart';
import 'sync/sync_server.dart';
import 'theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Route uncaught framework/platform errors to the on-device rotating log.
  ErrorLog.instance.installGlobalHandlers();

  final isDesktop = !kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  if (isDesktop) {
    // Enforce a single running instance on Windows — a second launch just
    // focuses the existing window instead of opening another.
    if (Platform.isWindows) {
      try {
        await WindowsSingleInstance.ensureSingleInstance(
          args,
          'nqe_desktop_single_instance',
          onSecondWindow: (_) {
            windowManager.show();
            windowManager.focus();
          },
        );
      } catch (_) {/* non-fatal */}
    }

    // Desktop runs the same app in "client mode": the local DB is backed by
    // the sqflite FFI (sqlite3) implementation instead of the mobile plugin.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // The desktop is a pure mirror of the phone: keep BOTH the ledger and the
    // Sandbox databases in memory only, so it persists nothing and always
    // gets/sends its data through the phone (the single source of truth) —
    // no divergent local state on the desktop.
    LedgerDb.ephemeral = true;
    SimDb.ephemeral = true;

    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      minimumSize: Size(900, 620),
      size: Size(1200, 780),
      title: 'NQE Desktop',
      center: true,
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    await themeController.load();
    runApp(const DesktopApp());
    return;
  }

  // Mobile bootstrap (unchanged).
  await themeController.load();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const NqeApp());
}

class NqeApp extends StatefulWidget {
  const NqeApp({super.key});

  @override
  State<NqeApp> createState() => _NqeAppState();
}

class _NqeAppState extends State<NqeApp> with WidgetsBindingObserver {
  final _navKey = GlobalKey<NavigatorState>();
  bool _backgrounded = false;
  bool _relocking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start the sandbox engine at launch so pending orders keep getting watched
    // and filled in the background (and fire notifications) even when the Trade
    // tab isn't open — like a real trading account. Mobile only (a paired
    // desktop is a mirror and must not run its own engine).
    simState.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
    } else if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      _maybeRelock();
    }
  }

  // Re-lock the app when it returns to the foreground after being backgrounded.
  Future<void> _maybeRelock() async {
    if (_relocking || lockScreenActive) return; // don't stack lock screens
    // A backup import/export legitimately backgrounds the app (file picker /
    // share sheet). Consume the one-shot suppress so returning from it doesn't
    // pop a lock screen and interrupt the restore.
    if (AuthService.suppressAutoLock) {
      AuthService.suppressAutoLock = false;
      return;
    }
    _relocking = true;
    try {
      if (!await AuthService.instance.lockEnabled()) return;
      if (!await AuthService.instance.hasUsableFactor()) return;
      final nav = _navKey.currentState;
      if (nav == null) return;
      await nav.push(MaterialPageRoute(
        builder: (_) => const LockScreen(resumeLock: true),
        fullscreenDialog: true,
      ));
    } finally {
      _relocking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'NQE',
          navigatorKey: _navKey,
          debugShowCheckedModeBanner: false,
          theme: buildNqeTheme(Brightness.light),
          darkTheme: buildNqeTheme(Brightness.dark),
          themeMode: themeController.mode,
          // While a desktop is connected in Desktop Mode, overlay a full-screen
          // gate so the phone (the source of truth) isn't driven at the same
          // time — one active device, no conflicting edits.
          builder: (context, child) => ListenableBuilder(
            listenable: SyncServer.instance,
            builder: (context, _) => Stack(
              children: [
                child ?? const SizedBox.shrink(),
                if (SyncServer.instance.connectedPeers > 0)
                  const DesktopModeGate(),
              ],
            ),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}
