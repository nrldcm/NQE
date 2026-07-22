// Desktop-side pairing host.
//
// The desktop shows a QR and briefly runs a tiny WebSocket listener so the
// phone (which scanned the QR) can hand over the sealed pairing payload. The
// actual trust decision is the human typing the phone's 6-digit code into the
// desktop — see [verifyCodeAndFinish]. All the cryptography lives in
// [Pairing]; this class only moves bytes and tracks UI state.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' show SimplePublicKey;
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'pairing.dart';

enum PairingHostState { idle, listening, received, verifying, paired, error }

/// One offer received from a phone: its public key + the sealed blob. The
/// desktop keeps the most recent offer and tests the typed code against it.
class _Offer {
  final String sid;
  final SimplePublicKey phonePub;
  final String blob;
  _Offer(this.sid, this.phonePub, this.blob);
}

class PairingHost extends ChangeNotifier {
  PairingHost();

  /// Desktop pairing port (distinct from the sync port 8787).
  static const int port = 8788;

  PairingHostState state = PairingHostState.idle;
  String? statusMessage;

  String? _sid;
  PairingKeys? _keys;
  String? _lanIp;
  HttpServer? _server;
  _Offer? _offer;

  /// The QR content shown on the desktop and scanned by the phone.
  /// `nqe://pair?host=<lanIp>&port=<port>&sid=<sid>&pk=<desktopPubKey>`
  String? get pairingUri {
    final ip = _lanIp, sid = _sid, keys = _keys;
    if (ip == null || sid == null || keys == null) return null;
    return 'nqe://pair?host=$ip&port=$port&sid=$sid&pk=${keys.publicKeyB64}';
  }

  bool get hasOffer => _offer != null;

  /// Start listening: pick a LAN IP, mint an ephemeral key pair + session id,
  /// and bind the pairing WebSocket. Safe to call again to restart a session.
  Future<void> start() async {
    await stop();
    try {
      _lanIp = await _resolveLanIp();
      if (_lanIp == null) {
        _set(PairingHostState.error,
            'No local network address found. Connect to Wi-Fi/LAN and retry.');
        return;
      }
      _keys = await Pairing.generateKeys();
      _sid = _randomSid();

      final handler = _buildHandler();
      _server = await shelf_io.serve(handler, '0.0.0.0', port);
      _server!.autoCompress = true;
      _set(PairingHostState.listening,
          'Scan this QR from your phone (NQE ▸ Settings ▸ Pair Desktop Device).');
    } catch (e) {
      _set(PairingHostState.error, 'Could not start pairing: $e');
    }
  }

  /// Tear down the listener. Called on cancel and after a successful pairing.
  Future<void> stop() async {
    try {
      await _server?.close(force: true);
    } catch (_) {
      // ignore — tearing down
    }
    _server = null;
  }

  Handler _buildHandler() {
    final ws = webSocketHandler((WebSocketChannel channel, String? _) {
      _handle(channel);
    });
    return (Request request) {
      if (request.url.path == 'pair') return ws(request);
      return Response.notFound('NQE pairing');
    };
  }

  void _handle(WebSocketChannel channel) {
    StreamSubscription? sub;
    sub = channel.stream.listen(
      (dynamic message) {
        try {
          final frame = message is String ? message : message.toString();
          final map = jsonDecode(frame) as Map<String, dynamic>;
          if ((map['sid'] ?? '') != _sid) return; // stale / wrong session
          final phonePub = Pairing.publicKeyFromB64((map['pk'] ?? '').toString());
          final blob = (map['blob'] ?? '').toString();
          if (blob.isEmpty) return;
          _offer = _Offer(_sid!, phonePub, blob);
          _set(PairingHostState.received,
              'Phone connected. Enter the 6-digit code shown on your phone.');
          // Acknowledge so the phone can show "connected".
          try {
            channel.sink.add(jsonEncode({'ack': true}));
          } catch (_) {/* ignore */}
        } catch (_) {
          // Ignore malformed frames — a wrong-app connection can't pair.
        }
      },
      onError: (Object _) => sub?.cancel(),
      onDone: () => sub?.cancel(),
      cancelOnError: true,
    );
  }

  /// Verify the typed 6-digit code against the current offer and, on a match,
  /// open the sealed payload. Returns the payload on success, or null if there
  /// is no offer / the code is wrong / the blob fails authentication.
  Future<PairingPayload?> verifyCodeAndFinish(String code) async {
    final offer = _offer;
    final keys = _keys;
    final sid = _sid;
    if (offer == null || keys == null || sid == null) return null;
    _set(PairingHostState.verifying, 'Verifying…');
    try {
      final expected = await Pairing.shortCode(
        sid: sid,
        desktopPub: keys.publicKey,
        phonePub: offer.phonePub,
      );
      if (code.trim() != expected) {
        _set(PairingHostState.received, 'Incorrect code — check your phone and retry.');
        return null;
      }
      final shared = await Pairing.deriveSharedKey(
        myKeyPair: keys.keyPair,
        peerPublicKey: offer.phonePub,
        sid: sid,
      );
      final payload =
          await Pairing.openPayload(sharedKey: shared, blobB64: offer.blob);
      _set(PairingHostState.paired, 'Paired.');
      await stop();
      return payload;
    } catch (e) {
      // GCM auth failure or malformed payload → treat as a rejected attempt.
      _set(PairingHostState.received,
          'Could not verify. Re-scan the QR and try again.');
      return null;
    }
  }

  // --- helpers ---------------------------------------------------------------

  void _set(PairingHostState s, String? msg) {
    state = s;
    statusMessage = msg;
    notifyListeners();
  }

  String _randomSid() {
    // 16 random bytes from a cryptographic source via the key material we just
    // generated is overkill; derive a compact session id from the public key.
    final pk = _keys?.publicKeyB64 ?? '';
    final tail = pk.length >= 16 ? pk.substring(0, 16) : pk;
    // Mix in the port/time-free constant; sid need not be secret, only unique
    // enough for one pairing window. The public key already varies per session.
    return base64Url.encode(utf8.encode(tail)).replaceAll('=', '');
  }

  /// Find a private IPv4 address for the desktop on the LAN. Prefers common
  /// home-network ranges and skips loopback / link-local.
  Future<String?> _resolveLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      String? fallback;
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
          fallback ??= ip;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              _is172Private(ip)) {
            return ip;
          }
        }
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  bool _is172Private(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? 0;
    return second >= 16 && second <= 31;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
