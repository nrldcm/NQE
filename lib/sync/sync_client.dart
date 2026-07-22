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

  // Parsed connection target from the last paired/loaded URI.
  String? _host;
  int? _port;
  String? _key;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pushTimer;
  Timer? _retryTimer;
  bool _manuallyClosed = false;
  bool _authed = false;

  // --- public API ----------------------------------------------------------

  /// Parse a `nqe://sync?host=&port=&key=` URI, persist it, then connect.
  Future<void> pair(String uri) async {
    final parsed = _parse(uri);
    if (parsed == null) {
      _set(SyncConn.disconnected, 'Invalid pairing link.');
      return;
    }
    _host = parsed.$1;
    _port = parsed.$2;
    _key = parsed.$3;
    lastUri = uri.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsUriKey, lastUri!);
    } catch (_) {
      // Persistence is best-effort; connecting still works this session.
    }
    await connect();
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
      _host = parsed.$1;
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
    if (_host == null || _port == null || _key == null) {
      _set(SyncConn.disconnected, 'No pairing link — paste one to connect.');
      return;
    }

    _teardownSocket();
    _set(SyncConn.connecting,
        'Connecting to $_host:$_port… (attempt ${attempt + 1})');

    try {
      final uri = Uri.parse('ws://$_host:$_port/sync');
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _authed = false;

      // Wait for the handshake so a dead host fails fast into reconnect.
      await channel.ready.timeout(const Duration(seconds: 8));

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
      _set(SyncConn.connected, 'Connected to $_host:$_port.');

      // Push our snapshot immediately, then keep pushing periodically.
      await _pushSnapshot();
      _startPushTimer();
    } catch (e) {
      _onDrop('Could not connect: $e');
    }
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

  /// Parse `nqe://sync?host=&port=&key=` into (host, port, key), or null.
  (String, int, String)? _parse(String raw) {
    try {
      final uri = Uri.parse(raw.trim());
      final host = uri.queryParameters['host'] ?? '';
      final key = uri.queryParameters['key'] ?? '';
      final port = int.tryParse(uri.queryParameters['port'] ?? '');
      if (host.isEmpty || key.isEmpty || port == null) return null;
      return (host, port, key);
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
