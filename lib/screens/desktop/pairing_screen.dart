// Desktop first-run pairing: show a QR the phone scans, then confirm with the
// 6-digit code the phone displays. On success the desktop adopts the phone's
// sync endpoint + PIN and moves on to the shell.
//
// UX: the LAN address is never shown (the QR carries it). The code entry only
// appears AFTER the phone has scanned. The QR auto-refreshes on a timeout, and
// the user can go "Back to QR" to let the phone re-scan a fresh code.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../sync/pairing_host.dart';
import '../../sync/sync_client.dart';
import '../../theme.dart';
import '../../widgets/nqe_logo.dart';

class DesktopPairingScreen extends StatefulWidget {
  /// Called once pairing completes and the target + PIN have been stored.
  final VoidCallback onPaired;
  const DesktopPairingScreen({super.key, required this.onPaired});

  @override
  State<DesktopPairingScreen> createState() => _DesktopPairingScreenState();
}

class _DesktopPairingScreenState extends State<DesktopPairingScreen> {
  final _host = PairingHost();
  final _codeCtrl = TextEditingController();
  bool _finishing = false;

  // A pairing session lives for this long before the QR auto-refreshes (a fresh
  // key pair + session id). The window resets when the phone scans, giving full
  // time to type the code.
  static const int _windowSeconds = 180;
  Timer? _ticker;
  int _secondsLeft = _windowSeconds;
  bool _sawOffer = false;

  @override
  void initState() {
    super.initState();
    _host.addListener(_onHost);
    _host.start();
    _startCountdown();
  }

  void _onHost() {
    if (!mounted) return;
    // When the phone first scans, reset the window so the user has the full
    // time to read + type the code.
    if (_host.hasOffer && !_sawOffer) {
      _sawOffer = true;
      _secondsLeft = _windowSeconds;
    }
    setState(() {});
  }

  void _startCountdown() {
    _ticker?.cancel();
    _secondsLeft = _windowSeconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) _restart();
    });
  }

  // Regenerate a fresh QR (new keys + session id) and return to the waiting
  // state so the phone can scan again. Used by "Back to QR" and on timeout.
  Future<void> _restart() async {
    _sawOffer = false;
    _codeCtrl.clear();
    _finishing = false;
    await _host.start();
    _startCountdown();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _host.removeListener(_onHost);
    _host.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      _snack('Enter the 6-digit code from your phone.');
      return;
    }
    setState(() => _finishing = true);
    try {
      final payload = await _host.verifyCodeAndFinish(code);
      if (payload == null) {
        _snack(_host.statusMessage ?? 'Incorrect code.');
        return;
      }
      if (payload.hasPin) {
        await AuthService.instance.importPinCredential(
          hash: payload.pinHash!,
          salt: payload.pinSalt!,
          len: payload.pinLen,
        );
      }
      await SyncClient.instance.setTargets(
        hosts: payload.allHosts,
        port: payload.syncPort,
        key: payload.syncKey,
      );
      try {
        await appState.load();
      } catch (_) {/* non-fatal */}
      if (!mounted) return;
      _ticker?.cancel();
      widget.onPaired();
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final uri = _host.pairingUri;
    final got = _host.hasOffer;
    final isError = _host.state == PairingHostState.error;

    return Scaffold(
      backgroundColor: pal.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NqeLogo(scale: 0.5),
                const SizedBox(height: 24),
                Text('Pair with your phone',
                    style: TextStyle(
                        color: pal.textHi,
                        fontSize: 24,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'On your phone open  NQE ▸ Settings ▸ Device Sync ▸ Pair Desktop '
                  'Device  and scan this QR. Your phone stays the source of truth.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pal.textLo, height: 1.5),
                ),
                const SizedBox(height: 28),
                if (isError)
                  _errorBox(pal)
                else if (!got)
                  _waitingView(pal, uri)
                else
                  _codeView(pal),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- waiting: QR + spinner (no address shown) ----
  Widget _waitingView(NqePalette pal, String? uri) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: uri == null
              ? const SizedBox(
                  width: 240,
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                )
              : QrImageView(
                  data: uri,
                  size: 240,
                  backgroundColor: Colors.white,
                  version: QrVersions.auto,
                ),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(pal.textLo)),
            ),
            const SizedBox(width: 10),
            Text('Waiting for your phone to scan…',
                style: TextStyle(color: pal.textLo)),
          ],
        ),
        const SizedBox(height: 8),
        Text('QR refreshes in ${_fmt(_secondsLeft)}',
            style: TextStyle(color: pal.textLo, fontSize: 12)),
      ],
    );
  }

  // ---- after scan: the 6-digit code entry appears ----
  Widget _codeView(NqePalette pal) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.textHi),
          ),
          child: Column(
            children: [
              Text('Enter the 6-digit code shown on your phone',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pal.textLo, fontSize: 13)),
              const SizedBox(height: 14),
              TextField(
                controller: _codeCtrl,
                enabled: !_finishing,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: TextStyle(
                  color: pal.textHi,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 12,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _finishing ? null : _submit,
                  child: _finishing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Pair'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: _finishing ? null : _restart,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to QR (scan again)'),
        ),
        Text('Code expires in ${_fmt(_secondsLeft)}',
            style: TextStyle(color: pal.textLo, fontSize: 12)),
      ],
    );
  }

  Widget _errorBox(NqePalette pal) {
    return Column(
      children: [
        const Icon(Icons.error_outline, size: 44, color: NqeColors.loss),
        const SizedBox(height: 14),
        Text(_host.statusMessage ?? 'Pairing error',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.textLo, height: 1.5)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _restart,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }

  static String _fmt(int s) {
    if (s < 0) s = 0;
    final m = s ~/ 60;
    final r = s % 60;
    if (m > 0) return '${m}m ${r.toString().padLeft(2, '0')}s';
    return '${r}s';
  }
}
