#!/bin/bash
# Builds out/f50-mihomo.apk from app/, build/config.yaml (scripts/prepare-config.py) and deps/ (scripts/fetch-deps.sh).
# Env: JAVA_HOME (JDK 17), F50_HOST (panel default backend, 192.168.0.1), KEYSTORE / KS_PASS (signing; one is made in .keys/).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
: "${JAVA_HOME:?set JAVA_HOME to a JDK 17}"; export PATH=$JAVA_HOME/bin:$PATH
SDK=$ROOT/.sdk; BT=$SDK/build-tools/34.0.0; JAR=$SDK/platforms/android-33/android.jar
[ -f build/config.yaml ] || { echo "run scripts/prepare-config.py first" >&2; exit 1; }
[ -f deps/mihomo ] || { echo "run scripts/fetch-deps.sh first" >&2; exit 1; }
VC=${VERSION_CODE:-$(( $(date +%s) / 60 ))}
O=$ROOT/build/out; rm -rf "$O"; mkdir -p "$O/assets" "$O/classes" "$O/apk" "$ROOT/out"
cp build/config.yaml "$O/assets/config.yaml"
cp deps/country.mmdb "$O/assets/country.mmdb"
cp -r deps/ui "$O/assets/ui"; cp config/proxy.pac "$O/assets/ui/proxy.pac"
sed -i "s|defaultBackendURL: ''|defaultBackendURL: 'http://${F50_HOST:-192.168.0.1}:19090'|" "$O/assets/ui/config.js"
# The service keeps its log under ui/<secret>/ so that the panel serves it only to holders of the secret.
python3 -c 'import sys,yaml;print(yaml.safe_load(open(sys.argv[1],encoding="utf-8"))["secret"])' build/config.yaml > "$O/assets/logkey"
"$BT/aapt2" compile --dir app/res -o "$O/res.zip"
"$BT/aapt2" link -o "$O/apk/unsigned.apk" -I "$JAR" --manifest app/AndroidManifest.xml -A "$O/assets" \
    --min-sdk-version 26 --target-sdk-version 33 --version-code "$VC" --version-name "1.19.32-$VC" "$O/res.zip"
javac -source 8 -target 8 -bootclasspath "$JAR" -nowarn -Xlint:-options -d "$O/classes" $(find app/src -name '*.java') 2>&1 | grep -v '^Note:' || true
"$BT/d8" --lib "$JAR" --min-api 26 --release --output "$O/apk" $(find "$O/classes" -name '*.class')
mkdir -p "$O/apk/lib/arm64-v8a"; cp deps/mihomo "$O/apk/lib/arm64-v8a/libmihomo.so"
(cd "$O/apk" && zip -q unsigned.apk classes.dex lib/arm64-v8a/libmihomo.so)
"$BT/zipalign" -f -p 4 "$O/apk/unsigned.apk" "$O/apk/aligned.apk"
KS=${KEYSTORE:-$ROOT/.keys/signing.jks}; KS_PASS=${KS_PASS:-f50mihomo}
[ -f "$KS" ] || { mkdir -p "$(dirname "$KS")"; keytool -genkeypair -keystore "$KS" -storepass "$KS_PASS" -keypass "$KS_PASS" \
    -alias f50 -keyalg RSA -keysize 2048 -validity 10000 -dname CN=f50mihomo >/dev/null 2>&1; }
"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$KS_PASS" --out out/f50-mihomo.apk "$O/apk/aligned.apk"
"$BT/apksigner" verify out/f50-mihomo.apk
echo "built out/f50-mihomo.apk (versionCode $VC, $(du -h out/f50-mihomo.apk | cut -f1))"
