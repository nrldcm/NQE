// Desktop first-run pairing: show a QR the phone scans, then confirm with the
// 6-digit code the phone displays. On success the desktop adopts the phone's
// sync endpoint + PIN and moves on to the shell.
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

  @override
  void initState() {
    super.initState();
    _host.addListener(_onHost);
    _host.start();
  }

  void _onHost() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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
      // Adopt the phone's PIN so the desktop unlocks with the same PIN.
      if (payload.hasPin) {
        await AuthService.instance.importPinCredential(
          hash: payload.pinHash!,
          salt: payload.pinSalt!,
          len: payload.pinLen,
        );
      }
      // Save the sync target and start syncing.
      await SyncClient.instance.setTarget(
        host: payload.syncHost,
        port: payload.syncPort,
        key: payload.syncKey,
      );
      try {
        await appState.load();
      } catch (_) {/* non-fatal */}
      if (!mounted) return;
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
    final waiting = _host.state == PairingHostState.listening;
    final got = _host.hasOffer;

    return Scaffold(
      backgroundColor: pal.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
                _qr(pal, uri),
                const SizedBox(height: 24),
                if (uri != null) _uriLine(pal, uri),
                const SizedBox(height: 28),
                _codeBox(pal, got),
                const SizedBox(height: 16),
                if (waiting && !got)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(pal.textLo)),
                      ),
                      const SizedBox(width: 10),
                      Text('Waiting for your phone to scan…',
                          style: TextStyle(color: pal.textLo)),
                    ],
                  ),
                if (_host.state == PairingHostState.error)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_host.statusMessage ?? 'Pairing error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: NqeColors.loss)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _qr(NqePalette pal, String? uri) {
    return Container(
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
    );
  }

  Widget _uriLine(NqePalette pal, String uri) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: pal.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              uri,
              style: TextStyle(
                  color: pal.textLo,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.3),
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy_rounded, size: 18, color: pal.textLo),
            tooltip: 'Copy link',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: uri));
              _snack('Pairing link copied');
            },
          ),
        ],
      ),
    );
  }

  Widget _codeBox(NqePalette pal, bool enabled) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: enabled ? pal.textHi : pal.line),
      ),
      child: Column(
        children: [
          Text(
            enabled
                ? 'Enter the 6-digit code shown on your phone'
                : 'The 6-digit code appears here after your phone scans',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.textLo, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _codeCtrl,
            enabled: enabled && !_finishing,
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
              onPressed: (enabled && !_finishing) ? _submit : null,
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
    );
  }
}
