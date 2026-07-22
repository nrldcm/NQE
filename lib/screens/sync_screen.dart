// Device Sync: run the phone as a LAN sync server and pair the NQE desktop app
// by scanning the QR. The phone is the source of truth; the desktop connects as
// a client. All state comes from SyncServer.instance (Module B).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../sync/sync_server.dart';
import '../theme.dart';
import '../widgets/connection_status.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _server = SyncServer.instance;
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (on) {
        await _server.start();
      } else {
        await _server.stop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Sync error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: const Text('Device Sync')),
      body: ListenableBuilder(
        listenable: _server,
        builder: (context, _) {
          final running = _server.status == SyncStatus.running;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _card(pal, [
                SwitchListTile(
                  secondary: Icon(Icons.wifi_tethering, color: pal.textHi),
                  title:
                      Text('LAN sync server', style: TextStyle(color: pal.textHi)),
                  subtitle: Text(
                    running
                        ? 'Running — desktop can connect'
                        : 'Off — turn on to allow the desktop to pair',
                    style: TextStyle(color: pal.textLo, fontSize: 12),
                  ),
                  value: running,
                  onChanged: _busy ? null : _toggle,
                ),
              ]),
              const SizedBox(height: 16),
              if (_busy && !running)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (running) ...[
                _card(pal, [
                  _kv(pal, 'Address',
                      '${_server.host ?? '—'}:${_server.port}'),
                  _divider(pal),
                  _kv(pal, 'Connected peers', '${_server.connectedPeers}'),
                ]),
                const SizedBox(height: 16),
                _qrCard(pal),
                const SizedBox(height: 16),
              ],
              ConnectionStatusBanner(_server.peer),
              const SizedBox(height: 16),
              Text(
                'Local network only · encrypted · your phone is the source of truth.',
                style: TextStyle(
                    color: pal.textLo, fontSize: 12, height: 1.4),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _qrCard(NqePalette pal) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        children: [
          // White backdrop so the code scans in dark mode too.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: _server.pairingUri,
              size: 220,
              backgroundColor: Colors.white,
              version: QrVersions.auto,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Scan this from the NQE desktop app to pair',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.textLo, fontSize: 13),
          ),
          const SizedBox(height: 14),
          _pairingLink(pal),
        ],
      ),
    );
  }

  /// Copyable pairing URI for desktops where scanning the QR isn't handy.
  Widget _pairingLink(NqePalette pal) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: pal.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SelectableText(
              _server.pairingUri,
              style: TextStyle(
                color: pal.textHi,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy_rounded, size: 20, color: pal.textHi),
            tooltip: 'Copy link',
            onPressed: _copyPairingUri,
          ),
        ],
      ),
    );
  }

  Future<void> _copyPairingUri() async {
    await Clipboard.setData(ClipboardData(text: _server.pairingUri));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pairing link copied')),
    );
  }

  Widget _kv(NqePalette pal, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(k, style: TextStyle(color: pal.textLo, fontSize: 13)),
            ),
            Text(
              v,
              style: TextStyle(
                color: pal.textHi,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );

  Widget _card(NqePalette pal, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.line),
        ),
        child: Column(children: children),
      );

  Widget _divider(NqePalette pal) =>
      Divider(height: 1, color: pal.line, indent: 16, endIndent: 16);
}
