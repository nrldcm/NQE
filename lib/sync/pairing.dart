// Secure device pairing — SAS-authenticated X25519 key exchange.
//
// Threat model: the desktop and phone are on the same LAN as a possible
// attacker who can sniff and inject traffic. We must transfer the phone's
// sync-server credentials AND its PIN to the desktop without either leaking to
// an eavesdropper or being silently intercepted by a man-in-the-middle.
//
// How it works (numeric-comparison pairing, the same idea Bluetooth Secure
// Connections and Signal safety-numbers use):
//   1. The DESKTOP creates an ephemeral X25519 key pair and a random session id
//      (sid). It shows a QR encoding its LAN endpoint + its public key + sid.
//   2. The PHONE scans the QR, creates its own ephemeral X25519 key pair, and
//      derives the shared secret via ECDH. From (sid, desktopPub, phonePub) it
//      computes a short 6-digit code (the SAS) and shows it.
//   3. The phone sends its public key (and the encrypted payload) to the
//      desktop. The desktop derives the SAME shared secret and the SAME 6-digit
//      code from (sid, desktopPub, phonePub).
//   4. The human types the 6-digit code shown on the phone into the desktop.
//      The desktop accepts ONLY if the typed code equals its computed SAS.
//
// Why this is safe:
//   * Confidentiality: the payload is sealed with AES-GCM under a key derived
//     from the full-entropy ECDH secret — NOT from the 6-digit code — so a
//     passive sniffer cannot decrypt it and the short code is never brute-force
//     material.
//   * Integrity / anti-MITM: an active attacker who swaps public keys changes
//     the SAS; the two devices would then show different 6-digit codes and the
//     human comparison fails. The code authenticates the key exchange.
//   * Forward secrecy: keys are ephemeral and discarded after pairing.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The decrypted pairing payload the phone hands to the desktop: everything the
/// desktop needs to reach the sync server and adopt the phone's PIN.
class PairingPayload {
  final String syncHost;
  final int syncPort;
  final String syncKey;

  /// PIN credential mirrored from the phone so the desktop unlocks with the
  /// exact same PIN. Null when the phone has no PIN configured.
  final String? pinHash;
  final String? pinSalt;
  final int pinLen;
  final int pinIterations;

  const PairingPayload({
    required this.syncHost,
    required this.syncPort,
    required this.syncKey,
    this.pinHash,
    this.pinSalt,
    this.pinLen = 0,
    this.pinIterations = 0,
  });

  bool get hasPin =>
      (pinHash ?? '').isNotEmpty && (pinSalt ?? '').isNotEmpty && pinLen > 0;

  Map<String, dynamic> toJson() => {
        'host': syncHost,
        'port': syncPort,
        'key': syncKey,
        if (hasPin) 'pinHash': pinHash,
        if (hasPin) 'pinSalt': pinSalt,
        if (hasPin) 'pinLen': pinLen,
        if (hasPin) 'pinIter': pinIterations,
      };

  factory PairingPayload.fromJson(Map<String, dynamic> j) => PairingPayload(
        syncHost: (j['host'] ?? '').toString(),
        syncPort: (j['port'] is int)
            ? j['port'] as int
            : int.tryParse('${j['port']}') ?? 0,
        syncKey: (j['key'] ?? '').toString(),
        pinHash: j['pinHash']?.toString(),
        pinSalt: j['pinSalt']?.toString(),
        pinLen: (j['pinLen'] is int)
            ? j['pinLen'] as int
            : int.tryParse('${j['pinLen']}') ?? 0,
        pinIterations: (j['pinIter'] is int)
            ? j['pinIter'] as int
            : int.tryParse('${j['pinIter']}') ?? 0,
      );
}

/// An ephemeral X25519 identity for one pairing session.
class PairingKeys {
  final SimpleKeyPair keyPair;
  final SimplePublicKey publicKey;
  const PairingKeys(this.keyPair, this.publicKey);

  /// URL-safe base64 of the 32-byte X25519 public key.
  String get publicKeyB64 => base64Url.encode(publicKey.bytes);
}

/// Stateless helpers for the pairing handshake. All crypto lives here so it can
/// be unit-tested without any UI, sockets, or platform channels.
class Pairing {
  static final X25519 _x25519 = X25519();
  static final AesGcm _aead = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Generate a fresh ephemeral X25519 key pair for a pairing session.
  static Future<PairingKeys> generateKeys() async {
    final kp = await _x25519.newKeyPair();
    final pub = await kp.extractPublicKey();
    return PairingKeys(kp, pub);
  }

  /// Parse a URL-safe base64 X25519 public key back into a [SimplePublicKey].
  static SimplePublicKey publicKeyFromB64(String b64) =>
      SimplePublicKey(base64Url.decode(_pad(b64)),
          type: KeyPairType.x25519);

  /// Derive the shared AES-256-GCM key from our private key + the peer's public
  /// key, bound to the session id so keys from other sessions never collide.
  static Future<SecretKey> deriveSharedKey({
    required SimpleKeyPair myKeyPair,
    required SimplePublicKey peerPublicKey,
    required String sid,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );
    final sharedBytes = await shared.extractBytes();
    // HKDF over the raw ECDH output, salted with the session id and a fixed
    // context string, yields the symmetric key actually used for AES-GCM.
    return _hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: utf8.encode('nqe-pair::$sid'),
      info: utf8.encode('nqe-pairing-v1'),
    );
  }

  /// Compute the 6-digit Short Authentication String from the transcript. Both
  /// devices compute this independently; the human compares them by typing the
  /// phone's code into the desktop. Order of public keys is fixed (desktop then
  /// phone) so both sides agree regardless of who calls it.
  static Future<String> shortCode({
    required String sid,
    required SimplePublicKey desktopPub,
    required SimplePublicKey phonePub,
  }) async {
    final transcript = <int>[
      ...utf8.encode('nqe-sas::$sid::'),
      ...desktopPub.bytes,
      0x7c, // '|' separator
      ...phonePub.bytes,
    ];
    final digest = await Sha256().hash(transcript);
    final b = digest.bytes;
    // Fold the first 4 bytes into a 0..999999 value (>=20 bits of the hash).
    final n = ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) & 0x7fffffff;
    return (n % 1000000).toString().padLeft(6, '0');
  }

  /// Seal the payload with AES-256-GCM under the shared key. Returns a
  /// self-describing base64 blob (nonce ++ ciphertext ++ mac).
  static Future<String> sealPayload({
    required SecretKey sharedKey,
    required PairingPayload payload,
  }) async {
    final plaintext = utf8.encode(jsonEncode(payload.toJson()));
    final box = await _aead.encrypt(plaintext, secretKey: sharedKey);
    final out = Uint8List(box.nonce.length + box.cipherText.length + box.mac.bytes.length);
    var o = 0;
    out.setRange(o, o += box.nonce.length, box.nonce);
    out.setRange(o, o += box.cipherText.length, box.cipherText);
    out.setRange(o, o += box.mac.bytes.length, box.mac.bytes);
    return base64Url.encode(out);
  }

  /// Open a sealed payload. Throws [SecretBoxAuthenticationError] (GCM MAC
  /// failure) if the key is wrong or the blob was tampered with — the caller
  /// treats that as "wrong code / rejected".
  static Future<PairingPayload> openPayload({
    required SecretKey sharedKey,
    required String blobB64,
  }) async {
    final raw = base64Url.decode(_pad(blobB64));
    const nonceLen = 12; // AES-GCM standard nonce
    const macLen = 16; // GCM tag
    if (raw.length < nonceLen + macLen) {
      throw const FormatException('pairing blob too short');
    }
    final nonce = raw.sublist(0, nonceLen);
    final cipherText = raw.sublist(nonceLen, raw.length - macLen);
    final mac = Mac(raw.sublist(raw.length - macLen));
    final box = SecretBox(cipherText, nonce: nonce, mac: mac);
    final clear = await _aead.decrypt(box, secretKey: sharedKey);
    final map = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    return PairingPayload.fromJson(map);
  }

  static String _pad(String b64) {
    final rem = b64.length % 4;
    return rem == 0 ? b64 : b64 + '=' * (4 - rem);
  }
}
