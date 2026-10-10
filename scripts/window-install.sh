#!/bin/bash
# Installs out/f50-mihomo.apk through the ~10 s of ADB the F50 gives at every boot, then starts it once.
# Needs the "USB port" switch on (scripts/zte-web.py adb-on). Retries over up to 5 reboots.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); A=${ADB:-$ROOT/.sdk/platform-tools/adb}; APK=$ROOT/out/f50-mihomo.apk; PKG=local.f50mihomo
SUM=$(sha256sum "$APK" | cut -d' ' -f1)
VC=$("$ROOT/.sdk/build-tools/34.0.0/aapt2" dump badging "$APK" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")
for round in 1 2 3 4 5; do
  echo "== round $round: rebooting"
  for t in $(seq 1 30); do python3 "$ROOT/scripts/zte-web.py" reboot >/dev/null 2>&1 && break; sleep 3; done
  T0=$SECONDS; until [ "$($A get-state 2>/dev/null)" = device ]; do sleep 0.2; [ $((SECONDS-T0)) -gt 150 ] && { echo "no adb: is the USB port switch on?"; exit 1; }; done
  echo "$((SECONDS-T0))s adb up"
  # Push only when the device copy differs (two builds can have the same size).
  have=$($A shell "sha256sum /data/local/tmp/f50-mihomo.apk 2>/dev/null" | cut -d' ' -f1)
  [ "$have" = "$SUM" ] || $A push "$APK" /data/local/tmp/f50-mihomo.apk 2>&1 | tail -1
  # pm/am refuse to work until boot completes; ZTE's USB service drops adb about 5 s after that.
  out=$($A shell "
    for i in \$(seq 1 100); do [ \"\$(getprop sys.boot_completed)\" = 1 ] && break; sleep 0.1; done
    v=\$(dumpsys package $PKG | grep -m1 versionCode= | sed 's/.*versionCode=\([0-9]*\).*/\1/')
    [ \"\$v\" = $VC ] || pm install -r -g /data/local/tmp/f50-mihomo.apk
    cmd deviceidle whitelist +$PKG
    am start -n $PKG/.MainActivity
    echo DONE \$(dumpsys package $PKG | grep -m1 versionCode=)
  " 2>&1 | tr -d '\r')
  echo "$out" | grep -vE '^\s+at '
  echo "$out" | grep -q "DONE.*versionCode=$VC" && echo "$out" | grep -q "Starting: Intent" && { echo "installed and started"; exit 0; }
  echo "window closed before finishing; trying again"; while [ "$($A get-state 2>/dev/null)" = device ]; do sleep 0.5; done
done
exit 1
