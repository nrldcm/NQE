// Desktop-side pairing — the desktop connects OUT to the phone over plain HTTP.
//
// Why outbound: a locked-down laptop's firewall blocks INBOUND connections
// (approving needs admin), so the desktop must be the one that reaches the
// phone (which runs the server — Android allows inbound).
//
// Why HTTP (not WebSocket): pairing is just two request/response round-trips.
// HttpClient with explicit timeouts is rock-solid across platforms and can
// never hang, unlike a desktop WebSocket handshake.
//
// Flow:
//   1. Desktop finds the phone — LAN auto-scan (GET <subnet>.*:port/nqe) or a
//      typed IP.
//   2. POST /pair/hello {pub}  → phone returns {sid, phonePub}; both derive the
//      shared key + the 6-digit code. The phone shows the code.
//   3. The human types the code into the desktop; on a local match the desktop
//      POST /pair/confirm → phone returns the sealed {sync endpoint + key + PIN}.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'net_util.dart';
import 'pairing.dart';

enum DesktopPairState {
  idle,
  scanning,
  connecting,
  awaitingCode,
  verifying,
  paired,
  error,
}

class DesktopPairing extends ChangeNotifier {
  DesktopPairState state = DesktopPairState.idle;
  String? message;
  List<String> found = [];

  PairingKeys? _keys;
  String? _sid;
  String? _phonePubB64;
  String? _expectedCode;
  bool _cancelled = false;

  /// The 6-digit code to DISPLAY on the desktop. The human compares it with the
  /// code on the phone and taps Approve on the phone. Same value the phone
  /// computes (shortCode over both public keys).
  String? get code => _expectedCode;

  @visibleForTesting
  String? get expectedCode => _expectedCode;

  /// Stop an in-flight approval poll (e.g. the user tapped Back).
  void cancel() {
    _cancelled = true;
  }

  /// Scan the local network(s) for a phone running the NQE sync server on
  /// [port]. Returns reachable phone IPs (also stored in [found]).
  Future<List<String>> discover(int port) async {
    _set(DesktopPairState.scanning, 'Searching your network for the phone…');
    final hits = <String>[];
    try {
      final prefixes = await _localSubnets();
      for (final prefix in prefixes) {
        final batch = <Future<void>>[];
        for (var i = 1; i <= 254; i++) {
          final ip = '$prefix.$i';
          batch.add(_probe(ip, port).then((ok) {
            if (ok && !hits.contains(ip)) hits.add(ip);
          }));
          if (batch.length >= 64) {
            await Future.wait(batch);
            batch.clear();
          }
        }
        await Future.wait(batch);
      }
    } catch (_) {
      // Best-effort; the user can still type the IP.
    }
    found = hits;
    // Don't clobber a connect that may have started; only settle if still
    // scanning.
    if (state == DesktopPairState.scanning) {
      _set(
        DesktopPairState.idle,
        hits.isEmpty
            ? 'No phone found. Check both are on the same Wi-Fi, then type the '
                'phone’s IP (NQE ▸ Settings ▸ Device Sync shows it).'
            : 'Found ${hits.length} device(s).',
      );
    }
    return hits;
  }

  Future<bool> _probe(String ip, int port) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 350);
      final req = await client
          .get(ip, port, '/nqe')
          .timeout(const Duration(milliseconds: 700));
      final resp = await req.close().timeout(const Duration(milliseconds: 700));
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 1));
      return body.trim() == 'NQE';
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  /// Full pairing: connect (hello), then show the 6-digit code and POLL the
  /// phone until the human taps Approve there — only then does the phone release
  /// the sealed payload, which we open and return. Returns null on failure /
  /// timeout / cancel. The approval-on-phone gate is the security boundary: a
  /// LAN client that never got the human's tap can never obtain the secrets.
  Future<PairingPayload?> pair(
    String host,
    int port, {
    Duration pollInterval = const Duration(milliseconds: 1200),
    int maxPolls = 100,
  }) async {
    _cancelled = false;
    _set(DesktopPairState.connecting, 'Connecting to $host:$port…');
    try {
      _keys = await Pairing.generateKeys();
      final hello = await _postJson(
          host, port, '/pair/hello', {'pub': _keys!.publicKeyB64});
      if (hello == null) {
        _set(DesktopPairState.error,
            'Could not reach the phone at $host:$port. Same Wi-Fi? Is “LAN Sync Server” on?');
        return null;
      }
      if (hello['error'] != null || hello['phonePub'] == null) {
        _set(DesktopPairState.error,
            'Phone isn’t ready to pair. On the phone open NQE ▸ Settings ▸ Device Sync ▸ Pair Desktop Device, then try again.');
        return null;
      }
      _sid = hello['sid'].toString();
      _phonePubB64 = hello['phonePub'].toString();
      final phonePub = Pairing.publicKeyFromB64(_phonePubB64!);
      _expectedCode = await Pairing.shortCode(
        sid: _sid!,
        desktopPub: _keys!.publicKey,
        phonePub: phonePub,
      );
      _set(DesktopPairState.awaitingCode,
          'Check the 6-digit code matches your phone, then tap Approve on the phone.');

      // Poll /pair/confirm until approved (200 payload), waiting (202), or we
      // give up. ~120s window; the phone releases only after the human approves.
      final shared = await Pairing.deriveSharedKey(
        myKeyPair: _keys!.keyPair,
        peerPublicKey: phonePub,
        sid: _sid!,
      );
      for (var i = 0; i < maxPolls; i++) {
        if (_cancelled) {
          _set(DesktopPairState.idle, null);
          return null;
        }
        final resp = await _postJson(host, port, '/pair/confirm', const {});
        if (resp != null && resp['payload'] != null) {
          final payload = await Pairing.openPayload(
              sharedKey: shared, blobB64: resp['payload'].toString());
          _set(DesktopPairState.paired, 'Paired.');
          return payload;
        }
        // 202 waiting / transient error → wait and poll again.
        await Future<void>.delayed(pollInterval);
      }
      _set(DesktopPairState.error,
          'Timed out waiting for approval on the phone. Try again.');
      return null;
    } catch (e) {
      _set(DesktopPairState.error, 'Pairing failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _postJson(
      String host, int port, String path, Map<String, dynamic> body) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await client
          .postUrl(Uri.parse('http://$host:$port$path'))
          .timeout(const Duration(seconds: 6));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final text = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));
      if (text.trim().isEmpty) return <String, dynamic>{};
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  void _set(DesktopPairState s, String? m) {
    state = s;
    message = m;
    notifyListeners();
  }

  /// Local /24 subnet prefixes (e.g. "192.168.1"), skipping virtual adapters.
  Future<List<String>> _localSubnets() async {
    final prefixes = <String>[];
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final ni in ifaces) {
        if (isVirtualAdapter(ni.name)) continue;
        for (final a in ni.addresses) {
          final ip = a.address;
          if (!_isPrivate(ip)) continue;
          final parts = ip.split('.');
          if (parts.length == 4) {
            final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
            if (!prefixes.contains(prefix)) prefixes.add(prefix);
          }
        }
      }
    } catch (_) {/* ignore */}
    return prefixes;
  }

  bool _isPrivate(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      final b = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return b >= 16 && b <= 31;
    }
    return false;
  }
}
