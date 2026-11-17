#!/bin/bash
# Download the AW88399 tuning file from the official linux-firmware repository and verify it.
# The same file ships in Lenovo's Windows "Realtek Audio Driver" package as AWDZ8399.bin.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
URL="https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main/awinic/aw88399_acf_17aa3907.bin"
SHA=1e927c9bca76d868181c0f81df2bccef3cf19c7d0910219f229360c87babd42c
OUT="$HERE/firmware/aw88399_acf_17aa3907.bin"
mkdir -p "$HERE/firmware"
curl -fsSL -o "$OUT" "$URL"
echo "$SHA  $OUT" | sha256sum -c -
