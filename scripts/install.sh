#!/bin/bash
# Install legion-aw88399 2.2: AW88399 woofer amplifiers for the Lenovo Legion Pro 7 16IAX10H
# (Intel, 83F5) on Ubuntu. See README.md.
#
# The installer picks the mode from the running kernel:
#   - The kernel ships the AW88399 HDA driver (Ubuntu 26.10, kernel 7.3 and later): "stock" mode.
#     It installs only the Awinic tuning file, under the names the kernel's driver requests.
#   - Ubuntu 7.0.0-NN-generic (26.04): "backport" mode. It installs the DKMS backport of the mainline
#     driver, plus the kernel-update helpers.
#
#   sudo ./scripts/install.sh                     # tested configuration: DMI 83F5 + codec 17aa:3907
#   sudo ./scripts/install.sh --allow-untested    # also accepts codec 17aa:3906 or another DMI product
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PKG=legion-aw88399; VER=2.2
FW="$HERE/firmware/aw88399_acf_17aa3907.bin"
FW_SHA=1e927c9bca76d868181c0f81df2bccef3cf19c7d0910219f229360c87babd42c
UPD=/lib/firmware/updates
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

K=$(uname -r)
if modinfo -k "$K" snd-hda-scodec-aw88399 >/dev/null 2>&1; then
	MODE=stock
elif [[ "$K" =~ ^7\.0\.0-[0-9]+-generic$ ]]; then
	MODE=backport
	command -v dkms >/dev/null || { echo "Install dkms first: sudo apt install dkms"; exit 1; }
	[ "$(dpkg-query -W -f='${Version}' linux-source-7.0.0 2>/dev/null)" = "$(dpkg-query -W -f='${Version}' "linux-modules-$K")" ] ||
		{ echo "linux-source-7.0.0 must match the running kernel. Run: sudo apt install linux-source-7.0.0"; exit 1; }
else
	echo "Kernel $K neither ships the AW88399 HDA driver nor is an Ubuntu 7.0.0-NN-generic kernel. Aborting."; exit 1
fi
echo "Kernel $K: $MODE mode."

# --- 1. Firmware (both modes) --------------------------------------------------------------------
# These names are byte-identical copies of one file. The same file is linux-firmware's
# awinic/aw88399_acf_17aa3906.bin and _17aa3907.bin, and Lenovo's Windows AWDZ8399.bin.
#   awinic/aw88399_acf_<ACPI _SUB>.bin   requested by mainline 7.4+ and by this repo's 7.0 backport.
#                                        sysfs doesn't expose _SUB, so both names are installed.
#   aw88399_acf.bin                      requested by Ubuntu 26.10's 7.3 kernel. Installing it on 26.04
#                                        too keeps the woofers working after a release upgrade.
# The script also adds any other plain name the running kernel's driver declares.
names=(awinic/aw88399_acf_17aa3906.bin awinic/aw88399_acf_17aa3907.bin aw88399_acf.bin)
if [ $MODE = stock ]; then
	while read -r n; do
		[[ -n "$n" && "$n" != *'*'* && "$n" != *..* ]] && names+=("$n")
	done < <(modinfo -k "$K" -F firmware snd-hda-scodec-aw88399)
fi
for n in $(printf '%s\n' "${names[@]}" | sort -u); do
	install -D -m 0644 "$FW" "$UPD/$n"
	echo "firmware: $UPD/$n"
done
install -D -m 0755 "$HERE/scripts/diagnostics.sh"           /usr/local/sbin/legion-aw88399-diagnostics
install -D -m 0755 "$HERE/system/login-check.sh"            /usr/lib/legion-aw88399/login-check
install -D -m 0644 "$HERE/system/legion-aw88399-check.desktop" /etc/xdg/autostart/legion-aw88399-check.desktop

if [ $MODE = stock ]; then
	# --- 2s. Remove the 7.0 backport if a release upgrade left it behind. It never builds for this
	# kernel, and the blacklist isn't needed: 7.3 creates no plain i2c-AWDZ8399:00 client for
	# snd_soc_aw88399 to claim.
	for old in $(dkms status -m $PKG 2>/dev/null | sed -n "s|^$PKG/\([^,:]*\)[,:].*|\1|p" | sort -u); do
		dkms remove -m $PKG -v "$old" --all || true
	done
	for d in /usr/src/$PKG-*; do [ -d "$d" ] && rm -rf -- "$d"; done
	rm -f /etc/apt/apt.conf.d/99legion-aw88399 /usr/lib/legion-aw88399/apt-hook \
		/usr/local/sbin/legion-aw88399-rebuild /etc/modprobe.d/legion-aw88399.conf
	rm -rf /var/lib/legion-aw88399
	echo
	echo "Installed the AW88399 tuning file for the kernel's own driver ($K)."
	echo "Reboot, then check: sudo legion-aw88399-diagnostics"
	exit 0
fi

# --- 2b. Keep the 7.0 ASoC driver (snd_soc_aw88399) from claiming the AWDZ8399 node --------------
printf '# legion-aw88399: the HDA side-codec driver owns ACPI AWDZ8399\nblacklist snd_soc_aw88399\n' \
	> /etc/modprobe.d/legion-aw88399.conf

# --- 3b. Modules via DKMS (replaces any earlier version) -----------------------------------------
for old in $(dkms status -m $PKG 2>/dev/null | sed -n "s|^$PKG/\([^,:]*\)[,:].*|\1|p" | sort -u); do
	dkms remove -m $PKG -v "$old" --all
done
for d in /usr/src/$PKG-*; do [ -d "$d" ] && rm -rf -- "$d"; done
cp -r "$HERE/dkms" /usr/src/$PKG-$VER
chmod +x /usr/src/$PKG-$VER/prepare.sh
dkms add -m $PKG -v $VER
dkms install -m $PKG -v $VER -k "$K"
compgen -G "/lib/modules/$K/updates/dkms/snd-hda-scodec-aw88399-legion.ko*" >/dev/null ||
	{ echo "DKMS did not install the module for $K. See /var/lib/dkms/$PKG/$VER/build/make.log"; exit 1; }

# --- 4b. Survive kernel updates --------------------------------------------------------------------
install -D -m 0755 "$HERE/system/apt-hook.sh"               /usr/lib/legion-aw88399/apt-hook
install -D -m 0644 "$HERE/system/99legion-aw88399"          /etc/apt/apt.conf.d/99legion-aw88399
install -D -m 0755 "$HERE/system/legion-aw88399-rebuild.sh" /usr/local/sbin/legion-aw88399-rebuild
apt-mark manual linux-source-7.0.0 >/dev/null   # keep apt autoremove from removing it
rm -rf /var/lib/legion-aw88399

echo
echo "Installed $PKG $VER for $K."
echo "If this is the first install: turn the speaker volume down to ~15-20%, then reboot."
echo "Check afterwards: sudo legion-aw88399-diagnostics"
