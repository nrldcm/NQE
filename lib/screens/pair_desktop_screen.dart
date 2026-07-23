// Phone-side "Pair Desktop Device". The phone is the server; the desktop
// connects to it. This screen turns on pairing mode, shows the phone's address
// (to type on the desktop if auto-scan doesn't find it), and — once the desktop
// connects — shows the 6-digit code to confirm on the desktop.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sync/sync_server.dart';
import '../theme.dart';

class PairDesktopScreen extends StatefulWidget {
  const PairDesktopScreen({super.key});

  @override
  State<PairDesktopScreen> createState() => _PairDesktopScreenState();
}

class _PairDesktopScreenState extends State<PairDesktopScreen> {
  final _server = SyncServer.instance;

  @override
  void initState() {
    super.initState();
    _server.startPairing();
  }

  @override
  void dispose() {
    // Leave pairing mode but keep the sync server running.
    _server.stopPairing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: const Text('Pair Desktop Device')),
      body: ListenableBuilder(
        listenable: _server,
        builder: (context, _) {
          final code = _server.pairingCode;
          final connected = _server.pairingConnected && code != null;
          final addr = '${_server.host ?? '—'}:${_server.port}';
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _card(pal, [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('On your desktop',
                          style: TextStyle(
                              color: pal.textHi,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                        'Open the NQE desktop app. It searches your Wi-Fi for '
                        'this phone automatically. If it doesn’t find it, type '
                        'this phone’s address below on the desktop.',
                        style: TextStyle(
                            color: pal.textLo, fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 14),
                      _addrRow(pal, addr),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              if (connected)
                _codeCard(pal, code)
              else
                _waitingCard(pal),
              const SizedBox(height: 18),
              Text(
                'Same Wi-Fi required. Encrypted end-to-end · your phone stays '
                'the source of truth.',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.textLo, fontSize: 12, height: 1.4),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _addrRow(NqePalette pal, String addr) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: pal.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              addr,
              style: TextStyle(
                  color: pal.textHi,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy_rounded, size: 20, color: pal.textHi),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: addr));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Address copied')));
            },
          ),
        ],
      ),
    );
  }

  Widget _waitingCard(NqePalette pal) {
    return _card(pal, [
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 16),
            Text('Waiting for the desktop to connect…',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.textLo)),
          ],
        ),
      ),
    ]);
  }

  Widget _codeCard(NqePalette pal, String code) {
    return _card(pal, [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Enter this code on your desktop',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.textLo, fontSize: 14)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: pal.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: pal.textHi),
              ),
              child: Text(
                code,
                style: TextStyle(
                  color: pal.textHi,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Keep this open until the desktop says “Paired”.',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.textLo, fontSize: 12)),
          ],
        ),
      ),
    ]);
  }

  Widget _card(NqePalette pal, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.line),
        ),
        child: Column(children: children),
      );
}
