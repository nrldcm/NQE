// App lock. Supports OS biometric / device-credential (fingerprint, face,
// device PIN, pattern, password) via local_auth, plus an in-app PIN with an
// escalating lockout. Fails CLOSED — a misconfigured lock never auto-opens.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/nqe_logo.dart';
import 'home_shell.dart';

/// True whenever a LockScreen is on screen — lets the app-level lifecycle
/// guard avoid stacking a second lock over an existing one.
bool lockScreenActive = false;

class LockScreen extends StatefulWidget {
  /// When true the screen was pushed on resume and simply pops on unlock
  /// (revealing the screen underneath) instead of rebuilding the app.
  final bool resumeLock;
  const LockScreen({super.key, this.resumeLock = false});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth = AuthService.instance;
  String _entered = '';
  bool _hasPin = false;
  bool _canBio = false;
  bool _error = false;
  int _lockRemaining = 0;
  int _pinLen = 4;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    lockScreenActive = true;
    _prepare();
  }

  @override
  void dispose() {
    lockScreenActive = false;
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _prepare() async {
    _hasPin = await _auth.hasPin();
    _pinLen = await _auth.pinLength();
    if (_pinLen < 4 || _pinLen > 6) _pinLen = _hasPin ? 4 : 4;
    final bioEnabled = await _auth.biometricEnabled();
    _canBio = bioEnabled && await _auth.canUseBiometrics();
    await _refreshLockout();
    if (mounted) setState(() {});
    // Don't prompt biometrics while locked out.
    if (_lockRemaining > 0) return;
    // Auto-prompt the OS on open when biometrics are on, OR — to fail closed —
    // whenever there is no in-app PIN configured (forces device credential).
    if (_canBio || !_hasPin) _tryBiometric();
  }

  Future<void> _refreshLockout() async {
    final remaining = await _auth.lockoutRemaining();
    _lockRemaining = remaining;
    _ticker?.cancel();
    if (remaining > 0) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (t) async {
        final r = await _auth.lockoutRemaining();
        if (!mounted) return;
        setState(() => _lockRemaining = r);
        if (r <= 0) t.cancel();
      });
    }
  }

  Future<void> _tryBiometric() async {
    // No biometric/face prompt while the app is in a lockout ("waiting") state.
    if (await _auth.lockoutRemaining() > 0) {
      await _refreshLockout();
      if (mounted) setState(() {});
      return;
    }
    final ok = await _auth.authenticateBiometric();
    if (ok) _unlock();
  }

  void _unlock() {
    if (!mounted) return;
    if (widget.resumeLock) {
      // Pushed over the running app on resume — just reveal it again.
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _onDigit(String d) async {
    if (_lockRemaining > 0) return;
    if (_entered.length >= _pinLen) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered += d;
      _error = false;
    });
    // Only verify a COMPLETE PIN — never partial entries (which would spam the
    // failure counter and trigger a false lockout even for the right PIN).
    if (_entered.length == _pinLen) {
      final ok = await _auth.submitPin(_entered);
      if (!mounted) return;
      if (ok) {
        _unlock();
      } else {
        HapticFeedback.heavyImpact();
        await _refreshLockout();
        if (!mounted) return;
        setState(() {
          _error = true;
          _entered = '';
        });
      }
    }
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  String _fmtLock(int s) {
    if (s >= 60) {
      final m = (s / 60).ceil();
      return '${m}m';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final locked = _lockRemaining > 0;
    return PopScope(
      canPop: false, // never allow the lock to be dismissed by back gesture
      child: Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            const NqeLogo(scale: 0.7),
            const SizedBox(height: 16),
            Text(
              locked
                  ? 'Too many attempts — try again in ${_fmtLock(_lockRemaining)}'
                  : (_hasPin ? 'Enter your PIN' : 'Unlock to continue'),
              style: TextStyle(
                  color: locked ? NqeColors.loss : pal.textLo, fontSize: 14),
            ),
            const SizedBox(height: 20),
            if (_hasPin) _dots(pal),
            if (_error && !locked)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Wrong PIN, try again',
                    style: TextStyle(color: NqeColors.loss, fontSize: 13)),
              ),
            const Spacer(flex: 2),
            if (_hasPin)
              Opacity(opacity: locked ? 0.4 : 1, child: _keypad(pal))
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: FilledButton.icon(
                  onPressed: locked ? null : _tryBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      ),
    );
  }

  Widget _dots(NqePalette pal) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pinLen, (i) {
        final filled = i < _entered.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 7),
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? pal.textHi : Colors.transparent,
            border: Border.all(color: pal.textLo, width: 1.5),
          ),
        );
      }),
    );
  }

  Widget _keypad(NqePalette pal) {
    final keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      'bio', '0', 'del',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.5,
        children: keys.map((k) {
          if (k == 'bio') {
            // Hide the biometric key while locked out.
            return (_canBio && _lockRemaining == 0)
                ? _keyButton(
                    pal,
                    child: Icon(Icons.fingerprint, color: pal.textHi, size: 26),
                    onTap: _tryBiometric,
                  )
                : const SizedBox();
          }
          if (k == 'del') {
            return _keyButton(
              pal,
              child: Icon(Icons.backspace_outlined,
                  color: pal.textHi, size: 22),
              onTap: _backspace,
            );
          }
          return _keyButton(
            pal,
            child: Text(k,
                style: TextStyle(
                    color: pal.textHi,
                    fontSize: 24,
                    fontWeight: FontWeight.w600)),
            onTap: () => _onDigit(k),
          );
        }).toList(),
      ),
    );
  }

  Widget _keyButton(NqePalette pal,
      {required Widget child, required VoidCallback onTap}) {
    return Material(
      color: pal.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}
