// Desktop first-run pairing (outbound). The desktop finds the phone on the LAN
// (auto-scan or a typed IP), connects OUT to it — so a firewalled laptop that
// can't accept inbound still works — then confirms with the 6-digit code the
// phone shows. On success it adopts the phone's sync endpoint + PIN.
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
  final _portCtrl = TextEditingController(text: '8787');
  final _codeCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pairing.addListener(_onChange);
    // Kick off an auto-scan so the user usually doesn't type anything.
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
    _portCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  int get _port => sanitizePort(int.tryParse(_portCtrl.text.trim()) ?? 8787);

  Future<void> _scan() async {
    final hits = await _pairing.discover(_port);
    if (!mounted) return;
    if (hits.length == 1) {
      _ipCtrl.text = hits.first;
      _connect(hits.first);
    } else if (hits.isNotEmpty) {
      _ipCtrl.text = hits.first;
    }
  }

  Future<void> _connect(String host) async {
    if (host.trim().isEmpty) {
      _snack('Enter your phone’s IP (see NQE ▸ Settings ▸ Device Sync).');
      return;
    }
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
                  'On your phone open  NQE ▸ Settings ▸ Device Sync,  turn on '
                  'LAN Sync Server, then tap Pair Desktop Device. This desktop '
                  'finds your phone and connects to it.',
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
              ],
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
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _ipCtrl,
                  enabled: !scanning,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'Phone IP',
                    hintText: 'e.g. 192.168.1.71',
                  ),
                  onSubmitted: (v) => _connect(v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _portCtrl,
                  enabled: !scanning,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_pairing.found.length > 1) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Found devices — tap to connect:',
                  style: TextStyle(color: pal.textLo, fontSize: 12)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _pairing.found
                  .map((ip) => ActionChip(
                        label: Text(ip),
                        onPressed: scanning ? null : () => _connect(ip),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: scanning ? null : _scan,
                  icon: scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_find),
                  label: Text(scanning ? 'Searching…' : 'Search again'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: scanning ? null : () => _connect(_ipCtrl.text),
                  icon: const Icon(Icons.link),
                  label: const Text('Connect'),
                ),
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
            onPressed: _busy ? null : () => _scan(),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back / find another device'),
          ),
        ],
      ),
    );
  }
}
