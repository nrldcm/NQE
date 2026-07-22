// Mobile-side LAN sync server.
//
// The phone is the source of truth: it runs a WebSocket server on the local
// Wi-Fi network and the desktop app connects to it as a client. Pairing is done
// out-of-band via a QR code encoding [pairingUri]; the desktop must present the
// [pairingKey] as its first frame to authenticate. After that both sides
// exchange one encrypted payload each and merge deterministically via
// [SyncEngine] / [SyncRepo].
//
// Design notes:
//   * Transport frames are the JSON payload string, encrypted with
//     CryptoService.encryptSecret/decryptSecret (authenticated AES-GCM) so no
//     ledger data crosses the LAN in the clear.
//   * The server is deliberately defensive: bind and every connection are
//     wrapped in try/catch, and any failure flips [status] to
//     [SyncStatus.error] rather than throwing into the UI.
//   * A foreground service (see foreground.dart) keeps the listener alive while
//     the screen is locked or the app is backgrounded.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/crypto_service.dart';
import 'foreground.dart';
import 'sync_engine.dart';
import 'sync_repo.dart';

enum SyncStatus { stopped, starting, running, error }

enum PeerState { idle, connecting, connected, reconnecting, disconnected }

class SyncServer extends ChangeNotifier {
  SyncServer._();
  static final SyncServer instance = SyncServer._();

  /// Default LAN port. Kept fixed so the QR pairing URI is predictable.
  static const int defaultPort = 8787;

  SyncStatus status = SyncStatus.stopped;
  PeerState peer = PeerState.idle;
  String? host;
  int port = defaultPort;
  int connectedPeers = 0;

  /// Human-readable reason for the last error, if any (for the UI).
  String? lastError;

  String _pairingKey = '';
  HttpServer? _server;

  /// Pairing URI encoded into the QR shown to the desktop client.
  String get pairingUri =>
      'nqe://sync?host=${host ?? ''}&port=$port&key=$_pairingKey';

  /// The one-time key the desktop must echo to authenticate.
  String get pairingKey => _pairingKey;

  bool get isRunning => status == SyncStatus.running;

  /// Start the LAN WebSocket server. Idempotent: a no-op while already running.
  Future<void> start() async {
    if (status == SyncStatus.running || status == SyncStatus.starting) return;
    status = SyncStatus.starting;
    peer = PeerState.idle;
    lastError = null;
    notifyListeners();

    try {
      host = await _resolveWifiIp();
      _pairingKey = _generateKey();

      final handler = _buildHandler();
      _server = await shelf_io.serve(handler, '0.0.0.0', port);
      // Be tolerant of proxies / relays.
      _server!.autoCompress = true;

      status = SyncStatus.running;
      notifyListeners();

      await startForeground(
        'Listening on ${host ?? '0.0.0.0'}:$port — waiting for desktop',
      );
    } catch (e) {
      _server = null;
      status = SyncStatus.error;
      peer = PeerState.disconnected;
      lastError = 'Could not start sync server: $e';
      notifyListeners();
    }
  }

  /// Stop the server, drop peers, and clear the foreground notification.
  Future<void> stop() async {
    try {
      await _server?.close(force: true);
    } catch (_) {
      // Ignore — we're tearing down anyway.
    }
    _server = null;
    connectedPeers = 0;
    peer = PeerState.idle;
    status = SyncStatus.stopped;
    lastError = null;
    notifyListeners();

    await stopForeground();
  }

  // --- internals -----------------------------------------------------------

  Handler _buildHandler() {
    final ws = webSocketHandler(
      (WebSocketChannel channel, String? protocol) {
        _handleConnection(channel);
      },
    );
    return (Request request) {
      if (request.url.path == 'sync') {
        return ws(request);
      }
      return Response.notFound('NQE sync server');
    };
  }

  void _handleConnection(WebSocketChannel channel) {
    peer = PeerState.connecting;
    notifyListeners();

    var authed = false;
    StreamSubscription? sub;

    void teardown() {
      if (authed) {
        connectedPeers = connectedPeers > 0 ? connectedPeers - 1 : 0;
        authed = false;
      }
      peer = connectedPeers > 0 ? PeerState.connected : PeerState.disconnected;
      notifyListeners();
      sub?.cancel();
    }

    try {
      sub = channel.stream.listen(
        (dynamic message) async {
          try {
            final frame = message is String ? message : message.toString();

            if (!authed) {
              // First frame must be the pairing key, verbatim.
              if (frame != _pairingKey) {
                await _closeQuietly(channel, 4001, 'unauthorized');
                peer = PeerState.disconnected;
                notifyListeners();
                return;
              }
              authed = true;
              connectedPeers += 1;
              peer = PeerState.connected;
              notifyListeners();
              await _sendLocalPayload(channel);
              return;
            }

            // Authenticated data frame: encrypted remote payload.
            await _applyRemoteFrame(frame);
          } catch (e) {
            lastError = 'Sync frame error: $e';
            notifyListeners();
          }
        },
        onError: (Object e) {
          lastError = 'Peer connection error: $e';
          teardown();
        },
        onDone: teardown,
        cancelOnError: true,
      );
    } catch (e) {
      lastError = 'Could not accept peer: $e';
      peer = PeerState.disconnected;
      notifyListeners();
    }
  }

  /// Build our full snapshot, encrypt it, and push it to the peer.
  Future<void> _sendLocalPayload(WebSocketChannel channel) async {
    try {
      final records = await SyncRepo.instance.buildAll();
      final json = SyncEngine.encodePayload(records);
      final encrypted = await CryptoService.instance.encryptSecret(json);
      channel.sink.add(encrypted);
    } catch (e) {
      lastError = 'Failed to send snapshot: $e';
      notifyListeners();
    }
  }

  /// Decrypt an incoming frame and merge it into the local database.
  Future<void> _applyRemoteFrame(String frame) async {
    final json = await CryptoService.instance.decryptSecret(frame);
    final records = SyncEngine.decodePayload(json);
    await SyncRepo.instance.applyRemote(records);
  }

  Future<void> _closeQuietly(
    WebSocketChannel channel,
    int code,
    String reason,
  ) async {
    try {
      await channel.sink.close(code, reason);
    } catch (_) {
      // Ignore close failures.
    }
  }

  Future<String?> _resolveWifiIp() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      if (ip != null && ip.isNotEmpty) return ip;
    } catch (_) {
      // Fall through — host stays null and the UI can prompt the user.
    }
    return null;
  }

  String _generateKey() {
    final rand = Random.secure();
    final bytes = List<int>.generate(24, (_) => rand.nextInt(256));
    // URL-safe, no padding — fits cleanly in the QR pairing URI.
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
