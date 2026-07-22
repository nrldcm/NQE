// Branded animated splash. Runs first-launch bootstrap (seed + load) then
// routes to the lock screen (if enabled) or straight into the app.
import 'package:flutter/material.dart';

import '../seed.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/nqe_logo.dart';
import 'home_shell.dart';
import 'lock_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.92, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));
    _c.forward();
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    await seedIfEmpty();
    await appState.load();
    final lock = await AuthService.instance.lockEnabled();

    // Keep the splash visible for at least ~1.2s for a polished feel.
    final elapsed = DateTime.now().difference(started);
    final remaining = const Duration(milliseconds: 1200) - elapsed;
    if (remaining > Duration.zero) await Future.delayed(remaining);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) =>
            lock ? const LockScreen() : const HomeShell(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NqeLogo(scale: 1.1),
                const SizedBox(height: 28),
                const WillongByline(),
                const SizedBox(height: 40),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: pal.textLo,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
