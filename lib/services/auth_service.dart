// App lock: biometric (fingerprint / face / device credential) with a PIN
// fallback.
//
// Hardening:
//   * The PIN is stretched with PBKDF2-HMAC-SHA256 (100k iterations) over a
//     random salt — an extracted hash is far slower to brute-force than a bare
//     SHA-256, and the compare is constant-time.
//   * Wrong-PIN attempts are counted and trigger an escalating lockout, so the
//     on-screen keypad can't be exhaustively guessed.
//   * Biometric verification is delegated to the OS (the app never sees the
//     fingerprint/face data).
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _kLockEnabled = 'lock_enabled';
  static const _kBiometricEnabled = 'biometric_enabled';
  static const _kPinHash = 'pin_hash';
  static const _kPinSalt = 'pin_salt';
  static const _kPinLen = 'pin_len';
  static const _kFails = 'pin_fails';
  static const _kLockUntil = 'pin_lock_until';

  static const int _pbkdf2Iterations = 100000;
  static const int _lockThreshold = 5; // attempts before lockout kicks in

  final _localAuth = LocalAuthentication();

  /// One-shot guard against the resume-time auto-relock. Flows that
  /// intentionally background the app (the backup file picker / share sheet)
  /// set this true; the next app-resume relock check consumes it and skips
  /// locking once, so returning from the picker doesn't interrupt an in-progress
  /// restore with a PIN / fingerprint prompt.
  static bool suppressAutoLock = false;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<bool> lockEnabled() async =>
      (await _prefs).getBool(_kLockEnabled) ?? false;

  Future<bool> biometricEnabled() async =>
      (await _prefs).getBool(_kBiometricEnabled) ?? false;

  Future<bool> hasPin() async =>
      ((await _prefs).getString(_kPinHash) ?? '').isNotEmpty;

  Future<void> setLockEnabled(bool v) async =>
      (await _prefs).setBool(_kLockEnabled, v);

  Future<void> setBiometricEnabled(bool v) async =>
      (await _prefs).setBool(_kBiometricEnabled, v);

  /// A lock is only usable if at least one real factor is configured.
  /// Used to fail *closed* (never auto-open a misconfigured lock).
  Future<bool> hasUsableFactor() async {
    if (await hasPin()) return true;
    return (await biometricEnabled()) && (await canUseBiometrics());
  }

  Future<bool> canUseBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  /// Biometric OR device-credential (PIN/pattern/password) via the OS.
  Future<bool> authenticateBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock your NQE ledger',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'NQE — Unlock',
            biometricHint: '',
            cancelButton: 'Use PIN',
          ),
        ],
      );
    } catch (_) {
      return false;
    }
  }

  // ---- PIN ------------------------------------------------------------------
  String _randomSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes);
  }

  Future<String> _hash(String pin, String salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode('$pin::nqe')),
      nonce: base64Url.decode(salt),
    );
    final bytes = await key.extractBytes();
    return base64Url.encode(bytes);
  }

  /// Constant-time string comparison to avoid timing side-channels.
  bool _constEq(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> setPin(String pin) async {
    final prefs = await _prefs;
    final salt = _randomSalt();
    final hash = await _hash(pin, salt);
    await prefs.setString(_kPinSalt, salt);
    await prefs.setString(_kPinHash, hash);
    // Store the length (not sensitive) so the lock screen only checks a
    // *complete* PIN — never partial entries, which would spam the counter.
    await prefs.setInt(_kPinLen, pin.length);
    await _clearFailures();
  }

  /// The configured PIN length (0 if none). Lets the keypad auto-submit at the
  /// right length instead of guessing on every keypress.
  Future<int> pinLength() async => (await _prefs).getInt(_kPinLen) ?? 0;

  /// The PBKDF2 iteration count baked into every hash. Exposed so a paired
  /// device can mirror the exact derivation parameters.
  int get pbkdf2Iterations => _pbkdf2Iterations;

  /// Export the PIN credential (hash + salt + length + iterations) for secure
  /// transfer to a paired desktop. Returns null when no PIN is set. The hash is
  /// already a slow PBKDF2 digest — never the PIN itself — so this is safe to
  /// hand over the (separately encrypted) pairing channel.
  Future<Map<String, dynamic>?> exportPinCredential() async {
    final prefs = await _prefs;
    final hash = prefs.getString(_kPinHash) ?? '';
    final salt = prefs.getString(_kPinSalt) ?? '';
    final len = prefs.getInt(_kPinLen) ?? 0;
    if (hash.isEmpty || salt.isEmpty || len <= 0) return null;
    return {
      'hash': hash,
      'salt': salt,
      'len': len,
      'iter': _pbkdf2Iterations,
    };
  }

  /// Adopt a PIN credential mirrored from a paired phone so this device unlocks
  /// with the exact same PIN. The derivation (algorithm, iterations, salt) is
  /// identical across builds, so verifying a typed PIN against the imported
  /// hash Just Works. Enables the lock as a side effect.
  Future<void> importPinCredential({
    required String hash,
    required String salt,
    required int len,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(_kPinHash, hash);
    await prefs.setString(_kPinSalt, salt);
    await prefs.setInt(_kPinLen, len);
    await prefs.setBool(_kLockEnabled, true);
    await _clearFailures();
  }

  Future<void> clearPin() async {
    final prefs = await _prefs;
    await prefs.remove(_kPinSalt);
    await prefs.remove(_kPinHash);
    await prefs.remove(_kPinLen);
    await _clearFailures();
  }

  Future<bool> _verifyPin(String pin) async {
    final prefs = await _prefs;
    final salt = prefs.getString(_kPinSalt) ?? '';
    final stored = prefs.getString(_kPinHash) ?? '';
    if (salt.isEmpty || stored.isEmpty) return false;
    final hash = await _hash(pin, salt);
    return _constEq(hash, stored);
  }

  // ---- Lockout --------------------------------------------------------------
  /// Seconds remaining in the current lockout (0 if not locked).
  Future<int> lockoutRemaining() async {
    final prefs = await _prefs;
    final until = prefs.getInt(_kLockUntil) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (until <= now) return 0;
    return ((until - now) / 1000).ceil();
  }

  Future<int> _failCount() async => (await _prefs).getInt(_kFails) ?? 0;

  Future<void> _clearFailures() async {
    final prefs = await _prefs;
    await prefs.remove(_kFails);
    await prefs.remove(_kLockUntil);
  }

  Future<void> _registerFailure() async {
    final prefs = await _prefs;
    final fails = (prefs.getInt(_kFails) ?? 0) + 1;
    await prefs.setInt(_kFails, fails);
    if (fails >= _lockThreshold) {
      // Escalating backoff: 30s, 60s, 120s, ... capped at 15 min.
      final over = fails - _lockThreshold; // 0,1,2,...
      final seconds = min(900, 30 * pow(2, over).toInt());
      final until =
          DateTime.now().millisecondsSinceEpoch + seconds * 1000;
      await prefs.setInt(_kLockUntil, until);
    }
  }

  /// Submit a PIN attempt. Honors lockout, manages the failure counter.
  /// Returns true only on a correct PIN.
  Future<bool> submitPin(String pin) async {
    if (await lockoutRemaining() > 0) return false;
    final ok = await _verifyPin(pin);
    if (ok) {
      await _clearFailures();
      return true;
    }
    await _registerFailure();
    return false;
  }

  Future<int> failedAttempts() => _failCount();
}
