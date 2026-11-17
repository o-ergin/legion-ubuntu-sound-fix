#!/bin/bash
# Install legion-aw88399 2.1: AW88399 woofer amplifiers for the Lenovo Legion Pro 7 16IAX10H
# (Intel, 83F5) on Ubuntu 7.0.0-NN-generic kernels. See README.md.
#
#   sudo ./scripts/install.sh                     # tested configuration: DMI 83F5 + codec 17aa:3907
#   sudo ./scripts/install.sh --allow-untested    # also accepts codec 17aa:3906 or another DMI product
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PKG=legion-aw88399; VER=2.1
FW="$HERE/firmware/aw88399_acf_17aa3907.bin"
FW_SHA=1e927c9bca76d868181c0f81df2bccef3cf19c7d0910219f229360c87babd42c
UNTESTED=no
for a in "$@"; do
	case "$a" in
	--allow-untested) UNTESTED=yes ;;
	*) echo "Unknown option: $a"; exit 1 ;;
	esac
done

# --- Preconditions -------------------------------------------------------------------------------
[ -e /sys/bus/acpi/devices/AWDZ8399:00 ] || { echo "No ACPI AWDZ8399 device: this laptop has no AW88399 amps. Aborting."; exit 1; }
SSID=$(grep -hos "Subsystem Id: 0x17aa390[67]" /proc/asound/card*/codec#* | head -n1 | sed 's/.*0x//') || true
PRODUCT=$(cat /sys/class/dmi/id/product_name)
case "$SSID" in
17aa3907) ;;
17aa3906) [ $UNTESTED = yes ] || { echo "Codec SSID 17aa:3906 is supported by mainline but untested here. Re-run with --allow-untested."; exit 1; } ;;
*) echo "Codec SSID 17aa:3906/3907 not found. Aborting."; exit 1 ;;
esac
if [ "$PRODUCT" != 83F5 ] && [ $UNTESTED != yes ]; then
	echo "DMI product is '$PRODUCT', not 83F5 (Legion Pro 7 16IAX10H). Re-run with --allow-untested to try anyway."; exit 1
fi
[ -f "$FW" ] || { echo "Firmware missing: run scripts/fetch-firmware.sh first."; exit 1; }
echo "$FW_SHA  $FW" | sha256sum -c --quiet || { echo "Firmware checksum mismatch. Aborting."; exit 1; }
command -v dkms >/dev/null || { echo "Install dkms first: sudo apt install dkms"; exit 1; }
K=$(uname -r)
[[ "$K" =~ ^7\.0\.0-[0-9]+-generic$ ]] || { echo "Running kernel $K is not an Ubuntu 7.0.0-NN-generic kernel. Aborting."; exit 1; }
[ "$(dpkg-query -W -f='${Version}' linux-source-7.0.0 2>/dev/null)" = "$(dpkg-query -W -f='${Version}' "linux-modules-$K")" ] ||
	{ echo "linux-source-7.0.0 must match the running kernel. Run: sudo apt install linux-source-7.0.0"; exit 1; }

# --- 1. Firmware ---------------------------------------------------------------------------------
# The driver loads awinic/aw88399_acf_<ACPI _SUB>.bin. sysfs does not expose _SUB, and the DSDT
# picks 3906 or 3907 at runtime. linux-firmware ships both names as byte-identical files, so install both.
for n in 17aa3906 17aa3907; do install -D -m 0644 "$FW" "/lib/firmware/updates/awinic/aw88399_acf_$n.bin"; done

# --- 2. Keep the 7.0 ASoC driver (snd_soc_aw88399) from claiming the AWDZ8399 node ---------------
printf '# legion-aw88399: the HDA side-codec driver owns ACPI AWDZ8399\nblacklist snd_soc_aw88399\n' \
	> /etc/modprobe.d/legion-aw88399.conf

# --- 3. Modules via DKMS (replaces any earlier version) ------------------------------------------
for old in $(dkms status -m $PKG 2>/dev/null | sed -n "s|^$PKG/\([^,]*\),.*|\1|p" | sort -u); do
	dkms remove -m $PKG -v "$old" --all
done
for d in /usr/src/$PKG-*; do [ -d "$d" ] && rm -rf -- "$d"; done
cp -r "$HERE/dkms" /usr/src/$PKG-$VER
chmod +x /usr/src/$PKG-$VER/prepare.sh
dkms add -m $PKG -v $VER
dkms install -m $PKG -v $VER -k "$K"
compgen -G "/lib/modules/$K/updates/dkms/snd-hda-scodec-aw88399-legion.ko*" >/dev/null ||
	{ echo "DKMS did not install the module for $K. See /var/lib/dkms/$PKG/$VER/build/make.log"; exit 1; }

# --- 4. Survive kernel updates ---------------------------------------------------------------------
install -D -m 0755 "$HERE/system/apt-hook.sh"               /usr/lib/legion-aw88399/apt-hook
install -D -m 0755 "$HERE/system/login-check.sh"            /usr/lib/legion-aw88399/login-check
install -D -m 0644 "$HERE/system/99legion-aw88399"          /etc/apt/apt.conf.d/99legion-aw88399
install -D -m 0644 "$HERE/system/legion-aw88399-check.desktop" /etc/xdg/autostart/legion-aw88399-check.desktop
install -D -m 0755 "$HERE/system/legion-aw88399-rebuild.sh" /usr/local/sbin/legion-aw88399-rebuild
install -D -m 0755 "$HERE/scripts/diagnostics.sh"           /usr/local/sbin/legion-aw88399-diagnostics
apt-mark manual linux-source-7.0.0 >/dev/null   # keep apt autoremove from removing it
rm -rf /var/lib/legion-aw88399

echo
echo "Installed $PKG $VER for $K."
echo "If this is the first install: turn the speaker volume down to ~15-20%, then reboot."
echo "Check afterwards: sudo legion-aw88399-diagnostics"
