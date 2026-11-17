#!/bin/bash
# Remove legion-aw88399 2.0 and return to the stock Ubuntu modules.
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
dkms remove -m legion-aw88399 -v 2.0 --all
[ -d /usr/src/legion-aw88399-2.0 ] && rm -rf -- /usr/src/legion-aw88399-2.0
rm -f /etc/modprobe.d/legion-aw88399.conf /lib/firmware/updates/awinic/aw88399_acf_17aa3907.bin
rmdir --ignore-fail-on-non-empty /lib/firmware/updates/awinic 2>/dev/null
depmod -a
echo "Removed. Reboot to load the stock drivers again."
