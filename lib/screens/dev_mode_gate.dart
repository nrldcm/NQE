// Full-screen anti-tamper gate: while Android "Developer options" (or USB
// debugging) is enabled, the app is blocked with instructions to turn it off.
// Enforced in RELEASE builds only, so development isn't hindered. Re-checks
// automatically whenever the app resumes (e.g. after the user flips the setting
// in Android Settings and switches back), plus a manual Re-check button.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/device_integrity.dart';
import '../theme.dart';

class DevModeGate extends StatefulWidget {
  const DevModeGate({super.key});

  @override
  State<DevModeGate> createState() => _DevModeGateState();
}

class _DevModeGateState extends State<DevModeGate>
    with WidgetsBindingObserver {
  bool _blocked = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-probe when the user comes back from Android Settings.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    // Only enforced in release — debug/profile dev builds are never blocked.
    if (!kReleaseMode) {
      if (_blocked && mounted) setState(() => _blocked = false);
      return;
    }
    if (_checking) return;
    setState(() => _checking = true);
    final on = await DeviceIntegrity.developerOptionsEnabled();
    if (!mounted) return;
    setState(() {
      _blocked = on;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_blocked) return const SizedBox.shrink();
    final pal = context.nqe;
    return Material(
      color: pal.bg,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: NqeColors.loss.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.developer_mode,
                        size: 38, color: NqeColors.loss),
                  ),
                  const SizedBox(height: 22),
                  Text('Developer Mode is on',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: pal.textHi,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text(
                    'For the security of the fund data, NQE can’t run while '
                    'Android Developer options (or USB debugging) is enabled.\n\n'
                    'Please turn it off, then tap Re-check:\n'
                    'Settings → System → Developer options → off.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: pal.textLo, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _check,
                      icon: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      label: Text(_checking ? 'Checking…' : 'Re-check'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
