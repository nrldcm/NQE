// Lightweight anti-tamper probe: is Android "Developer options" (or USB
// debugging) currently enabled? Read over a MethodChannel backed by
// Settings.Global on the native side. Fail-open (false) everywhere the check
// doesn't apply — off Android, on the desktop build, or on any error — so the
// app can never brick itself where the signal is unavailable.
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class DeviceIntegrity {
  DeviceIntegrity._();

  static const MethodChannel _ch = MethodChannel('com.willong.nqe/security');

  /// True when Developer options or USB debugging is switched on (Android only).
  static Future<bool> developerOptionsEnabled() async {
    // Fail-open on web: `Platform` is dart:io and unavailable in the browser,
    // and there is no Android dev-options signal there anyway.
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return false;
    try {
      final v = await _ch.invokeMethod<bool>('devOptionsEnabled');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }
}
