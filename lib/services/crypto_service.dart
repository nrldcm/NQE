// Encrypted export/import container.
//
// Design goals from the brief:
//   * "encrypted, app lang maka-decrypt" — files are encrypted with a key
//     derived inside the app, so only the NQE app can read them back.
//   * "di prone sa corruption" — AES-GCM is *authenticated* encryption: the
//     built-in tag is verified on decrypt, so any bit-flip, truncation, or
//     tampering is detected and rejected instead of silently importing garbage.
//
// File layout (.nqe):
//   magic  "NQEBK1"  (6 bytes)
//   ver    0x01      (1 byte)
//   nonce  12 bytes  (random per export)
//   mac    16 bytes  (GCM authentication tag)
//   body   ciphertext (AES-256-GCM of UTF-8 JSON snapshot)
//
// NOTE: with an app-embedded key, anyone with the app can decrypt an export.
// That matches the requested model (no password to remember). For stronger,
// per-user secrecy, layer a passphrase on top (see Settings → future option).
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class CryptoException implements Exception {
  final String message;
  CryptoException(this.message);
  @override
  String toString() => message;
}

class CryptoService {
  CryptoService._();
  static final CryptoService instance = CryptoService._();

  static const _magic = [0x4E, 0x51, 0x45, 0x42, 0x4B, 0x31]; // "NQEBK1"
  static const _version = 0x01;

  // App-embedded base secret + salt. Combined through PBKDF2 into the AES key.
  static const String _appSecret =
      'NQE.Willong.Capital//narrative-quality-execution//v1';
  static final List<int> _salt = utf8.encode('nqe-fund-static-salt-2026');

  final _gcm = AesGcm.with256bits();
  SecretKey? _cachedKey;

  Future<SecretKey> _key() async {
    if (_cachedKey != null) return _cachedKey!;
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    _cachedKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(_appSecret)),
      nonce: _salt,
    );
    return _cachedKey!;
  }

  /// Encrypt arbitrary JSON-serialisable content into the .nqe container.
  Future<Uint8List> encryptJson(Map<String, Object?> json) async {
    final plain = utf8.encode(jsonEncode(json));
    final key = await _key();
    final box = await _gcm.encrypt(plain, secretKey: key);

    final out = BytesBuilder();
    out.add(_magic);
    out.addByte(_version);
    out.add(box.nonce); // 12 bytes
    out.add(box.mac.bytes); // 16 bytes
    out.add(box.cipherText);
    return out.toBytes();
  }

  /// Decrypt a .nqe container back into JSON, verifying integrity.
  Future<Map<String, Object?>> decryptJson(Uint8List bytes) async {
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
    if (ver != _version) {
      throw CryptoException('Unsupported backup version ($ver).');
    }
    final nonce = bytes.sublist(i, i + 12);
    i += 12;
    final mac = bytes.sublist(i, i + 16);
    i += 16;
    final cipherText = bytes.sublist(i);

    final key = await _key();
    List<int> plain;
    try {
      plain = await _gcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
    } catch (_) {
      // GCM tag mismatch => corrupted or tampered file.
      throw CryptoException(
          'Backup is corrupted or was not created by this app.');
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
