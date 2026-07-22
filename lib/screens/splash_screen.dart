// Branded animated splash. Runs first-launch bootstrap, then routes to:
//   * Onboarding  (first run / after reinstall — security setup is required)
//   * LockScreen  (returning user with app-lock enabled)
//   * HomeShell   (returning user, no lock)
// Boot is fully guarded so the app can never get stuck on the loading screen.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../seed.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/nqe_logo.dart';
import 'home_shell.dart';
import 'lock_screen.dart';
import 'onboarding_screen.dart';

const String kOnboardedKey = 'onboarded';

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
    bool onboarded = false;
    bool lock = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      onboarded = prefs.getBool(kOnboardedKey) ?? false;
      if (onboarded) {
        await seedIfEmpty();
        await appState.load();
        lock = await AuthService.instance.lockEnabled();
      }
    } catch (_) {
      // Never hang on the splash — proceed to a safe destination even if boot
      // hit an error. A returning user still reaches the app; a new user still
      // reaches onboarding.
    }

    // Keep the splash visible briefly for a polished feel.
    final elapsed = DateTime.now().difference(started);
    final remaining = const Duration(milliseconds: 1200) - elapsed;
    if (remaining > Duration.zero) await Future.delayed(remaining);
    if (!mounted) return;

    final Widget next = !onboarded
        ? const OnboardingScreen()
        : (lock ? const LockScreen() : const HomeShell());

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => next,
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
