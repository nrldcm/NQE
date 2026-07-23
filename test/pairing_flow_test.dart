// End-to-end regression test for the desktop→phone pairing flow over HTTP.
//
// It stands up a real HTTP server that mimics the phone's /pair/hello and
// /pair/confirm endpoints (the same protocol lib/sync/sync_server.dart serves)
// and drives the REAL desktop client (lib/sync/pairing_desktop.dart) against it,
// asserting the connect → code → confirm handshake yields the sealed payload.
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/sync/pairing.dart';
import 'package:nqe/sync/pairing_desktop.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() {
  // NOTE: do NOT initialize the Flutter widget test binding here — it installs
  // HttpOverrides that make every HttpClient request return 400, which would
  // stop the real client from reaching our mimic phone server below.

  test('desktop connects, matches the code, and receives the sealed payload',
      () async {
    // --- phone side (mimics SyncServer's pairing responder) ---
    final phoneKeys = await Pairing.generateKeys();
    final sid = phoneKeys.publicKeyB64.substring(0, 16);
    const payload = PairingPayload(
      syncHost: '192.168.1.71',
      hosts: ['192.168.1.71', '100.90.80.70'],
      syncPort: 8787,
      syncKey: 'the-sync-key',
      pinHash: 'aGFzaA',
      pinSalt: 'c2FsdA',
      pinLen: 6,
      pinIterations: 100000,
    );
    SecretKey? shared;

    Future<Response> handler(Request req) async {
      const json = {'content-type': 'application/json'};
      if (req.url.path == 'nqe') return Response.ok('NQE');
      if (req.url.path == 'pair/hello' && req.method == 'POST') {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final desktopPub = Pairing.publicKeyFromB64(body['pub'].toString());
        shared = await Pairing.deriveSharedKey(
            myKeyPair: phoneKeys.keyPair, peerPublicKey: desktopPub, sid: sid);
        return Response.ok(
            jsonEncode({'sid': sid, 'phonePub': phoneKeys.publicKeyB64}),
            headers: json);
      }
      if (req.url.path == 'pair/confirm' && req.method == 'POST') {
        final blob =
            await Pairing.sealPayload(sharedKey: shared!, payload: payload);
        return Response.ok(jsonEncode({'payload': blob}), headers: json);
      }
      return Response.notFound('x');
    }

    final server = await shelf_io.serve(handler, 'localhost', 0);
    addTearDown(() => server.close(force: true));

    // --- desktop side (the real client) ---
    final desktop = DesktopPairing();
    final ok = await desktop.connect('localhost', server.port);
    expect(ok, isTrue);
    expect(desktop.state, DesktopPairState.awaitingCode);
    expect(desktop.expectedCode, matches(RegExp(r'^\d{6}$')));

    // Wrong code must be rejected without fetching the payload.
    final bad = await desktop.submitCode('000000');
    expect(bad, isNull);
    expect(desktop.state, DesktopPairState.awaitingCode);

    // Correct code (what the phone shows) → sealed payload opens.
    final result = await desktop.submitCode(desktop.expectedCode!);
    expect(result, isNotNull);
    expect(result!.syncKey, 'the-sync-key');
    expect(result.allHosts, ['192.168.1.71', '100.90.80.70']);
    expect(result.hasPin, isTrue);
    expect(desktop.state, DesktopPairState.paired);
  });

  test('connecting to a phone that is not pairing surfaces a clear error',
      () async {
    Future<Response> handler(Request req) async {
      const json = {'content-type': 'application/json'};
      if (req.url.path == 'pair/hello') {
        return Response(409,
            body: jsonEncode({'error': 'not_pairing'}), headers: json);
      }
      return Response.notFound('x');
    }

    final server = await shelf_io.serve(handler, 'localhost', 0);
    addTearDown(() => server.close(force: true));

    final desktop = DesktopPairing();
    final ok = await desktop.connect('localhost', server.port);
    expect(ok, isFalse);
    expect(desktop.state, DesktopPairState.error);
  });

  test('connecting to a dead address fails fast, never hangs', () async {
    final desktop = DesktopPairing();
    // Nothing is listening on this port → bounded HttpClient timeout, no hang.
    final ok = await desktop
        .connect('127.0.0.1', 59099)
        .timeout(const Duration(seconds: 20));
    expect(ok, isFalse);
    expect(desktop.state, DesktopPairState.error);
  });
}
