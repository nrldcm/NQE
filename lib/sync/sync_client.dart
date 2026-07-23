// Desktop-side LAN sync client.
//
// The mobile app is the source of truth and runs the WebSocket server (see
// sync_server.dart). The desktop connects to it as a client, mirroring that
// server's frame/auth protocol exactly:
//   1. Open a WebSocketChannel to ws://host:port/sync.
//   2. Send the pairing key verbatim as the FIRST frame to authenticate.
//   3. Push our full snapshot: encryptSecret(encodePayload(buildAll())).
//   4. For every incoming (encrypted) frame: decryptSecret -> decodePayload ->
//      SyncRepo.applyRemote, refresh appState, then reply with our latest
//      snapshot so the two sides converge.
//   5. A periodic timer re-sends our snapshot every few seconds. The merge is
//      idempotent/commutative (see sync_engine.dart), so repeated sends only
//      guarantee convergence and never corrupt data or drop edits.
//
// Everything is try/catch guarded: a socket error or close flips the state to
// reconnecting and retries with backoff up to [maxAttempts]; exceeding that
// stops at [SyncConn.disconnected]. The pairing URI is persisted so the desktop
// can auto-reconnect on the next launch.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/crypto_service.dart';
import '../state/app_state.dart';
import 'sync_engine.dart';
import 'sync_repo.dart';

enum SyncConn { idle, connecting, connected, reconnecting, disconnected }

class SyncClient extends ChangeNotifier {
  SyncClient._() {
    // Hydrate the saved pairing URI as soon as the singleton is created so
    // [lastUri] / host / port / key are available for auto-reconnect and the
    // sync panel's pre-fill without an explicit load call.
    loadSaved();
  }
  static final SyncClient instance = SyncClient._();

  static const _prefsUriKey = 'nqe.sync.lastUri';
  static const Duration _pushInterval = Duration(seconds: 4);

  SyncConn state = SyncConn.idle;
  int attempt = 0;
  int maxAttempts = 6;
  String? lastUri;
  String? statusMessage;

  // Parsed connection target from the last paired/loaded URI. [_hosts] holds
  // every candidate address in priority order (LAN first, mesh-VPN fallback).
  List<String> _hosts = [];
  int? _port;
  String? _key;

  /// The address the live connection is using (for status display).
  String? activeHost;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pushTimer;
  Timer? _retryTimer;
  bool _manuallyClosed = false;
  bool _authed = false;

  // --- public API ----------------------------------------------------------

  /// Parse a `nqe://sync?host=&hosts=&port=&key=` URI, persist it, then connect.
  Future<void> pair(String uri) async {
    final parsed = _parse(uri);
    if (parsed == null) {
      _set(SyncConn.disconnected, 'Invalid pairing link.');
      return;
    }
    _hosts = parsed.$1;
    _port = parsed.$2;
    _key = parsed.$3;
    lastUri = uri.trim();
    await _persistUri();
    await connect();
  }

  /// Set the sync target directly from a completed pairing. [hosts] are the
  /// phone's candidate addresses in priority order (LAN first, mesh-VPN
  /// fallback). Persists them, then connects. Used after the QR handshake.
  Future<void> setTargets({
    required List<String> hosts,
    required int port,
    required String key,
  }) async {
    _hosts = hosts.where((h) => h.trim().isNotEmpty).toList();
    _port = port;
    _key = key;
    lastUri = 'nqe://sync?host=${_hosts.isNotEmpty ? _hosts.first : ''}'
        '&hosts=${_hosts.join(',')}&port=$port&key=$key';
    await _persistUri();
    await connect();
  }

  /// Back-compat single-host convenience.
  Future<void> setTarget({
    required String host,
    required int port,
    required String key,
  }) =>
      setTargets(hosts: [host], port: port, key: key);

  Future<void> _persistUri() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (lastUri != null) await prefs.setString(_prefsUriKey, lastUri!);
    } catch (_) {
      // Persistence is best-effort; connecting still works this session.
    }
  }

  /// True once a pairing target has been saved (used to gate desktop first-run).
  Future<bool> isPaired() async {
    if (lastUri != null) return true;
    return loadSaved();
  }

  /// Forget the saved pairing so the desktop returns to first-run pairing.
  Future<void> unpair() async {
    disconnect();
    _hosts = [];
    _port = null;
    _key = null;
    activeHost = null;
    lastUri = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsUriKey);
    } catch (_) {/* ignore */}
    notifyListeners();
  }

  /// Load the saved pairing URI (if any) without connecting. Returns true if a
  /// URI was found, so the caller (desktop shell) can decide to auto-connect.
  Future<bool> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsUriKey);
      if (saved == null || saved.isEmpty) return false;
      final parsed = _parse(saved);
      if (parsed == null) return false;
      _hosts = parsed.$1;
      _port = parsed.$2;
      _key = parsed.$3;
      lastUri = saved;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Open the connection using the current (paired/loaded) URI. Resets the
  /// attempt counter — this is a fresh connect, not a backoff retry.
  Future<void> connect() async {
    attempt = 0;
    _manuallyClosed = false;
    await _open();
  }

  /// Manual retry: reset the attempt counter and connect again.
  Future<void> reconnect() async {
    _retryTimer?.cancel();
    attempt = 0;
    _manuallyClosed = false;
    await _open();
  }

  /// Tear down the connection and stop all timers. No further auto-reconnect.
  void disconnect() {
    _manuallyClosed = true;
    _retryTimer?.cancel();
    _teardownSocket();
    _set(SyncConn.idle, 'Disconnected.');
  }

  // --- connection lifecycle ------------------------------------------------

  Future<void> _open() async {
    // Self-heal: if we were never paired this session but a URI is persisted,
    // load it before giving up (covers auto-connect on a fresh launch).
    if (_key == null) {
      await loadSaved();
    }
    if (_hosts.isEmpty || _port == null || _key == null) {
      _set(SyncConn.disconnected, 'No pairing link — pair from your phone.');
      return;
    }

    _teardownSocket();

    // Hybrid connect: try each candidate address in priority order — LAN Wi-Fi
    // first, then the mesh-VPN (Tailscale) fallback — and use the first that
    // answers. This lets sync survive the phone leaving Wi-Fi.
    for (var i = 0; i < _hosts.length; i++) {
      final host = _hosts[i];
      final label = _hosts.length > 1 ? ' [${i + 1}/${_hosts.length}]' : '';
      _set(SyncConn.connecting,
          'Connecting to $host:$_port…$label (attempt ${attempt + 1})');
      try {
        final channel =
            WebSocketChannel.connect(Uri.parse('ws://$host:$_port/sync'));
        _channel = channel;
        _authed = false;

        // Short per-candidate timeout so a dead address fails fast to the next.
        await channel.ready.timeout(const Duration(seconds: 5));

        _sub = channel.stream.listen(
          _onFrame,
          onError: (Object e) => _onDrop('Connection error: $e'),
          onDone: () => _onDrop('Connection closed by peer.'),
          cancelOnError: true,
        );

        // First frame authenticates: the pairing key, verbatim.
        channel.sink.add(_key);
        _authed = true;
        attempt = 0;
        activeHost = host;
        _set(SyncConn.connected, 'Connected to $host:$_port.');

        await _pushSnapshot();
        _startPushTimer();
        return; // connected — stop trying candidates
      } catch (_) {
        // This candidate failed; clean up and try the next one.
        _teardownSocket();
      }
    }

    // No candidate answered — back off and retry the whole list later.
    _onDrop('Could not reach the phone on any address.');
  }

  void _onFrame(dynamic message) async {
    try {
      final frame = message is String ? message : message.toString();
      final json = await CryptoService.instance.decryptSecret(frame);
      final records = SyncEngine.decodePayload(json);
      await SyncRepo.instance.applyRemote(records);
      // Refresh the reused screens with the merged data.
      await appState.load();
      // Reply with our latest snapshot so the peer converges too.
      await _pushSnapshot();
    } catch (e) {
      // A single bad frame shouldn't drop the link — log via status and go on.
      statusMessage = 'Sync frame error: $e';
      notifyListeners();
    }
  }

  /// Encrypt + send our full local snapshot. Idempotent by construction.
  Future<void> _pushSnapshot() async {
    final channel = _channel;
    if (channel == null || !_authed) return;
    try {
      final records = await SyncRepo.instance.buildAll();
      final json = SyncEngine.encodePayload(records);
      final encrypted = await CryptoService.instance.encryptSecret(json);
      channel.sink.add(encrypted);
    } catch (e) {
      statusMessage = 'Failed to send snapshot: $e';
      notifyListeners();
    }
  }

  void _startPushTimer() {
    _pushTimer?.cancel();
    _pushTimer = Timer.periodic(_pushInterval, (_) => _pushSnapshot());
  }

  /// Handle a socket drop: if not manually closed, retry with backoff up to
  /// [maxAttempts]; beyond that, stop at [SyncConn.disconnected].
  void _onDrop(String reason) {
    _teardownSocket();
    if (_manuallyClosed) {
      _set(SyncConn.idle, 'Disconnected.');
      return;
    }

    if (attempt >= maxAttempts) {
      _set(SyncConn.disconnected,
          'Could not reconnect after $maxAttempts attempts. $reason');
      return;
    }

    attempt += 1;
    _set(SyncConn.reconnecting,
        'Reconnecting… (attempt $attempt of $maxAttempts)');

    // Exponential-ish backoff, capped, so a flapping link doesn't hammer.
    final secs = attempt.clamp(1, 8);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: secs), () {
      if (_manuallyClosed) return;
      _open();
    });
  }

  void _teardownSocket() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _authed = false;
    try {
      _sub?.cancel();
    } catch (_) {
      // Ignore — tearing down.
    }
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {
      // Ignore — tearing down.
    }
    _channel = null;
  }

  void _set(SyncConn s, String? message) {
    state = s;
    statusMessage = message;
    notifyListeners();
  }

  // --- parsing -------------------------------------------------------------

  /// Parse `nqe://sync?host=&hosts=&port=&key=` into (hosts, port, key), or
  /// null. `hosts` is a comma-separated priority list; `host` is the legacy
  /// single-address form and is folded in for backward compatibility.
  (List<String>, int, String)? _parse(String raw) {
    try {
      final uri = Uri.parse(raw.trim());
      final host = uri.queryParameters['host'] ?? '';
      final hostsParam = uri.queryParameters['hosts'] ?? '';
      final key = uri.queryParameters['key'] ?? '';
      final port = int.tryParse(uri.queryParameters['port'] ?? '');
      final hosts = <String>[];
      for (final h in [host, ...hostsParam.split(',')]) {
        final t = h.trim();
        if (t.isNotEmpty && !hosts.contains(t)) hosts.add(t);
      }
      if (hosts.isEmpty || key.isEmpty || port == null) return null;
      return (hosts, port, key);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _teardownSocket();
    super.dispose();
  }
}
