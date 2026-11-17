#!/bin/bash
# Remove legion-aw88399 (any version) and return to the stock Ubuntu modules.
# linux-source-7.0.0 stays installed. Remove it yourself with `sudo apt remove linux-source-7.0.0`.
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
PKG=legion-aw88399
for v in $(dkms status -m $PKG 2>/dev/null | sed -n "s|^$PKG/\([^,]*\),.*|\1|p" | sort -u); do
	dkms remove -m $PKG -v "$v" --all
done
for d in /usr/src/$PKG-*; do [ -d "$d" ] && rm -rf -- "$d"; done
rm -f /etc/modprobe.d/legion-aw88399.conf \
	/lib/firmware/updates/awinic/aw88399_acf_17aa3906.bin /lib/firmware/updates/awinic/aw88399_acf_17aa3907.bin \
	/etc/apt/apt.conf.d/99legion-aw88399 /etc/xdg/autostart/legion-aw88399-check.desktop \
	/usr/local/sbin/legion-aw88399-rebuild /usr/local/sbin/legion-aw88399-diagnostics
rm -rf /usr/lib/legion-aw88399 /var/lib/legion-aw88399
rmdir --ignore-fail-on-non-empty /lib/firmware/updates/awinic 2>/dev/null
depmod -a
echo "Removed. Reboot to load the stock drivers again."
