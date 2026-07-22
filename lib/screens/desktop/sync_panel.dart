// Desktop pairing / status panel. Reflects the live [SyncClient] state and lets
// the user pair by pasting the mobile app's `nqe://sync?…` URI (scanned from its
// QR), then reconnect if the link drops. The phone stays the source of truth;
// this panel only drives the desktop's client connection.
import 'package:flutter/material.dart';

import '../../sync/sync_client.dart';
import '../../theme.dart';
import '../../widgets/connection_watcher.dart';

class SyncPanel extends StatefulWidget {
  const SyncPanel({super.key});

  @override
  State<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends State<SyncPanel> {
  final _client = SyncClient.instance;
  final _uriController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill with the last paired URI, if any, for a one-click reconnect.
    final last = _client.lastUri;
    if (last != null && last.isNotEmpty) _uriController.text = last;
  }

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final text = _uriController.text.trim();
    if (text.isEmpty) return;
    await _client.pair(text);
  }

  Future<void> _reconnect() async {
    await _client.reconnect();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return ListenableBuilder(
      listenable: _client,
      builder: (context, _) {
        final disconnected = _client.state == SyncConn.disconnected;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Device Sync',
                    style: TextStyle(
                      color: pal.textHi,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your phone runs the sync server. This desktop connects to '
                    'it over your local network and keeps its ledger in sync.',
                    style: TextStyle(
                        color: pal.textLo, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 28),

                  // Big, centered live status readout.
                  Center(
                    child: ConnectionWatcher(
                      _client.state,
                      attempt: _client.attempt,
                    ),
                  ),
                  if (_client.statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _client.statusMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: pal.textLo, fontSize: 12, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 28),

                  // Reconnect banner when the link has given up.
                  if (disconnected) ...[
                    _card(pal, [
                      Text(
                        'The connection was lost.',
                        style: TextStyle(
                          color: pal.textHi,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Retry the last link, or paste a fresh one below if your '
                        'phone restarted the server (new QR).',
                        style: TextStyle(
                            color: pal.textLo, fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _reconnect,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Reconnect'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                  ],

                  // Paste-URI pairing field — always available so the user can
                  // re-scan the mobile QR and paste a new link at any time.
                  _card(pal, [
                    Text(
                      'Pairing link',
                      style: TextStyle(
                        color: pal.textHi,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Scan the QR in the phone\'s Device Sync screen and paste '
                      'its nqe://sync link here.',
                      style: TextStyle(
                          color: pal.textLo, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _uriController,
                      style: TextStyle(color: pal.textHi, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'nqe://sync?host=…&port=…&key=…',
                      ),
                      onSubmitted: (_) => _pair(),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _pair,
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('Connect / Pair'),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 24),
                  Text(
                    'Local network only · encrypted · your phone is the source '
                    'of truth. Edits on either device converge automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: pal.textLo, fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card(NqePalette pal, List<Widget> children) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}
