// App lock. Supports OS biometric / device-credential (fingerprint, face,
// device PIN, pattern, password) via local_auth, plus an in-app PIN fallback.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/nqe_logo.dart';
import 'home_shell.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth = AuthService.instance;
  String _entered = '';
  bool _hasPin = false;
  bool _canBio = false;
  bool _error = false;
  final int _pinMax = 6;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    _hasPin = await _auth.hasPin();
    final bioEnabled = await _auth.biometricEnabled();
    _canBio = bioEnabled && await _auth.canUseBiometrics();
    if (mounted) setState(() {});
    // Auto-prompt biometric on open.
    if (_canBio) _tryBiometric();
    // If lock is on but nothing is actually configured, don't trap the user.
    if (!_hasPin && !_canBio) _unlock();
  }

  Future<void> _tryBiometric() async {
    final ok = await _auth.authenticateBiometric();
    if (ok) _unlock();
  }

  void _unlock() {
    if (!mounted) return;
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
    if (_entered.length >= _pinMax) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered += d;
      _error = false;
    });
    if (_entered.length >= 4) {
      // Try verifying once we have at least 4 digits.
      final ok = await _auth.verifyPin(_entered);
      if (ok) {
        _unlock();
      } else if (_entered.length >= _pinMax) {
        HapticFeedback.heavyImpact();
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

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            const NqeLogo(scale: 0.7),
            const SizedBox(height: 16),
            Text(
              _hasPin ? 'Enter your PIN' : 'Unlock to continue',
              style: TextStyle(color: pal.textLo, fontSize: 14),
            ),
            const SizedBox(height: 20),
            if (_hasPin) _dots(pal),
            if (_error)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Wrong PIN, try again',
                    style: TextStyle(color: NqeColors.loss, fontSize: 13)),
              ),
            const Spacer(flex: 2),
            if (_hasPin)
              _keypad(pal)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: FilledButton.icon(
                  onPressed: _tryBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _dots(NqePalette pal) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pinMax, (i) {
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
            return _canBio
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
