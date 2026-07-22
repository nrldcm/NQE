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
