#!/bin/bash
# Downloads the pinned mihomo (android-arm64), metacubexd panel and GeoIP database into deps/ and checks them.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); D=$ROOT/deps; mkdir -p "$D"; cd "$D"
MIHOMO=v1.19.32; XD=v1.273.1
get() { [ -f "$2" ] && echo "$3  $2" | sha256sum -c --quiet 2>/dev/null && return; curl -fL --retry 3 -o "$2" "$1"; echo "$3  $2" | sha256sum -c; }
get https://github.com/MetaCubeX/mihomo/releases/download/$MIHOMO/mihomo-android-arm64-v8-$MIHOMO.gz mihomo.gz \
    42b1f2be8702484d3ae6238daab392622f54bd0d264966700f1f28f52596e326
get https://github.com/MetaCubeX/metacubexd/releases/download/$XD/compressed-dist.tgz metacubexd.tgz \
    a178e00b67acabcda2dcef00afa90be6a7bb261e466a67dad58c8478d9553603
# meta-rules-dat "latest" moves; a hash mismatch here only means a newer database, check it and update the hash.
get https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb country.mmdb \
    ad2a3b90848bccd2065545e295de53b324931f710e0077a1a0fae2b89fddc5e5
gunzip -kf mihomo.gz
rm -rf ui && mkdir ui && tar -xzf metacubexd.tgz -C ui
echo "deps ready in $D"
