// End-to-end regression test for the desktop→phone pairing flow over HTTP,
// including the SECURITY gate: the phone releases the sealed payload ONLY after
// the human taps Approve on the phone. A LAN client that never gets an approval
// must never obtain the secrets, no matter how many times it polls.
//
// It stands up a real HTTP server that mimics the phone's /pair/hello and
// /pair/confirm endpoints (the same protocol lib/sync/sync_server.dart serves)
// and drives the REAL desktop client (lib/sync/pairing_desktop.dart) against it.
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/sync/pairing.dart';
import 'package:nqe/sync/pairing_desktop.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() {
  // Do NOT initialise the Flutter widget test binding — it installs
  // HttpOverrides that make every HttpClient request return 400.

  // A tiny mimic of the phone's pairing responder. [approve] gates release.
  Future<({int port, Future<void> Function() close, void Function() approve})>
      startPhone(PairingPayload payload) async {
    final phoneKeys = await Pairing.generateKeys();
    final sid = phoneKeys.publicKeyB64.substring(0, 16);
    SecretKey? shared;
    var approved = false;

    Future<Response> handler(Request req) async {
      const json = {'content-type': 'application/json'};
      if (req.url.path == 'nqe') return Response.ok('NQE');
      if (req.url.path == 'pair/hello' && req.method == 'POST') {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final desktopPub = Pairing.publicKeyFromB64(body['pub'].toString());
        shared = await Pairing.deriveSharedKey(
            myKeyPair: phoneKeys.keyPair, peerPublicKey: desktopPub, sid: sid);
        approved = false;
        return Response.ok(
            jsonEncode({'sid': sid, 'phonePub': phoneKeys.publicKeyB64}),
            headers: json);
      }
      if (req.url.path == 'pair/confirm' && req.method == 'POST') {
        if (!approved) {
          return Response(202,
              body: jsonEncode({'status': 'waiting'}), headers: json);
        }
        final blob =
            await Pairing.sealPayload(sharedKey: shared!, payload: payload);
        return Response.ok(jsonEncode({'payload': blob}), headers: json);
      }
      return Response.notFound('x');
    }

    final server = await shelf_io.serve(handler, 'localhost', 0);
    return (
      port: server.port,
      close: () => server.close(force: true),
      approve: () => approved = true,
    );
  }

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

  test('desktop pairs only AFTER the human approves on the phone', () async {
    final phone = await startPhone(payload);
    addTearDown(phone.close);

    final desktop = DesktopPairing();
    // Approve shortly after pairing starts (simulates the human tap).
    Future<void>.delayed(const Duration(milliseconds: 150), phone.approve);

    final result = await desktop
        .pair('localhost', phone.port,
            pollInterval: const Duration(milliseconds: 40), maxPolls: 100)
        .timeout(const Duration(seconds: 15));

    expect(result, isNotNull);
    expect(result!.syncKey, 'the-sync-key');
    expect(result.allHosts, ['192.168.1.71', '100.90.80.70']);
    expect(result.hasPin, isTrue);
    expect(desktop.state, DesktopPairState.paired);
    expect(desktop.code, matches(RegExp(r'^\d{6}$')));
  });

  test('without approval the phone never releases the payload (security gate)',
      () async {
    final phone = await startPhone(payload);
    addTearDown(phone.close);

    // Never call phone.approve() → every /pair/confirm returns 202.
    final desktop = DesktopPairing();
    final result = await desktop
        .pair('localhost', phone.port,
            pollInterval: const Duration(milliseconds: 20), maxPolls: 8)
        .timeout(const Duration(seconds: 15));

    expect(result, isNull, reason: 'no approval → no secrets released');
    expect(desktop.state, DesktopPairState.error);
  });

  test('cancel stops the approval poll promptly', () async {
    final phone = await startPhone(payload);
    addTearDown(phone.close);

    final desktop = DesktopPairing();
    final future = desktop.pair('localhost', phone.port,
        pollInterval: const Duration(milliseconds: 40), maxPolls: 1000);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    desktop.cancel();
    final result = await future.timeout(const Duration(seconds: 5));
    expect(result, isNull);
  });

  test('phone not in pairing mode → clear error, no hang', () async {
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
    final result = await desktop
        .pair('localhost', server.port)
        .timeout(const Duration(seconds: 15));
    expect(result, isNull);
    expect(desktop.state, DesktopPairState.error);
  });

  test('dead address fails fast, never hangs', () async {
    final desktop = DesktopPairing();
    final result = await desktop
        .pair('127.0.0.1', 59099)
        .timeout(const Duration(seconds: 20));
    expect(result, isNull);
    expect(desktop.state, DesktopPairState.error);
  });
}
