#!/bin/bash
# Reboots the F50 and runs one adb shell command in the boot-time ADB window, e.g.
#   scripts/window-shell.sh 'pm uninstall local.f50mihomo'
ROOT=$(cd "$(dirname "$0")/.." && pwd); A=${ADB:-$ROOT/.sdk/platform-tools/adb}
for t in $(seq 1 30); do python3 "$ROOT/scripts/zte-web.py" reboot >/dev/null 2>&1 && break; sleep 3; done
T0=$SECONDS; until [ "$($A get-state 2>/dev/null)" = device ]; do sleep 0.2; [ $((SECONDS-T0)) -gt 150 ] && { echo "no adb"; exit 1; }; done
$A shell "for i in \$(seq 1 100); do [ \"\$(getprop sys.boot_completed)\" = 1 ] && break; sleep 0.1; done; $1"
