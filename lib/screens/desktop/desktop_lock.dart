// Desktop app lock. Unlike the mobile keypad, the desktop accepts an
// alphanumeric password OR a numeric PIN through a normal obscured TextField
// (AuthService hashes any string, so the same stored secret works). No
// biometric on desktop. Honors the shared escalating lockout.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/nqe_logo.dart';

class DesktopLock extends StatefulWidget {
  /// Invoked once the correct PIN / password is entered.
  final VoidCallback onUnlocked;
  const DesktopLock({super.key, required this.onUnlocked});

  @override
  State<DesktopLock> createState() => _DesktopLockState();
}

class _DesktopLockState extends State<DesktopLock> {
  final _auth = AuthService.instance;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  bool _obscure = true;
  bool _error = false;
  bool _busy = false;
  int _lockRemaining = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _refreshLockout();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _refreshLockout() async {
    final remaining = await _auth.lockoutRemaining();
    if (!mounted) return;
    setState(() => _lockRemaining = remaining);
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

  Future<void> _submit() async {
    if (_busy || _lockRemaining > 0) return;
    final value = _controller.text;
    if (value.isEmpty) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    bool ok = false;
    try {
      ok = await _auth.submitPin(value);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    await _refreshLockout();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = true;
      _controller.clear();
    });
    _focus.requestFocus();
  }

  String _fmtLock(int s) {
    if (s >= 60) return '${(s / 60).ceil()}m';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final locked = _lockRemaining > 0;
    return Scaffold(
      backgroundColor: pal.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NqeLogo(scale: 0.7),
                const SizedBox(height: 28),
                Text(
                  locked
                      ? 'Too many attempts — try again in ${_fmtLock(_lockRemaining)}'
                      : 'Enter your PIN or password',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: locked ? NqeColors.loss : pal.textLo,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  enabled: !locked && !_busy,
                  obscureText: _obscure,
                  obscuringCharacter: '•',
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'PIN or password',
                    prefixIcon: Icon(Icons.lock_outline, color: pal.textLo),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: pal.textLo,
                      ),
                      tooltip: _obscure ? 'Show' : 'Hide',
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_error && !locked)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Wrong PIN or password, try again',
                      style: TextStyle(color: NqeColors.loss, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (locked || _busy) ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Unlock'),
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
