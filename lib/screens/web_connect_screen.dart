// Browser connect screen (web only). The web app is served BY the phone, so it
// already knows the phone's address (Uri.base) — the user just enters the
// access code shown in the phone's Desktop Mode, and we open a realtime sync
// session. No QR pairing, no local database: the phone stays the source of
// truth. The access code is kept in memory only (never localStorage).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sync/sync_client.dart';
import '../theme.dart';
import '../widgets/nqe_logo.dart';

class WebConnectScreen extends StatefulWidget {
  final VoidCallback onConnected;
  const WebConnectScreen({super.key, required this.onConnected});

  @override
  State<WebConnectScreen> createState() => _WebConnectScreenState();
}

class _WebConnectScreenState extends State<WebConnectScreen> {
  final _code = TextEditingController();
  bool _connecting = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SyncClient.instance.addListener(_onSync);
    // Less-hassle path: if the URL carries the code (e.g. a scanned QR link
    // `…/?code=123456`), prefill it and connect automatically.
    final urlCode = Uri.base.queryParameters['code']?.trim() ?? '';
    if (urlCode.isNotEmpty) {
      _code.text = urlCode;
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
  }

  @override
  void dispose() {
    SyncClient.instance.removeListener(_onSync);
    _code.dispose();
    super.dispose();
  }

  void _onSync() {
    final s = SyncClient.instance.state;
    if (s == SyncConn.connected && !_done) {
      _done = true;
      widget.onConnected();
    } else if (_connecting &&
        (s == SyncConn.disconnected || s == SyncConn.idle)) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = SyncClient.instance.statusMessage;
        });
      }
    }
  }

  Future<void> _connect() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the access code shown on your phone.');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final base = Uri.base; // the phone address that served this page
    await SyncClient.instance.setTargets(
      hosts: [base.host],
      port: base.hasPort ? base.port : 8787,
      key: code,
      persist: false, // session-only: never store the code in the browser
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: NqeLogo(scale: 0.5)),
                  const SizedBox(height: 28),
                  Text('Connect to your phone',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: pal.textHi,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'On your phone open NQE → Settings → Desktop Mode, then '
                    'enter the access code shown there. Your phone stays the '
                    'source of truth; this browser holds no data.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: pal.textLo, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    enabled: !_connecting,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    style: const TextStyle(
                        fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                    onSubmitted: (_) => _connect(),
                    decoration: InputDecoration(
                      labelText: '6-digit access code',
                      counterText: '',
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _connecting ? null : _connect,
                      icon: _connecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.link),
                      label: Text(_connecting ? 'Connecting…' : 'Connect'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Phone: ${Uri.base.host}:${Uri.base.hasPort ? Uri.base.port : 8787}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: pal.textLo, fontSize: 11),
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
