import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/auth_service.dart';
import 'screens/lock_screen.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (lockScreenActive) return; // a lock is already showing
    if (!await AuthService.instance.lockEnabled()) return;
    if (!await AuthService.instance.hasUsableFactor()) return;
    final nav = _navKey.currentState;
    if (nav == null) return;
    await nav.push(MaterialPageRoute(
      builder: (_) => const LockScreen(resumeLock: true),
      fullscreenDialog: true,
    ));
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
          home: const SplashScreen(),
        );
      },
    );
  }
}
