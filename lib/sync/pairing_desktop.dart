// Desktop-side pairing — the desktop connects OUT to the phone.
//
// Why outbound: a locked-down laptop's firewall blocks INBOUND connections
// (approving needs admin), so the desktop can never reliably accept the phone
// connecting to it. Outbound connections are not blocked, so the desktop is the
// one that reaches the phone (which runs the server — Android allows inbound).
//
// Flow (mirrors the SAS handshake, direction reversed):
//   1. Desktop finds the phone — LAN auto-scan (probe <subnet>.*:port/nqe) or a
//      manually typed IP.
//   2. Desktop opens ws://phone:port/pair, sends its ephemeral public key.
//   3. Phone replies with its public key + session id; both derive the shared
//      key and the 6-digit code. The phone shows the code.
//   4. The human types that code into the desktop; the desktop verifies it
//      equals its own computed code, then asks the phone for the sealed payload
//      (sync endpoint + key + PIN) and opens it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  PairingKeys? _keys;
  String? _sid;
  String? _phonePubB64;
  String? _expectedCode;
  final _payloadCompleter = <Completer<String>>[];

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
      // Scan best-effort; the user can still type the IP.
    }
    found = hits;
    _set(
      hits.isEmpty ? DesktopPairState.idle : DesktopPairState.idle,
      hits.isEmpty
          ? 'No phone found. Check you are on the same Wi-Fi, then enter the '
              'phone’s IP shown in NQE ▸ Settings ▸ Device Sync.'
          : 'Found ${hits.length} device(s).',
    );
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

  /// Connect to the phone at [host]:[port] and run the key exchange. On success
  /// the state becomes [DesktopPairState.awaitingCode] and the caller should
  /// prompt for the 6-digit code shown on the phone.
  Future<bool> connect(String host, int port) async {
    await _teardown();
    _set(DesktopPairState.connecting, 'Connecting to $host:$port…');
    try {
      _keys = await Pairing.generateKeys();
      final channel =
          WebSocketChannel.connect(Uri.parse('ws://$host:$port/pair'));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 8));

      final firstFrame = Completer<Map<String, dynamic>>();
      _sub = channel.stream.listen(
        (dynamic msg) {
          try {
            final map = jsonDecode(
                    msg is String ? msg : msg.toString()) as Map<String, dynamic>;
            if (!firstFrame.isCompleted && map['phonePub'] != null) {
              firstFrame.complete(map);
            } else if (map['payload'] != null && _payloadCompleter.isNotEmpty) {
              final c = _payloadCompleter.removeAt(0);
              if (!c.isCompleted) c.complete(map['payload'].toString());
            } else if (map['error'] != null) {
              if (!firstFrame.isCompleted) {
                firstFrame.completeError(map['error'].toString());
              }
              if (_payloadCompleter.isNotEmpty) {
                final c = _payloadCompleter.removeAt(0);
                if (!c.isCompleted) c.completeError(map['error'].toString());
              }
            }
          } catch (_) {/* ignore malformed */}
        },
        onError: (Object e) => _onDrop('$e'),
        onDone: () => _onDrop('closed'),
        cancelOnError: true,
      );

      channel.sink.add(jsonEncode({'hello': _keys!.publicKeyB64}));
      final reply = await firstFrame.future.timeout(const Duration(seconds: 8));
      _sid = reply['sid'].toString();
      _phonePubB64 = reply['phonePub'].toString();
      final phonePub = Pairing.publicKeyFromB64(_phonePubB64!);
      _expectedCode = await Pairing.shortCode(
        sid: _sid!,
        desktopPub: _keys!.publicKey,
        phonePub: phonePub,
      );
      _set(DesktopPairState.awaitingCode,
          'Enter the 6-digit code shown on your phone.');
      return true;
    } catch (e) {
      _set(DesktopPairState.error, 'Could not reach the phone: $e');
      await _teardown();
      return false;
    }
  }

  /// Verify the typed code against our computed code and, on a match, fetch and
  /// open the sealed payload from the phone.
  Future<PairingPayload?> submitCode(String code) async {
    final channel = _channel;
    if (channel == null || _sid == null || _phonePubB64 == null ||
        _keys == null) {
      return null;
    }
    if (code.trim() != _expectedCode) {
      _set(DesktopPairState.awaitingCode,
          'Incorrect code — check your phone and try again.');
      return null;
    }
    _set(DesktopPairState.verifying, 'Verifying…');
    try {
      final phonePub = Pairing.publicKeyFromB64(_phonePubB64!);
      final shared = await Pairing.deriveSharedKey(
        myKeyPair: _keys!.keyPair,
        peerPublicKey: phonePub,
        sid: _sid!,
      );
      final completer = Completer<String>();
      _payloadCompleter.add(completer);
      channel.sink.add(jsonEncode({'confirm': true}));
      final blob = await completer.future.timeout(const Duration(seconds: 10));
      final payload =
          await Pairing.openPayload(sharedKey: shared, blobB64: blob);
      _set(DesktopPairState.paired, 'Paired.');
      await _teardown();
      return payload;
    } catch (e) {
      _set(DesktopPairState.awaitingCode, 'Could not verify: $e');
      return null;
    }
  }

  void _onDrop(String why) {
    if (state == DesktopPairState.awaitingCode ||
        state == DesktopPairState.connecting ||
        state == DesktopPairState.verifying) {
      _set(DesktopPairState.error, 'Connection lost ($why). Try again.');
    }
  }

  Future<void> _teardown() async {
    try {
      await _sub?.cancel();
    } catch (_) {/* ignore */}
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {/* ignore */}
    _channel = null;
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

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
