// Security tests for the SAS-authenticated X25519 pairing handshake.
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/sync/pairing.dart';

void main() {
  const sid = 'c2Vzc2lvbi1pZC0xMjM0NTY3OA';

  Future<(PairingKeys, PairingKeys)> pair() async {
    final desktop = await Pairing.generateKeys();
    final phone = await Pairing.generateKeys();
    return (desktop, phone);
  }

  test('both sides derive the same shared key and the same 6-digit code',
      () async {
    final (desktop, phone) = await pair();

    final kDesktop = await Pairing.deriveSharedKey(
      myKeyPair: desktop.keyPair,
      peerPublicKey: phone.publicKey,
      sid: sid,
    );
    final kPhone = await Pairing.deriveSharedKey(
      myKeyPair: phone.keyPair,
      peerPublicKey: desktop.publicKey,
      sid: sid,
    );
    expect(await kDesktop.extractBytes(), await kPhone.extractBytes(),
        reason: 'ECDH must converge on the same key');

    final codeDesktop = await Pairing.shortCode(
        sid: sid, desktopPub: desktop.publicKey, phonePub: phone.publicKey);
    final codePhone = await Pairing.shortCode(
        sid: sid, desktopPub: desktop.publicKey, phonePub: phone.publicKey);
    expect(codeDesktop, codePhone);
    expect(codeDesktop, matches(RegExp(r'^\d{6}$')));
  });

  test('payload seals and opens across the two derived keys', () async {
    final (desktop, phone) = await pair();
    const payload = PairingPayload(
      syncHost: '192.168.1.50',
      syncPort: 8787,
      syncKey: 'super-secret-sync-key',
      pinHash: 'aGFzaA',
      pinSalt: 'c2FsdA',
      pinLen: 6,
      pinIterations: 100000,
    );

    final phoneKey = await Pairing.deriveSharedKey(
      myKeyPair: phone.keyPair,
      peerPublicKey: desktop.publicKey,
      sid: sid,
    );
    final blob = await Pairing.sealPayload(sharedKey: phoneKey, payload: payload);

    final desktopKey = await Pairing.deriveSharedKey(
      myKeyPair: desktop.keyPair,
      peerPublicKey: phone.publicKey,
      sid: sid,
    );
    final opened =
        await Pairing.openPayload(sharedKey: desktopKey, blobB64: blob);

    expect(opened.syncHost, payload.syncHost);
    expect(opened.syncPort, payload.syncPort);
    expect(opened.syncKey, payload.syncKey);
    expect(opened.hasPin, isTrue);
    expect(opened.pinHash, payload.pinHash);
    expect(opened.pinLen, 6);
  });

  test('an eavesdropper without the ECDH secret cannot open the blob',
      () async {
    final (desktop, phone) = await pair();
    final attacker = await Pairing.generateKeys();

    final phoneKey = await Pairing.deriveSharedKey(
      myKeyPair: phone.keyPair,
      peerPublicKey: desktop.publicKey,
      sid: sid,
    );
    const payload = PairingPayload(
        syncHost: '10.0.0.2', syncPort: 8787, syncKey: 'k');
    final blob = await Pairing.sealPayload(sharedKey: phoneKey, payload: payload);

    // Attacker substitutes their own key pair — a different shared secret.
    final attackerKey = await Pairing.deriveSharedKey(
      myKeyPair: attacker.keyPair,
      peerPublicKey: phone.publicKey,
      sid: sid,
    );
    expect(
      () => Pairing.openPayload(sharedKey: attackerKey, blobB64: blob),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('a MITM that swaps public keys changes the 6-digit code (detected)',
      () async {
    final desktop = await Pairing.generateKeys();
    final phone = await Pairing.generateKeys();
    final mitm = await Pairing.generateKeys();

    // Honest transcript (what the phone shows).
    final honest = await Pairing.shortCode(
        sid: sid, desktopPub: desktop.publicKey, phonePub: phone.publicKey);
    // What the desktop would compute if a MITM injected its key as "the phone".
    final tampered = await Pairing.shortCode(
        sid: sid, desktopPub: desktop.publicKey, phonePub: mitm.publicKey);

    expect(honest == tampered, isFalse,
        reason: 'SAS must differ so the human comparison catches the MITM');
  });

  test('the session id binds the code — a replay under a new sid differs',
      () async {
    final desktop = await Pairing.generateKeys();
    final phone = await Pairing.generateKeys();
    final a = await Pairing.shortCode(
        sid: 'session-A', desktopPub: desktop.publicKey, phonePub: phone.publicKey);
    final b = await Pairing.shortCode(
        sid: 'session-B', desktopPub: desktop.publicKey, phonePub: phone.publicKey);
    expect(a == b, isFalse);
  });

  test('hybrid multi-host payload survives the sealed round-trip', () async {
    final (desktop, phone) = await pair();
    const payload = PairingPayload(
      syncHost: '192.168.1.50',
      hosts: ['192.168.1.50', '100.101.102.103'], // LAN + Tailscale
      syncPort: 8787,
      syncKey: 'k',
    );
    final phoneKey = await Pairing.deriveSharedKey(
      myKeyPair: phone.keyPair,
      peerPublicKey: desktop.publicKey,
      sid: sid,
    );
    final blob = await Pairing.sealPayload(sharedKey: phoneKey, payload: payload);
    final desktopKey = await Pairing.deriveSharedKey(
      myKeyPair: desktop.keyPair,
      peerPublicKey: phone.publicKey,
      sid: sid,
    );
    final opened =
        await Pairing.openPayload(sharedKey: desktopKey, blobB64: blob);
    expect(opened.allHosts, ['192.168.1.50', '100.101.102.103']);
    expect(opened.allHosts.first, '192.168.1.50', reason: 'LAN stays primary');
  });

  test('public key survives a base64 round-trip through the QR', () async {
    final keys = await Pairing.generateKeys();
    final restored = Pairing.publicKeyFromB64(keys.publicKeyB64);
    expect(restored.bytes, keys.publicKey.bytes);
  });
}
