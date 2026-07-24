// Mobile-side LAN sync server.
//
// The phone is the source of truth: it runs a WebSocket server on the local
// Wi-Fi network and the desktop app connects to it as a client. Pairing is done
// out-of-band via a QR code encoding [pairingUri]; the [pairingKey] it carries
// is provisioned over the SAS-authenticated QR handshake and both devices
// persist it. After that both sides exchange encrypted payloads and merge
// deterministically via [SyncEngine] / [SyncRepo].
//
// Design notes:
//   * Session security: EVERY transport frame is sealed with AES-256-GCM under
//     a key derived (HKDF-SHA256) from the paired secret — NOT the app-embedded
//     static secret. Authentication is implicit: the first frame must decrypt
//     and verify under that key to prove the peer holds the paired secret, so
//     there is no cleartext key on the wire. Each frame carries a monotonic
//     counter (replay protection) and only ONE peer may be connected at a time.
//   * The server is deliberately defensive: bind and every connection are
//     wrapped in try/catch, and any failure flips [status] to
//     [SyncStatus.error] rather than throwing into the UI.
//   * A foreground service (see foreground.dart) keeps the listener alive while
//     the screen is locked or the app is backgrounded.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/auth_service.dart';
import '../services/crypto_service.dart';
import '../services/error_log.dart';
import '../sim/sim_state.dart';
import '../sim/sim_sync.dart';
import '../state/app_state.dart';
import 'foreground.dart';
import 'net_util.dart';
import 'pairing.dart';
import 'sync_engine.dart';
import 'sync_repo.dart';

enum SyncStatus { stopped, starting, running, error }

enum PeerState { idle, connecting, connected, reconnecting, disconnected }

class SyncServer extends ChangeNotifier {
  SyncServer._();
  static final SyncServer instance = SyncServer._();

  /// Default LAN port — the preferred one to bind. If it is busy/blocked the
  /// server auto-scans upward for an open port (see [bindWithFallback]) and the
  /// actually-bound [port] is what gets advertised in the QR.
  static const int defaultPort = 8787;
  static const _prefsPortKey = 'nqe.sync.port';

  SyncStatus status = SyncStatus.stopped;
  PeerState peer = PeerState.idle;
  String? host;

  /// Preferred port to try first (user-configurable). Persisted.
  int preferredPort = defaultPort;

  /// The port actually bound (== preferredPort unless it was busy/blocked).
  int port = defaultPort;
  int connectedPeers = 0;

  /// Human-readable reason for the last error, if any (for the UI).
  String? lastError;

  String _pairingKey = '';

  /// AES-256-GCM key for the live sync session, derived from [_pairingKey] via
  /// HKDF. Set on [start]; every sync frame is sealed/opened under it.
  SecretKey? _sessionKey;

  /// Monotonic counter stamped into every frame we send, for the peer's replay
  /// check. Strictly increasing across the server's lifetime.
  int _sendCounter = 0;

  HttpServer? _server;

  /// Currently authenticated peer sockets. Hard-capped to a SINGLE peer (a new
  /// authenticated connection replaces any existing one) so a sniffed session
  /// can't be joined by an extra forged peer. Also used to fan out the periodic
  /// auto-sync push below.
  final Set<WebSocketChannel> _peers = {};

  /// Periodic full-state push. Runs only while at least one peer is connected;
  /// started on the first connect and cancelled on the last disconnect / stop().
  Timer? _pushTimer;

  /// Debounce for the event-driven (near-instant) push fired on data changes.
  Timer? _debounce;

  /// Hash of the last snapshot we sent — skips redundant pushes so applying a
  /// remote change doesn't echo forever (convergence stops in one round).
  int? _lastSentHash;

  bool _appStateBound = false;

  /// Fallback interval. The real latency comes from the event-driven push on
  /// [appState] changes; this only catches anything the events might miss.
  static const Duration _pushInterval = Duration(seconds: 5);

  /// Pairing URI encoded into the QR shown to the desktop client.
  String get pairingUri =>
      'nqe://sync?host=${host ?? ''}&port=$port&key=$_pairingKey';

  /// The one-time key the desktop must echo to authenticate.
  String get pairingKey => _pairingKey;

  /// True when the server is serving over TLS (a bundled self-signed cert).
  bool _secure = false;

  /// Scheme + full browser URL to open the web app (https when a cert is bound).
  String get scheme => _secure ? 'https' : 'http';
  String get webUrl => '$scheme://${host ?? ''}:$port';

  bool get isRunning => status == SyncStatus.running;

  /// Load the bundled self-signed cert/key into a TLS context, so the web app
  /// is served over https/wss. Returns null (→ plain http fallback) if the
  /// cert can't be loaded, so the server always comes up.
  Future<SecurityContext?> _buildSecurityContext() async {
    try {
      final cert = await rootBundle.load('assets/tls/nqe_cert.pem');
      final key = await rootBundle.load('assets/tls/nqe_key.pem');
      return SecurityContext()
        ..useCertificateChainBytes(cert.buffer.asUint8List())
        ..usePrivateKeyBytes(key.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  /// Build the secure pairing payload handed to a desktop during pairing: the
  /// reachable sync endpoint + key, plus the phone's PIN credential so the
  /// desktop unlocks with the same PIN. Starts the server if needed so the
  /// host/port/key are valid. Returns null if the server can't be started (e.g.
  /// no Wi-Fi address). This object is sealed with AES-GCM by [Pairing] before
  /// it ever leaves the device.
  Future<PairingPayload?> buildPairingPayload() async {
    if (!isRunning) await start();
    if (_pairingKey.isEmpty) return null;
    final hosts = await _allSyncIps();
    if (hosts.isEmpty) return null;
    final pin = await AuthService.instance.exportPinCredential();
    return PairingPayload(
      syncHost: hosts.first,
      hosts: hosts,
      syncPort: port,
      syncKey: _pairingKey,
      pinHash: pin?['hash'] as String?,
      pinSalt: pin?['salt'] as String?,
      pinLen: (pin?['len'] as int?) ?? 0,
      pinIterations: (pin?['iter'] as int?) ?? 0,
    );
  }

  /// All addresses the desktop may reach this phone on, in priority order:
  /// LAN Wi-Fi first, then any mesh-VPN (Tailscale 100.64/10) address so sync
  /// keeps working when the phone leaves Wi-Fi, then any other private IPv4.
  /// The server binds 0.0.0.0, so it already listens on every one of these.
  Future<List<String>> _allSyncIps() async {
    final lan = <String>[];
    final mesh = <String>[];
    final other = <String>[];
    final wifi = host; // resolved on start() via network_info_plus
    if (wifi != null && wifi.isNotEmpty) lan.add(wifi);
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final ni in ifaces) {
        for (final a in ni.addresses) {
          final ip = a.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
          if (_isMeshVpn(ip)) {
            if (!mesh.contains(ip)) mesh.add(ip);
          } else if (_isPrivate(ip)) {
            if (ip != wifi && !other.contains(ip)) other.add(ip);
          }
        }
      }
    } catch (_) {
      // Fall back to whatever the Wi-Fi IP gave us.
    }
    // LAN preferred, mesh VPN as the internet fallback, then anything else.
    return [...lan, ...mesh, ...other];
  }

  /// Tailscale / CGNAT mesh range: 100.64.0.0/10 (second octet 64–127).
  bool _isMeshVpn(String ip) {
    if (!ip.startsWith('100.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final b = int.tryParse(parts[1]) ?? -1;
    return b >= 64 && b <= 127;
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

  /// Start the LAN WebSocket server. Idempotent: a no-op while already running.
  Future<void> start() async {
    if (status == SyncStatus.running || status == SyncStatus.starting) return;
    status = SyncStatus.starting;
    peer = PeerState.idle;
    lastError = null;
    notifyListeners();

    try {
      await _loadPreferredPort();
      host = await _resolveWifiIp();
      _pairingKey = _generateKey();
      // Derive the session AEAD key from the paired secret (never _appSecret).
      _sessionKey = await CryptoService.instance.deriveSessionKey(_pairingKey);
      _sendCounter = 0;

      final handler = _buildHandler();
      // Serve over TLS (self-signed) when the cert is available, so the browser
      // uses https/wss; fall back to plain http if it can't load.
      final tls = await _buildSecurityContext();
      _secure = tls != null;
      // Auto-scan for an open port starting at the preferred one, so a busy or
      // firewalled port doesn't break pairing. The bound port is advertised.
      _server =
          await bindWithFallback(handler, preferredPort, securityContext: tls);
      port = _server!.port;
      _server!.autoCompress = true;

      status = SyncStatus.running;
      _bindAppState();
      notifyListeners();

      await startForeground(
        'Listening on ${host ?? '0.0.0.0'}:$port — waiting for desktop',
      );
    } catch (e) {
      _server = null;
      _unbindAppState(); // don't leave the listener attached on a failed start
      status = SyncStatus.error;
      peer = PeerState.disconnected;
      lastError = 'Could not start sync server: $e';
      notifyListeners();
    }
  }

  /// Stop the server, drop peers, and clear the foreground notification.
  Future<void> stop() async {
    // Explicitly close each peer socket first so a connected desktop is told
    // to disconnect immediately (tapping Disconnect on the phone drops it),
    // instead of waiting to notice the server went away.
    for (final channel in _peers.toList()) {
      try {
        await channel.sink.close(1000, 'server stopped');
      } catch (_) {/* already gone */}
    }
    try {
      await _server?.close(force: true);
    } catch (_) {
      // Ignore — we're tearing down anyway.
    }
    _server = null;
    _stopPushTimer();
    _unbindAppState();
    _peers.clear();
    _sessionKey = null;
    _sendCounter = 0;
    connectedPeers = 0;
    peer = PeerState.idle;
    status = SyncStatus.stopped;
    lastError = null;
    notifyListeners();

    await stopForeground();
  }

  // --- near-instant, event-driven push --------------------------------------

  void _bindAppState() {
    if (_appStateBound) return;
    appState.addListener(_onLocalChange);
    simState.addListener(_onLocalChange); // sandbox edits push too
    _appStateBound = true;
  }

  void _unbindAppState() {
    if (!_appStateBound) return;
    appState.removeListener(_onLocalChange);
    simState.removeListener(_onLocalChange);
    _appStateBound = false;
    _debounce?.cancel();
    _debounce = null;
  }

  /// A local edit changed app state → push almost immediately (small debounce
  /// coalesces the load()'s two notifications and rapid successive edits).
  void _onLocalChange() {
    if (_peers.isEmpty) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120),
        () => unawaited(_pushToPeers()));
  }

  // --- pairing (phone is the server; the desktop connects OUT to us) --------
  //
  // On a locked-down laptop the desktop can't accept inbound connections
  // (firewall needs admin), so pairing is desktop-initiated: the desktop
  // connects to ws://<thisPhone>:<port>/pair. We run the SAS-authenticated
  // X25519 handshake here and, once the human confirms the 6-digit code, hand
  // over the sealed sync/PIN payload.
  bool pairingMode = false;
  bool pairingConnected = false; // a desktop is mid-handshake
  bool pairingApproved = false; // the human tapped Approve on THIS phone
  String? pairingCode; // the 6-digit SAS to show on the phone
  PairingKeys? _pairKeys;
  String? _pairSid;
  SecretKey? _pairShared; // derived shared key for the current handshake

  static const Map<String, String> _jsonHeaders = {
    'content-type': 'application/json'
  };

  bool get isPairing => pairingMode;

  /// Enter pairing mode (starts the server if needed) and mint a fresh session.
  Future<void> startPairing() async {
    if (!isRunning) await start();
    _pairKeys = await Pairing.generateKeys();
    final pk = _pairKeys!.publicKeyB64;
    _pairSid = pk.length >= 16 ? pk.substring(0, 16) : pk;
    pairingMode = true;
    pairingConnected = false;
    pairingApproved = false;
    pairingCode = null;
    notifyListeners();
  }

  /// Leave pairing mode and forget the ephemeral pairing session.
  void stopPairing() {
    pairingMode = false;
    pairingConnected = false;
    pairingApproved = false;
    pairingCode = null;
    _pairKeys = null;
    _pairSid = null;
    _pairShared = null;
    notifyListeners();
  }

  /// The human tapped Approve on THIS phone after confirming the desktop shows
  /// the same 6-digit code. Only now may the sealed payload be released. This is
  /// the security gate: without it any LAN client that completed the handshake
  /// could fetch the sync key + PIN. The human comparison + this tap authorise
  /// exactly one desktop.
  void approvePairing() {
    if (!pairingConnected) return;
    pairingApproved = true;
    notifyListeners();
  }

  /// Reject the current pairing attempt (codes didn't match / not me).
  void denyPairing() {
    pairingApproved = false;
    pairingConnected = false;
    pairingCode = null;
    _pairShared = null;
    notifyListeners();
  }

  // Pairing is plain HTTP request/response (two round-trips). This is far more
  // robust across platforms than a WebSocket and can't hang — the desktop uses
  // bounded HttpClient timeouts.

  /// POST /pair/hello  { pub }  →  { sid, phonePub }
  Future<Response> _pairHello(Request request) async {
    if (!pairingMode || _pairKeys == null || _pairSid == null) {
      return Response(409,
          body: jsonEncode({'error': 'not_pairing'}), headers: _jsonHeaders);
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final desktopPub = Pairing.publicKeyFromB64((body['pub'] ?? '').toString());
      _pairShared = await Pairing.deriveSharedKey(
        myKeyPair: _pairKeys!.keyPair,
        peerPublicKey: desktopPub,
        sid: _pairSid!,
      );
      pairingCode = await Pairing.shortCode(
        sid: _pairSid!,
        desktopPub: desktopPub,
        phonePub: _pairKeys!.publicKey,
      );
      pairingConnected = true;
      pairingApproved = false; // a new desktop must be re-approved by the human
      notifyListeners();
      return Response.ok(
        jsonEncode({'sid': _pairSid, 'phonePub': _pairKeys!.publicKeyB64}),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response(400,
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  /// POST /pair/confirm  { }  →  202 {status:waiting} until the human taps
  /// Approve on the phone, then 200 { payload } (sealed sync endpoint + PIN).
  /// The approval gate is what authorises release — without it the desktop
  /// polls and gets nothing, so a LAN client that never had the human's tap
  /// can never obtain the secrets.
  Future<Response> _pairConfirm(Request request) async {
    final shared = _pairShared;
    if (shared == null) {
      return Response(409,
          body: jsonEncode({'error': 'no_session'}), headers: _jsonHeaders);
    }
    if (!pairingApproved) {
      // Not yet approved by the human on this phone — tell the desktop to wait.
      return Response(202,
          body: jsonEncode({'status': 'waiting'}), headers: _jsonHeaders);
    }
    try {
      final payload = await buildPairingPayload();
      if (payload == null) {
        return Response(500,
            body: jsonEncode({'error': 'no_payload'}), headers: _jsonHeaders);
      }
      final blob = await Pairing.sealPayload(sharedKey: shared, payload: payload);
      // Release exactly once: burn the session so it can't be re-fetched.
      _pairShared = null;
      pairingApproved = false;
      pairingConnected = false;
      pairingCode = null;
      notifyListeners();
      return Response.ok(jsonEncode({'payload': blob}), headers: _jsonHeaders);
    } catch (e) {
      return Response(500,
          body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  /// Set the preferred sync port (persisted). Restarts the server if running so
  /// the new port takes effect and is re-advertised.
  Future<void> setPreferredPort(int p) async {
    preferredPort = sanitizePort(p, fallback: defaultPort);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsPortKey, preferredPort);
    } catch (_) {/* best-effort */}
    if (isRunning) {
      await stop();
      await start();
    } else {
      notifyListeners();
    }
  }

  Future<void> _loadPreferredPort() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      preferredPort = prefs.getInt(_prefsPortKey) ?? defaultPort;
    } catch (_) {
      preferredPort = defaultPort;
    }
  }

  // --- internals -----------------------------------------------------------

  Handler _buildHandler() {
    final syncWs = webSocketHandler(
      (WebSocketChannel channel, String? protocol) {
        _handleConnection(channel);
      },
    );
    return (Request request) async {
      final path = request.url.path;
      if (path == 'sync') return syncWs(request);
      // A tiny liveness probe used by the desktop's LAN scan to find this phone.
      if (path == 'nqe') {
        return Response.ok('NQE', headers: {'content-type': 'text/plain'});
      }
      if (path == 'pair/hello' && request.method == 'POST') {
        return _pairHello(request);
      }
      if (path == 'pair/confirm' && request.method == 'POST') {
        return _pairConfirm(request);
      }
      // Everything else: serve the bundled Flutter-web app so opening the
      // phone's LAN URL in a browser loads NQE instead of a bare 404. Only GET
      // is served statically; the special routes above keep their own methods.
      if (request.method == 'GET') {
        final asset = await _serveWebAsset(path);
        if (asset != null) return asset;
      }
      return Response.notFound('NQE server');
    };
  }

  /// Serve a file from the bundled Flutter-web build (see the `assets/web/`
  /// entries in pubspec, staged by CI from `flutter build web`). The URL path
  /// maps directly onto the asset key: root (`''`) → `assets/web/index.html`,
  /// otherwise `assets/web/<path>`. Returns null when the asset isn't bundled
  /// (rootBundle throws) so the caller falls back to the existing 404.
  Future<Response?> _serveWebAsset(String path) async {
    final rel = path.isEmpty ? 'index.html' : path;
    final key = 'assets/web/$rel';
    try {
      final data = await rootBundle.load(key);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      return Response.ok(bytes, headers: {'content-type': _webContentType(rel)});
    } catch (_) {
      return null;
    }
  }

  /// Best-effort content type for a bundled web asset, keyed off its extension.
  String _webContentType(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
    switch (ext) {
      case 'html':
        return 'text/html; charset=utf-8';
      case 'js':
        return 'application/javascript';
      case 'json':
        return 'application/json';
      case 'wasm':
        return 'application/wasm';
      case 'png':
        return 'image/png';
      case 'ico':
        return 'image/x-icon';
      case 'css':
        return 'text/css';
      case 'svg':
        return 'image/svg+xml';
      case 'ttf':
        return 'font/ttf';
      case 'otf':
        return 'font/otf';
      default:
        return 'application/octet-stream';
    }
  }

  void _handleConnection(WebSocketChannel channel) {
    peer = PeerState.connecting;
    notifyListeners();

    var authed = false;
    // Per-connection replay guard: the last accepted frame counter.
    var recvCounter = 0;
    StreamSubscription? sub;

    void teardown() {
      if (authed) {
        _peers.remove(channel);
        connectedPeers = _peers.length;
        authed = false;
      }
      // Stop the auto-sync push once the last peer has gone.
      if (_peers.isEmpty) _stopPushTimer();
      peer = connectedPeers > 0 ? PeerState.connected : PeerState.disconnected;
      notifyListeners();
      sub?.cancel();
    }

    try {
      sub = channel.stream.listen(
        (dynamic message) async {
          try {
            final frame = message is String ? message : message.toString();
            final key = _sessionKey;
            if (key == null) {
              await _closeQuietly(channel, 4001, 'unavailable');
              return;
            }

            // Every frame (including the first) must decrypt + authenticate
            // under the paired session key. A GCM/format failure ⇒ the peer
            // does not hold the paired secret ⇒ close 4001.
            SyncFrame decoded;
            try {
              decoded = await CryptoService.instance.openFrame(key, frame);
            } catch (_) {
              await _closeQuietly(channel, 4001, 'unauthorized');
              if (!authed) {
                peer = PeerState.disconnected;
                notifyListeners();
              }
              return;
            }

            // Replay protection: reject a frame whose counter does not strictly
            // advance. An unauthenticated first frame that fails this is treated
            // as a rejected auth attempt (close); an authed peer just drops it.
            if (CryptoService.isReplay(decoded.counter, recvCounter)) {
              if (!authed) {
                await _closeQuietly(channel, 4001, 'unauthorized');
                peer = PeerState.disconnected;
                notifyListeners();
              }
              return;
            }
            recvCounter = decoded.counter;

            final firstFrame = !authed;
            if (firstFrame) {
              // Single-peer cap: a newly authenticated peer replaces any
              // existing one so at most one connection is ever live.
              for (final old in _peers.toList()) {
                _peers.remove(old);
                await _closeQuietly(old, 4002, 'replaced by a newer peer');
              }
              authed = true;
              _peers.add(channel);
              connectedPeers = _peers.length;
              peer = PeerState.connected;
              notifyListeners();
              // Kick off continuous auto-sync now that a peer is connected.
              _startPushTimer();
            }

            // Merge the authenticated remote payload into the local DB.
            await _applyRecords(SyncEngine.decodePayload(decoded.payload));

            // On the first authenticated frame, answer with our snapshot so the
            // two sides converge.
            if (firstFrame) await _sendLocalPayload(channel);
          } catch (e, s) {
            lastError = 'Sync frame error: $e';
            unawaited(ErrorLog.instance
                .log('Sync frame error (server)', error: e, stack: s));
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

  /// Build our full snapshot, seal it under the session key, and push it to the
  /// peer as a replay-stamped frame.
  Future<void> _sendLocalPayload(WebSocketChannel channel) async {
    final key = _sessionKey;
    if (key == null) return;
    try {
      final records = await SyncRepo.instance.buildAll();
      records.addAll(await SimSyncRepo.instance.buildAll());
      final json = SyncEngine.encodePayload(records);
      _sendCounter += 1;
      final frame = await CryptoService.instance
          .sealFrame(key, counter: _sendCounter, payload: json);
      channel.sink.add(frame);
    } catch (e) {
      lastError = 'Failed to send snapshot: $e';
      notifyListeners();
    }
  }

  /// Start the periodic full-state push if it isn't already running. Idempotent
  /// so repeated peer connects don't spawn multiple timers.
  void _startPushTimer() {
    _pushTimer ??= Timer.periodic(_pushInterval, (_) {
      // Fire-and-forget; the async body swallows its own errors so the timer
      // never propagates an exception. Force a resend so a rare snapshot-hash
      // collision (which would skip the event-driven push) still converges.
      unawaited(_pushToPeers(force: true));
    });
  }

  /// Cancel and clear the periodic push timer.
  void _stopPushTimer() {
    _pushTimer?.cancel();
    _pushTimer = null;
  }

  /// Build a fresh encrypted snapshot once and fan it out to every connected
  /// peer. Idempotent on the receiving side (SyncEngine merges by newest
  /// (table,id)), so a re-send never duplicates or loses data. Fully guarded:
  /// a build/encrypt failure is recorded but never thrown, and a dead socket is
  /// skipped without aborting the rest.
  Future<void> _pushToPeers({bool force = false}) async {
    if (_peers.isEmpty) return;
    final key = _sessionKey;
    if (key == null) return;
    try {
      final records = await SyncRepo.instance.buildAll();
      records.addAll(await SimSyncRepo.instance.buildAll());
      final json = SyncEngine.encodePayload(records);
      // Skip when nothing changed since the last send — this stops an applied
      // remote frame from echoing back and forth forever.
      final hash = json.hashCode;
      if (!force && hash == _lastSentHash) return;
      _lastSentHash = hash;
      _sendCounter += 1;
      final frame = await CryptoService.instance
          .sealFrame(key, counter: _sendCounter, payload: json);
      for (final channel in _peers.toList()) {
        try {
          channel.sink.add(frame);
        } catch (_) {
          // Broken pipe — leave teardown (onDone/onError) to remove it.
        }
      }
    } catch (e) {
      lastError = 'Auto-sync push failed: $e';
      notifyListeners();
    }
  }

  /// Merge already-decrypted, authenticated remote [records] into the local DB.
  Future<void> _applyRecords(List<SyncRecord> records) async {
    // A connected desktop means Desktop Mode is gating this phone (the desktop
    // is the sole editor), so accept its ledger edits VERBATIM — clock-skew
    // can't then reject a genuine desktop edit/delete of an existing row.
    await SyncRepo.instance
        .applyRemote(records, asFollower: connectedPeers > 0);
    // Sandbox rows land in the sim DB only; then the phone (authority) reloads
    // so a desktop-placed order enters the engine loop and executes here. The
    // phone is the authority (asFollower:false) — it only accepts new forwarded
    // orders / order-cancels / account LWW from the desktop, never letting a
    // stale mirror row overwrite engine-owned positions & fills.
    final simApplied = await SimSyncRepo.instance
        .applyRemote(records, asFollower: simState.mirror);
    if (simApplied > 0) {
      try {
        await simState.onRemoteSimApplied();
      } catch (_) {/* non-fatal */}
    }
    // Refresh the phone's own screens so a desktop-originated edit shows up
    // live here too (two-way convergence). Best-effort — never throws.
    try {
      await appState.load();
    } catch (_) {
      // Non-fatal: the merge already landed in the DB.
    }
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
    // A 6-digit access code — easy to read off the phone and type into the
    // browser. Entropy is low (~20 bits) so it leans on the LAN scope, the
    // single-peer cap and the failed-auth throttle; use a tunnel/HTTPS for
    // internet exposure. The live sync frames are still AES-GCM-encrypted under
    // a key HKDF-derived from this code.
    final rand = Random.secure();
    return (100000 + rand.nextInt(900000)).toString();
  }
}
