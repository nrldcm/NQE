// Encrypted export/import container.
//
// Design goals from the brief:
//   * "encrypted, app lang maka-decrypt" — by default files are encrypted with
//     a key derived inside the app, so any install of the NQE app can restore a
//     backup with no password to remember (needed for reinstall / new phone).
//   * OPTIONAL passphrase — if the user sets an export passphrase, it is mixed
//     into the key derivation, giving true confidentiality (files can then only
//     be decrypted by someone who knows the passphrase, even with the app).
//   * "di prone sa corruption" — AES-GCM is authenticated encryption: the tag is
//     verified on decrypt, so any bit-flip, truncation, or tampering is rejected
//     instead of silently importing garbage.
//
// File layout (.nqe) v2:
//   magic  "NQEBK1"  (6 bytes)
//   ver    0x02      (1 byte)
//   flags  (1 byte)  bit0 = passphrase-protected
//   salt   16 bytes  (random per export — PBKDF2 salt)
//   nonce  12 bytes  (random per export — AES-GCM nonce)
//   mac    16 bytes  (GCM authentication tag)
//   body   ciphertext (AES-256-GCM of UTF-8 JSON snapshot)
//
// v1 files (static salt, no flags/passphrase) are still accepted on import.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class CryptoException implements Exception {
  final String message;
  CryptoException(this.message);
  @override
  String toString() => message;
}

/// A decoded, authenticated LAN-sync frame: the monotonic replay [counter] and
/// the ledger [payload] JSON it carried. Produced by [CryptoService.openFrame].
class SyncFrame {
  final int counter;
  final String payload;
  const SyncFrame(this.counter, this.payload);
}

class CryptoService {
  CryptoService._();
  static final CryptoService instance = CryptoService._();

  static const _magic = [0x4E, 0x51, 0x45, 0x42, 0x4B, 0x31]; // "NQEBK1"
  static const _v1 = 0x01;
  static const _v2 = 0x02;
  static const _flagPassphrase = 0x01;

  // App-embedded base secret. Combined (with the optional passphrase) through
  // PBKDF2 into the AES key. Not a real secret against someone who has the app;
  // the passphrase is what provides confidentiality between users.
  static const String _appSecret =
      'NQE.Willong.Capital//narrative-quality-execution//v1';
  // Legacy static salt, only used to read any v1 file.
  static final List<int> _legacySalt = utf8.encode('nqe-fund-static-salt-2026');

  final _gcm = AesGcm.with256bits();
  final _rand = Random.secure();

  // HKDF-SHA256 used to stretch the QR-provisioned pairing secret into the
  // 256-bit AEAD key that protects the live sync session. Kept separate from
  // the backup key derivation (_deriveKey) and NEVER mixed with _appSecret.
  static final Hkdf _sessionHkdf =
      Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  // Cache derived keys by (saltHex|passphrase) so repeated ops are fast.
  final Map<String, SecretKey> _keyCache = {};

  Future<SecretKey> _deriveKey(List<int> salt, String passphrase) async {
    final cacheKey =
        '${base64Url.encode(salt)}|${passphrase.hashCode}|${passphrase.length}';
    final cached = _keyCache[cacheKey];
    if (cached != null) return cached;
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode('$_appSecret::$passphrase')),
      nonce: salt,
    );
    _keyCache[cacheKey] = key;
    return key;
  }

  Uint8List _randomBytes(int n) {
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = _rand.nextInt(256);
    }
    return b;
  }

  /// Encrypt JSON content into the .nqe container. If [passphrase] is non-empty,
  /// the file becomes passphrase-protected and can only be restored with it.
  Future<Uint8List> encryptJson(
    Map<String, Object?> json, {
    String passphrase = '',
  }) async {
    final plain = utf8.encode(jsonEncode(json));
    final salt = _randomBytes(16);
    final key = await _deriveKey(salt, passphrase);
    final box = await _gcm.encrypt(plain, secretKey: key);

    final out = BytesBuilder();
    out.add(_magic);
    out.addByte(_v2);
    out.addByte(passphrase.isNotEmpty ? _flagPassphrase : 0);
    out.add(salt); // 16
    out.add(box.nonce); // 12
    out.add(box.mac.bytes); // 16
    out.add(box.cipherText);
    return out.toBytes();
  }

  /// Encrypt a small secret (e.g. an API key) into a base64 string suitable
  /// for storing in SQLite. Decryptable only inside the app.
  Future<String> encryptSecret(String value) async {
    final bytes = await encryptJson({'v': value});
    return base64Encode(bytes);
  }

  Future<String> decryptSecret(String b64) async {
    final bytes = Uint8List.fromList(base64Decode(b64));
    final json = await decryptJson(bytes);
    return (json['v'] ?? '').toString();
  }

  // --- LAN sync session encryption -----------------------------------------
  //
  // The live WebSocket sync session is protected by a key derived ONLY from the
  // pairing secret that both devices provisioned over the SAS-authenticated QR
  // handshake — never from the app-embedded _appSecret. A passive LAN sniffer
  // therefore cannot read or forge sync frames, and possession of a validly
  // authenticated frame proves possession of the paired key.

  /// Derive the 256-bit AES-GCM session key from the shared [pairingKey] via
  /// HKDF-SHA256. Deterministic, so both peers derive the identical key.
  Future<SecretKey> deriveSessionKey(String pairingKey) {
    return _sessionHkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(pairingKey)),
      nonce: utf8.encode('nqe-sync-session-salt'),
      info: utf8.encode('nqe-sync-session-v1'),
    );
  }

  /// AES-256-GCM encrypt [plaintext] under an explicit [key]. Output layout
  /// mirrors the pairing/backup format: base64( nonce(12) ++ ciphertext ++
  /// tag(16) ). A fresh random 12-byte nonce is used per message.
  Future<String> encryptWithKey(SecretKey key, String plaintext) async {
    final box = await _gcm.encrypt(utf8.encode(plaintext), secretKey: key);
    final out = BytesBuilder();
    out.add(box.nonce); // 12
    out.add(box.cipherText);
    out.add(box.mac.bytes); // 16
    return base64Encode(out.toBytes());
  }

  /// Reverse [encryptWithKey]. Throws (GCM tag failure / format error) when the
  /// blob was not produced under [key] or was tampered with — the caller treats
  /// that as an unauthenticated frame.
  Future<String> decryptWithKey(SecretKey key, String b64) async {
    final raw = Uint8List.fromList(base64Decode(b64));
    const nonceLen = 12;
    const macLen = 16;
    if (raw.length < nonceLen + macLen) {
      throw CryptoException('Sync frame too short.');
    }
    final nonce = raw.sublist(0, nonceLen);
    final cipherText = raw.sublist(nonceLen, raw.length - macLen);
    final mac = Mac(raw.sublist(raw.length - macLen));
    final clear = await _gcm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return utf8.decode(clear);
  }

  /// Seal a sync frame: authenticated-encrypt an envelope binding the replay
  /// [counter] to the ledger [payload] JSON under the session [key].
  Future<String> sealFrame(
    SecretKey key, {
    required int counter,
    required String payload,
  }) {
    final envelope = jsonEncode({'c': counter, 'p': payload});
    return encryptWithKey(key, envelope);
  }

  /// Open a sync frame produced by [sealFrame]. Throws when [blob] is not
  /// authentic under [key]. The returned [SyncFrame.counter] must still be
  /// checked against the receiver's last-accepted counter via [isReplay].
  Future<SyncFrame> openFrame(SecretKey key, String blob) async {
    final clear = await decryptWithKey(key, blob);
    final env = jsonDecode(clear) as Map<String, dynamic>;
    final c = (env['c'] is int)
        ? env['c'] as int
        : int.tryParse('${env['c']}') ?? -1;
    final payload = (env['p'] ?? '').toString();
    return SyncFrame(c, payload);
  }

  /// Replay rule: a frame is stale/replayed when its [counter] does not
  /// strictly exceed the [lastAccepted] counter for the session. Shared by the
  /// server and client receivers so both enforce identical monotonicity.
  static bool isReplay(int counter, int lastAccepted) =>
      counter <= lastAccepted;

  /// True if the container requires a passphrase to decrypt.
  bool isPassphraseProtected(Uint8List bytes) {
    if (bytes.length < _magic.length + 2) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    final ver = bytes[_magic.length];
    if (ver != _v2) return false;
    return (bytes[_magic.length + 1] & _flagPassphrase) != 0;
  }

  /// Decrypt a .nqe container back into JSON, verifying integrity.
  Future<Map<String, Object?>> decryptJson(
    Uint8List bytes, {
    String passphrase = '',
  }) async {
    if (bytes.length < _magic.length + 1 + 12 + 16) {
      throw CryptoException('File too small or not an NQE backup.');
    }
    var i = 0;
    for (final b in _magic) {
      if (bytes[i++] != b) {
        throw CryptoException('Not an NQE backup file (bad header).');
      }
    }
    final ver = bytes[i++];

    List<int> salt;
    bool needsPass = false;
    if (ver == _v2) {
      final flags = bytes[i++];
      needsPass = (flags & _flagPassphrase) != 0;
      if (bytes.length < i + 16 + 12 + 16) {
        throw CryptoException('Backup is truncated.');
      }
      salt = bytes.sublist(i, i + 16);
      i += 16;
    } else if (ver == _v1) {
      salt = _legacySalt;
    } else {
      throw CryptoException('Unsupported backup version ($ver).');
    }

    if (needsPass && passphrase.isEmpty) {
      throw CryptoException(
          'This backup is passphrase-protected. Enter its passphrase to restore.');
    }

    final nonce = bytes.sublist(i, i + 12);
    i += 12;
    final mac = bytes.sublist(i, i + 16);
    i += 16;
    final cipherText = bytes.sublist(i);

    final key = await _deriveKey(salt, needsPass ? passphrase : '');
    List<int> plain;
    try {
      plain = await _gcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
    } catch (_) {
      // GCM tag mismatch => corrupted, tampered, or wrong passphrase.
      throw CryptoException(needsPass
          ? 'Wrong passphrase, or the backup is corrupted.'
          : 'Backup is corrupted or was not created by this app.');
    }
    try {
      final obj = jsonDecode(utf8.decode(plain));
      if (obj is! Map) throw const FormatException('bad');
      return obj.cast<String, Object?>();
    } catch (_) {
      throw CryptoException('Backup content is unreadable.');
    }
  }
}
