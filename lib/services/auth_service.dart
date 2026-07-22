// App lock: biometric (fingerprint / face) with a PIN fallback.
//
// The PIN is never stored in clear — only a salted SHA-256 hash lives in
// shared_preferences. Biometric verification is delegated to the OS via
// local_auth (the app never sees the fingerprint/face data).
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

  final _localAuth = LocalAuthentication();

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

  /// Whether the device actually has biometric hardware available.
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
    final digest =
        await Sha256().hash(utf8.encode('$salt::$pin::nqe'));
    return base64Url.encode(digest.bytes);
  }

  Future<void> setPin(String pin) async {
    final prefs = await _prefs;
    final salt = _randomSalt();
    final hash = await _hash(pin, salt);
    await prefs.setString(_kPinSalt, salt);
    await prefs.setString(_kPinHash, hash);
  }

  Future<void> clearPin() async {
    final prefs = await _prefs;
    await prefs.remove(_kPinSalt);
    await prefs.remove(_kPinHash);
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await _prefs;
    final salt = prefs.getString(_kPinSalt) ?? '';
    final stored = prefs.getString(_kPinHash) ?? '';
    if (salt.isEmpty || stored.isEmpty) return false;
    final hash = await _hash(pin, salt);
    return hash == stored;
  }
}
