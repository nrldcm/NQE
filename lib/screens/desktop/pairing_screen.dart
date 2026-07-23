// Desktop first-run pairing (outbound, scan-first). The desktop auto-finds the
// phone on the Wi-Fi and connects OUT to it — so a firewalled laptop that can't
// accept inbound still works. No IP/port typing needed for normal use; power
// users can press F12 to set a custom port, or expand "Enter manually".
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../sync/net_util.dart';
import '../../sync/pairing_desktop.dart';
import '../../sync/sync_client.dart';
import '../../theme.dart';
import '../../widgets/nqe_logo.dart';

class DesktopPairingScreen extends StatefulWidget {
  final VoidCallback onPaired;
  const DesktopPairingScreen({super.key, required this.onPaired});

  @override
  State<DesktopPairingScreen> createState() => _DesktopPairingScreenState();
}

class _DesktopPairingScreenState extends State<DesktopPairingScreen> {
  final _pairing = DesktopPairing();
  final _ipCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  int _port = 8787;
  bool _manual = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pairing.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pairing.removeListener(_onChange);
    _pairing.dispose();
    _ipCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final hits = await _pairing.discover(_port);
    if (!mounted) return;
    // Exactly one phone → connect straight away (no tapping needed).
    if (hits.length == 1) _connect(hits.first);
  }

  Future<void> _connect(String host) async {
    if (host.trim().isEmpty) return;
    await _pairing.connect(host.trim(), _port);
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      _snack('Enter the 6-digit code shown on your phone.');
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = await _pairing.submitCode(code);
      if (payload == null) {
        _snack(_pairing.message ?? 'Incorrect code.');
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
      widget.onPaired();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPortDialog() async {
    final pal = context.nqe;
    final ctrl = TextEditingController(text: _port.toString());
    final res = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: pal.surface,
        title: Text('Custom port', style: TextStyle(color: pal.textHi)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The port your phone’s LAN Sync Server uses (Settings ▸ Device '
              'Sync ▸ Sync port). Default is 8787.',
              style: TextStyle(color: pal.textLo, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  const InputDecoration(labelText: 'Port (1024–65535)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, int.tryParse(ctrl.text.trim())),
              child: const Text('Apply')),
        ],
      ),
    );
    if (res == null) return;
    setState(() => _port = sanitizePort(res, fallback: 8787));
    _scan();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final st = _pairing.state;
    final awaiting = st == DesktopPairState.awaitingCode ||
        st == DesktopPairState.verifying;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f12): () {
          _showPortDialog();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
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
                      'On your phone open  NQE ▸ Settings ▸ Device Sync,  turn on '
                      'LAN Sync Server, then tap Pair Desktop Device. This desktop '
                      'finds your phone automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: pal.textLo, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    if (awaiting) _codeCard(pal) else _findCard(pal),
                    if (_pairing.message != null) ...[
                      const SizedBox(height: 14),
                      Text(_pairing.message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: st == DesktopPairState.error
                                  ? NqeColors.loss
                                  : pal.textLo,
                              fontSize: 12)),
                    ],
                    const SizedBox(height: 10),
                    Text('Port $_port · press F12 to change',
                        style: TextStyle(color: pal.textLo, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _findCard(NqePalette pal) {
    final scanning = _pairing.state == DesktopPairState.scanning ||
        _pairing.state == DesktopPairState.connecting;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        children: [
          if (scanning) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Text(
                  _pairing.state == DesktopPairState.connecting
                      ? 'Connecting…'
                      : 'Searching your Wi-Fi for your phone…',
                  style: TextStyle(color: pal.textHi),
                ),
              ],
            ),
          ] else if (_pairing.found.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Tap your phone to connect:',
                  style: TextStyle(color: pal.textLo, fontSize: 13)),
            ),
            const SizedBox(height: 10),
            ..._pairing.found.map((ip) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _connect(ip),
                      icon: const Icon(Icons.smartphone),
                      label: Text(ip),
                    ),
                  ),
                )),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Search again'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.wifi_find),
              label: const Text('Search for my phone'),
            ),
          ],
          // Manual entry, tucked away for the non-technical default.
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() => _manual = !_manual),
            child: Text(_manual ? 'Hide manual entry' : 'Enter phone IP manually',
                style: TextStyle(color: pal.textLo, fontSize: 12)),
          ),
          if (_manual)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Phone IP',
                      hintText: 'e.g. 192.168.1.71',
                    ),
                    onSubmitted: (v) => _connect(v),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: scanning ? null : () => _connect(_ipCtrl.text),
                  child: const Text('Connect'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _codeCard(NqePalette pal) {
    return Container(
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
            enabled: !_busy,
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
            decoration:
                const InputDecoration(counterText: '', hintText: '••••••'),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _verify,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Pair'),
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back / find another device'),
          ),
        ],
      ),
    );
  }
}
