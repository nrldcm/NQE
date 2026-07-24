#!/usr/bin/env bash
# Regenerates the Android platform folder (not committed) and hardens it:
#   * biometric-capable activity (FlutterFragmentActivity) + FLAG_SECURE
#     (blocks screenshots and the app-switcher preview of financial data)
#   * scoped permissions: biometric, internet (live charts), LAN sync + a
#     foreground service (dataSync) so the sync server survives screen-off
#   * android:allowBackup="false" so the ledger DB / prefs can't be pulled via
#     cloud auto-backup or `adb backup`
#   * minSdk 23 (biometric prompt)
# A failed/mis-applied patch is a hard error (never ship an unhardened build).
set -euo pipefail

ORG="com.willong"
PKG="com.willong.nqe"

echo "==> flutter create (android platform files)"
flutter create . --platforms=android --org "$ORG" --project-name nqe

APP="android/app"
MANIFEST="$APP/src/main/AndroidManifest.xml"

echo "==> Injecting permissions (biometric, internet, LAN-sync foreground service)"
if ! grep -q "USE_BIOMETRIC" "$MANIFEST"; then
  perl -0pi -e 's/(<manifest[^>]*>)/$1\n    <uses-permission android:name="android.permission.USE_BIOMETRIC"\/>\n    <uses-permission android:name="android.permission.INTERNET"\/>\n    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"\/>\n    <uses-permission android:name="android.permission.WAKE_LOCK"\/>\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"\/>\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"\/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"\/>\n    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"\/>/s' "$MANIFEST"
fi

echo "==> Declaring the foreground service (dataSync) for background LAN sync"
# flutter_foreground_task 8.x does NOT declare its service in the plugin
# manifest — the app must, and Android 14+ requires an explicit
# foregroundServiceType or startForegroundService throws. Without this the
# background sync server dies when the screen locks.
if ! grep -q "flutter_foreground_task.service.ForegroundService" "$MANIFEST"; then
  perl -0pi -e 's/(<application\b[^>]*>)/$1\n        <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" android:foregroundServiceType="dataSync" android:exported="false" android:stopWithTask="false"\/>/s' "$MANIFEST"
fi

echo "==> Disabling backup (android:allowBackup=\"false\")"
if ! grep -q 'android:allowBackup="false"' "$MANIFEST"; then
  # Add/replace allowBackup on the <application> tag.
  if grep -q 'android:allowBackup=' "$MANIFEST"; then
    perl -0pi -e 's/android:allowBackup="[^"]*"/android:allowBackup="false"/s' "$MANIFEST"
  else
    perl -0pi -e 's/(<application\b)/$1 android:allowBackup="false"/s' "$MANIFEST"
  fi
fi

echo "==> MainActivity: FlutterFragmentActivity + FLAG_SECURE + security channel"
MA="$(find "$APP/src/main" -name 'MainActivity.kt' | head -n1 || true)"
if [ -n "${MA:-}" ]; then
  cat > "$MA" <<KOT
package $PKG

import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val securityChannel = "com.willong.nqe/security"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots and hide app content in the recents/app-switcher.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, securityChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "devOptionsEnabled" -> result.success(isDevOptionsEnabled())
                    else -> result.notImplemented()
                }
            }
    }

    // True when Developer options or USB debugging is switched on.
    private fun isDevOptionsEnabled(): Boolean {
        return try {
            val dev = Settings.Global.getInt(
                contentResolver,
                Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0
            )
            val adb = Settings.Global.getInt(
                contentResolver, Settings.Global.ADB_ENABLED, 0
            )
            dev == 1 || adb == 1
        } catch (e: Exception) {
            false
        }
    }
}
KOT
  echo "    patched: $MA"
else
  echo "ERROR: MainActivity.kt not found" >&2
  exit 1
fi

echo "==> Forcing minSdk = 23 (biometric prompt)"
for G in "$APP/build.gradle.kts" "$APP/build.gradle"; do
  [ -f "$G" ] || continue
  sed -i -E 's/minSdk[[:space:]]*=[[:space:]]*[A-Za-z0-9._]+/minSdk = 23/' "$G" || true
  sed -i -E 's/minSdkVersion[[:space:]]+[A-Za-z0-9._]+/minSdkVersion 23/' "$G" || true
done

echo "==> Verifying hardening applied"
fail=0
grep -q "USE_BIOMETRIC" "$MANIFEST" || { echo "MISSING: USE_BIOMETRIC" >&2; fail=1; }
grep -q 'android:allowBackup="false"' "$MANIFEST" || { echo "MISSING: allowBackup=false" >&2; fail=1; }
grep -Eqr 'minSdk[[:space:]]*=[[:space:]]*23|minSdkVersion[[:space:]]+23' "$APP"/build.gradle* \
  || { echo "MISSING: minSdk=23" >&2; fail=1; }
grep -q "android.permission.INTERNET" "$MANIFEST" \
  || { echo "MISSING: INTERNET (needed for live charts)" >&2; fail=1; }
grep -q "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" "$MANIFEST" \
  || { echo "MISSING: REQUEST_IGNORE_BATTERY_OPTIMIZATIONS (background sync)" >&2; fail=1; }
grep -q "flutter_foreground_task.service.ForegroundService" "$MANIFEST" \
  || { echo "MISSING: ForegroundService declaration (background sync)" >&2; fail=1; }
grep -q 'android:foregroundServiceType="dataSync"' "$MANIFEST" \
  || { echo "MISSING: foregroundServiceType=dataSync (Android 14+)" >&2; fail=1; }
if [ "$fail" -ne 0 ]; then
  echo "ERROR: Android hardening did not fully apply — failing the build." >&2
  exit 1
fi

echo "==> Android prepared and hardened."
