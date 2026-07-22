#!/usr/bin/env bash
# Regenerates the Android platform folder (not committed) and patches it for the
# app's needs: biometric-capable activity, required permissions, and minSdk.
set -euo pipefail

ORG="com.willong"
PKG="com.willong.nqe"

echo "==> flutter create (android platform files)"
flutter create . --platforms=android --org "$ORG" --project-name nqe

APP="android/app"
MANIFEST="$APP/src/main/AndroidManifest.xml"

echo "==> Injecting permissions into AndroidManifest.xml"
if ! grep -q "USE_BIOMETRIC" "$MANIFEST"; then
  perl -0pi -e 's/(<manifest[^>]*>)/$1\n    <uses-permission android:name="android.permission.INTERNET"\/>\n    <uses-permission android:name="android.permission.USE_BIOMETRIC"\/>\n    <uses-permission android:name="android.permission.USE_FINGERPRINT"\/>/s' "$MANIFEST"
fi

echo "==> Setting MainActivity to FlutterFragmentActivity (required by local_auth)"
MA="$(find "$APP/src/main" -name 'MainActivity.kt' | head -n1 || true)"
if [ -n "${MA:-}" ]; then
  cat > "$MA" <<KOT
package $PKG

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
KOT
  echo "    patched: $MA"
else
  echo "    WARNING: MainActivity.kt not found"
fi

echo "==> Forcing minSdk = 23 (biometric prompt)"
# Handles both Kotlin-DSL and Groovy templates, and both the newer
# `minSdk = flutter.minSdkVersion` and the legacy `minSdkVersion 21` forms.
for G in "$APP/build.gradle.kts" "$APP/build.gradle"; do
  [ -f "$G" ] || continue
  sed -i -E 's/minSdk[[:space:]]*=[[:space:]]*[A-Za-z0-9._]+/minSdk = 23/' "$G" || true
  sed -i -E 's/minSdkVersion[[:space:]]+[A-Za-z0-9._]+/minSdkVersion 23/' "$G" || true
  if grep -Eq 'minSdk[[:space:]]*=[[:space:]]*23|minSdkVersion[[:space:]]+23' "$G"; then
    echo "    minSdk set in $G"
  else
    echo "    NOTE: minSdk pattern not found in $G"
  fi
done

echo "==> Android prepared."
