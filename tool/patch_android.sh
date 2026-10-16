#!/usr/bin/env bash
# Runs inside app/ right after `flutter create`. Patches the generated Android project.
set -euo pipefail

M=android/app/src/main/AndroidManifest.xml
sed -i 's#<manifest xmlns:android="http://schemas.android.com/apk/res/android">#&\n    <uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.RECORD_AUDIO"/>#' "$M"
sed -i 's#android:label="[^"]*"#android:label="PDI CHATS"#' "$M"
grep -q 'android.permission.INTERNET' "$M"
grep -q 'android.permission.RECORD_AUDIO' "$M"

for f in android/app/build.gradle.kts android/app/build.gradle; do
  if [ -f "$f" ]; then
    sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 24/; s/minSdkVersion flutter.minSdkVersion/minSdkVersion 24/' "$f"
  fi
done

# Fixed signing key, so new versions install over the old one.
KS="$PWD/android/app/release.keystore"
PASS="pdichats-sign-2026"
mkdir -p /tmp/ks
if gh release download pdi-keystore --pattern release.keystore --dir /tmp/ks --clobber >/dev/null 2>&1; then
  cp /tmp/ks/release.keystore "$KS"
else
  keytool -genkeypair -storetype JKS -keystore "$KS" -storepass "$PASS" -keypass "$PASS" -alias pdichats -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=PDI CHATS, O=PDI"
  gh release create pdi-keystore "$KS" --title "signing key" --notes "Do not delete. Keeps app updates installable."
fi

echo >> android/gradle.properties
cat >> android/gradle.properties <<EOF
android.injected.signing.store.file=$KS
android.injected.signing.store.password=$PASS
android.injected.signing.key.alias=pdichats
android.injected.signing.key.password=$PASS
EOF
