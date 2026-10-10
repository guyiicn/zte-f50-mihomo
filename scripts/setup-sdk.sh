#!/bin/bash
# Installs adb, the Android build tools and platform 33 into .sdk/ (no root needed). Needs a JDK 17 in JAVA_HOME.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); SDK=$ROOT/.sdk; mkdir -p "$SDK/dl"; cd "$SDK/dl"
: "${JAVA_HOME:?set JAVA_HOME to a JDK 17 (e.g. mise install java@temurin-17)}"
export PATH=$JAVA_HOME/bin:$PATH
[ -x "$SDK/platform-tools/adb" ] || { curl -fLO https://dl.google.com/android/repository/platform-tools-latest-linux.zip; unzip -qo platform-tools-latest-linux.zip -d "$SDK"; }
[ -x "$SDK/cmdline-tools/bin/sdkmanager" ] || { curl -fLO https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip; unzip -qo commandlinetools-linux-11076708_latest.zip -d "$SDK"; }
yes | "$SDK/cmdline-tools/bin/sdkmanager" --sdk_root="$SDK" "build-tools;34.0.0" "platforms;android-33" >/dev/null
echo "SDK ready in $SDK"
