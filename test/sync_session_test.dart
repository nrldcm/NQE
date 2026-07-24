// Security regression tests for the LAN-sync SESSION protocol.
//
// The live WebSocket sync session must be confidential + authenticated under
// the QR-provisioned pairing secret, NOT under the app-embedded static secret
// (which is recoverable from the shipped bundle). These tests pin that:
//   * a frame sealed under the session key round-trips;
//   * a frame sealed under the WRONG key (incl. the old encryptSecret /
//     _appSecret path) fails to authenticate;
//   * a replayed / stale counter is rejected by the monotonic replay rule.
import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/services/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = CryptoService.instance;

  group('sync session frames', () {
    test('a frame sealed under the session key round-trips', () async {
      final key = await svc.deriveSessionKey('paired-secret-abc');
      const payload =
          '[{"t":"trades","id":"x","u":"2026-01-01","d":0,"v":{"n":1}}]';
      final blob = await svc.sealFrame(key, counter: 1, payload: payload);
      // Ciphertext must hide the plaintext ledger payload.
      expect(blob.contains(payload), isFalse);
      final open = await svc.openFrame(key, blob);
      expect(open.counter, 1);
      expect(open.payload, payload);
    });

    test('the same pairing secret derives an identical key on both sides',
        () async {
      final a = await svc.deriveSessionKey('shared');
      final b = await svc.deriveSessionKey('shared');
      final blob = await svc.sealFrame(a, counter: 9, payload: 'hello');
      final open = await svc.openFrame(b, blob);
      expect(open.counter, 9);
      expect(open.payload, 'hello');
    });

    test('a frame sealed under the WRONG session key fails to authenticate',
        () async {
      final good = await svc.deriveSessionKey('paired-secret-abc');
      final wrong = await svc.deriveSessionKey('some-other-secret');
      final blob = await svc.sealFrame(good, counter: 1, payload: 'secret');
      expect(() => svc.openFrame(wrong, blob), throwsA(anything));
    });

    test('an old _appSecret (encryptSecret) blob cannot be opened as a frame',
        () async {
      // Frames used to be encrypted with the STATIC app secret. Prove that a
      // blob from that path no longer authenticates under the paired key.
      final key = await svc.deriveSessionKey('paired-secret-abc');
      final legacy = await svc.encryptSecret('[{"t":"trades"}]');
      expect(() => svc.openFrame(key, legacy), throwsA(anything));
    });

    test('a replayed / stale counter is rejected (monotonic rule)', () async {
      final key = await svc.deriveSessionKey('paired-secret-abc');
      final f1 = await svc.sealFrame(key, counter: 1, payload: 'a');
      final f2 = await svc.sealFrame(key, counter: 2, payload: 'b');

      var last = 0; // receiver's last-accepted counter

      final o1 = await svc.openFrame(key, f1);
      expect(CryptoService.isReplay(o1.counter, last), isFalse);
      last = o1.counter; // 1

      final o2 = await svc.openFrame(key, f2);
      expect(CryptoService.isReplay(o2.counter, last), isFalse);
      last = o2.counter; // 2

      // Replaying an OLD frame (counter 1 <= 2) is rejected.
      final replayed = await svc.openFrame(key, f1);
      expect(CryptoService.isReplay(replayed.counter, last), isTrue);

      // Re-sending the SAME counter (2 <= 2) is also rejected.
      final resent = await svc.openFrame(key, f2);
      expect(CryptoService.isReplay(resent.counter, last), isTrue);
    });
  });
}
