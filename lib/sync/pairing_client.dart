// Phone-side pairing client.
//
// After the phone scans the desktop's QR, this runs the phone half of the
// SAS-authenticated handshake: derive the shared key, seal the sync/PIN payload
// (from [SyncServer.buildPairingPayload]) and push it to the desktop, then
// surface the 6-digit code the user types into the desktop to confirm.
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'pairing.dart';
import 'sync_server.dart';

class PairingResult {
  final bool ok;
  final String? code; // the 6-digit code to type on the desktop
  final String message;
  const PairingResult({required this.ok, this.code, required this.message});
}

class PairingClient {
  /// Run the phone half of pairing for a scanned `nqe://pair?...` URI.
  static Future<PairingResult> run(String scannedUri) async {
    final target = _parse(scannedUri);
    if (target == null) {
      return const PairingResult(
          ok: false, message: 'That QR is not an NQE desktop pairing code.');
    }

    // The phone must be reachable as the sync server, and we need its endpoint
    // + key + PIN to hand over. buildPairingPayload starts the server if needed.
    final payload = await SyncServer.instance.buildPairingPayload();
    if (payload == null) {
      return const PairingResult(
          ok: false,
          message:
              'Could not start the sync server. Make sure Wi-Fi is on, then retry.');
    }

    try {
      final desktopPub = Pairing.publicKeyFromB64(target.pk);
      final myKeys = await Pairing.generateKeys();
      final shared = await Pairing.deriveSharedKey(
        myKeyPair: myKeys.keyPair,
        peerPublicKey: desktopPub,
        sid: target.sid,
      );
      // Fixed order (desktop, phone) so both sides compute the same code.
      final code = await Pairing.shortCode(
        sid: target.sid,
        desktopPub: desktopPub,
        phonePub: myKeys.publicKey,
      );
      final blob = await Pairing.sealPayload(sharedKey: shared, payload: payload);

      final uri = Uri.parse('ws://${target.host}:${target.port}/pair');
      final channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 8));

      channel.sink.add(jsonEncode({
        'sid': target.sid,
        'pk': myKeys.publicKeyB64,
        'blob': blob,
      }));

      // Best-effort wait for the desktop's ack, then close. The desktop already
      // holds the sealed blob; the user confirms by typing the code.
      try {
        await channel.stream.first.timeout(const Duration(seconds: 5));
      } catch (_) {
        // No ack isn't fatal — the blob was sent.
      }
      try {
        await channel.sink.close();
      } catch (_) {/* ignore */}

      return PairingResult(
        ok: true,
        code: code,
        message: 'Enter this code on your desktop to finish pairing.',
      );
    } catch (e) {
      return PairingResult(
          ok: false, message: 'Could not reach the desktop: $e');
    }
  }

  static _Target? _parse(String raw) {
    try {
      final uri = Uri.parse(raw.trim());
      if (uri.scheme != 'nqe' || uri.host != 'pair') {
        // Also accept nqe://pair?... where 'pair' is the host component.
        if (!(uri.scheme == 'nqe' && uri.path.contains('pair')) &&
            uri.host != 'pair') {
          return null;
        }
      }
      final host = uri.queryParameters['host'] ?? '';
      final port = int.tryParse(uri.queryParameters['port'] ?? '');
      final sid = uri.queryParameters['sid'] ?? '';
      final pk = uri.queryParameters['pk'] ?? '';
      if (host.isEmpty || port == null || sid.isEmpty || pk.isEmpty) return null;
      return _Target(host: host, port: port, sid: sid, pk: pk);
    } catch (_) {
      return null;
    }
  }
}

class _Target {
  final String host;
  final int port;
  final String sid;
  final String pk;
  const _Target(
      {required this.host,
      required this.port,
      required this.sid,
      required this.pk});
}
