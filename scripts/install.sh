#!/bin/bash
# Install legion-aw88399 2.0: AW88399 woofer amplifiers for Lenovo Legion Pro 7 16IAX10H
# (Intel, 83F5, codec SSID 17aa:3907) on Ubuntu 7.0.0-NN-generic kernels. See README.md.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PKG=legion-aw88399; VER=2.0
FW="$HERE/firmware/aw88399_acf_17aa3907.bin"
FW_SHA=1e927c9bca76d868181c0f81df2bccef3cf19c7d0910219f229360c87babd42c

# Preconditions: refuse on anything that is not exactly this machine/configuration.
[ "$(cat /sys/class/dmi/id/product_name)" = "83F5" ] || { echo "Not a Legion Pro 7 16IAX10H (83F5). Aborting."; exit 1; }
grep -qs "Subsystem Id: 0x17aa3907" /proc/asound/card*/codec#* || { echo "Codec SSID 17aa:3907 not found. Aborting."; exit 1; }
[ -f "$FW" ] || { echo "Firmware missing: run scripts/fetch-firmware.sh first."; exit 1; }
echo "$FW_SHA  $FW" | sha256sum -c --quiet || { echo "Firmware checksum mismatch. Aborting."; exit 1; }
command -v dkms >/dev/null || { echo "Install dkms first: sudo apt install dkms"; exit 1; }
[ "$(dpkg-query -W -f='${Version}' linux-source-7.0.0 2>/dev/null)" = "$(dpkg-query -W -f='${Version}' linux-image-"$(uname -r)")" ] ||
	{ echo "linux-source-7.0.0 must match the running kernel. Run: sudo apt install linux-source-7.0.0"; exit 1; }

# 1. Firmware (byte-identical to linux-firmware awinic/aw88399_acf_17aa3907.bin).
install -D -m 0644 "$FW" /lib/firmware/updates/awinic/aw88399_acf_17aa3907.bin

# 2. Keep the 7.0 ASoC driver (snd_soc_aw88399) from claiming the AWDZ8399 node.
printf '# legion-aw88399: the HDA side-codec driver owns ACPI AWDZ8399\nblacklist snd_soc_aw88399\n' \
	> /etc/modprobe.d/legion-aw88399.conf

# 3. Modules via DKMS.
if dkms status -m $PKG -v $VER | grep -q .; then dkms remove -m $PKG -v $VER --all; fi
[ -d /usr/src/$PKG-$VER ] && rm -rf -- /usr/src/$PKG-$VER
cp -r "$HERE/dkms" /usr/src/$PKG-$VER
dkms add -m $PKG -v $VER
dkms build -m $PKG -v $VER -k "$(uname -r)"
dkms install -m $PKG -v $VER -k "$(uname -r)"

echo
echo "Installed. Turn the speaker volume down to ~15-20%, then reboot."
echo "After reboot: sudo $HERE/scripts/check-amps.sh"
