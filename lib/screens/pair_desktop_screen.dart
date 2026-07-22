// Phone-side "Pair Desktop Device": open the camera, scan the desktop's QR,
// run the secure handshake, then show the 6-digit code to type on the desktop.
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../sync/pairing_client.dart';
import '../theme.dart';

enum _Phase { scanning, working, done, failed }

class PairDesktopScreen extends StatefulWidget {
  const PairDesktopScreen({super.key});

  @override
  State<PairDesktopScreen> createState() => _PairDesktopScreenState();
}

class _PairDesktopScreenState extends State<PairDesktopScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  _Phase _phase = _Phase.scanning;
  String _message = '';
  String? _code;
  bool _handled = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null || !raw.startsWith('nqe://pair')) return;
    _handled = true;
    try {
      await _scanner.stop();
    } catch (_) {/* ignore */}
    setState(() {
      _phase = _Phase.working;
      _message = 'Securing connection…';
    });

    final res = await PairingClient.run(raw);
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        _phase = _Phase.done;
        _code = res.code;
        _message = res.message;
      } else {
        _phase = _Phase.failed;
        _message = res.message;
      }
    });
  }

  Future<void> _rescan() async {
    _handled = false;
    setState(() {
      _phase = _Phase.scanning;
      _message = '';
      _code = null;
    });
    try {
      await _scanner.start();
    } catch (_) {/* ignore */}
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: const Text('Pair Desktop Device')),
      body: switch (_phase) {
        _Phase.scanning => _scanView(pal),
        _Phase.working => _busyView(pal),
        _Phase.done => _codeView(pal),
        _Phase.failed => _failView(pal),
      },
    );
  }

  Widget _scanView(NqePalette pal) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _scanner, onDetect: _onDetect),
              // Simple viewfinder overlay.
              Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          color: pal.surface,
          padding: const EdgeInsets.all(20),
          child: Text(
            'Open the NQE desktop app and scan the QR it shows. Your phone stays '
            'the source of truth.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.textLo, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _busyView(NqePalette pal) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(_message, style: TextStyle(color: pal.textLo)),
        ],
      ),
    );
  }

  Widget _codeView(NqePalette pal) {
    final code = _code ?? '------';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.desktop_windows_outlined, size: 48, color: pal.textHi),
            const SizedBox(height: 20),
            Text('Enter this code on your desktop',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.textLo, fontSize: 14)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
              decoration: BoxDecoration(
                color: pal.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: pal.textHi),
              ),
              child: Text(
                code,
                style: TextStyle(
                  color: pal.textHi,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 14,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Keep this screen open until the desktop says “Paired”. The two '
              'devices will then sync automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.textLo, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.check),
              label: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _failView(NqePalette pal) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: NqeColors.loss),
            const SizedBox(height: 18),
            Text(_message,
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.textLo, height: 1.5)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _rescan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan again'),
            ),
          ],
        ),
      ),
    );
  }
}
