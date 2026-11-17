#!/bin/bash
# legion-aw88399 login check, installed as /usr/lib/legion-aw88399/login-check.
# Runs as the logged-in user from /etc/xdg/autostart. Read-only. It shows a desktop notification
# only when the woofer amps should be active on the running kernel but aren't.
set -u
K=$(uname -r)
I2C=/sys/bus/i2c/devices
[ -e /sys/bus/acpi/devices/AWDZ8399:00 ] || exit 0                 # not this hardware
drv() { basename "$(readlink -f "$1/driver" 2>/dev/null)" 2>/dev/null; }
notify() {
	command -v notify-send >/dev/null && notify-send -u normal -i audio-speakers -a "Legion speakers" "$1" "$2"
	echo "$1: $2" >&2
	exit 0
}

if modinfo -k "$K" snd-hda-scodec-aw88399 >/dev/null 2>&1; then
	# Stock driver (Ubuntu 26.10 / kernel 7.3+): one client per amp, i2c-AWDZ8399:00-aw88399-hda.N.
	# If a client has no driver, its probe failed. The usual cause is a missing tuning file.
	n=0
	for d in "$I2C"/i2c-AWDZ8399:00-aw88399-hda.*; do
		[ -e "$d" ] || continue
		n=$((n + 1))
		[ "$(drv "$d")" = aw88399-hda ] ||
			notify "Speaker bass (woofers) not working" \
				"The AW88399 amp driver failed to start on kernel $K, most likely a missing tuning file. Re-run: sudo ./scripts/install.sh (legion-ubuntu-sound-fix), then reboot."
	done
	[ $n -gt 0 ] || notify "Speaker bass (woofers) not working" "Kernel $K has the AW88399 driver, but it created no amplifier devices. Run: sudo legion-aw88399-diagnostics"
	exit 0
fi

# 7.0 backport (Ubuntu 26.04).
[[ "$K" =~ ^7\.0\.0-[0-9]+-generic$ ]] || exit 0                    # kernel this package does not target
[ "$(drv "$I2C/i2c-AWDZ8399:00")" = aw88399-hda-legion ] && exit 0   # fix active
if compgen -G "/lib/modules/$K/updates/dkms/snd-hda-scodec-aw88399-legion.ko*" >/dev/null; then
	notify "Speaker bass driver installed but not active" \
		"Kernel $K has the AW88399 driver, but it did not bind. Run: sudo legion-aw88399-diagnostics"
fi
notify "Speaker bass driver missing for this kernel" \
	"Kernel $K is running without the AW88399 woofer driver (thin sound). Fix: sudo legion-aw88399-rebuild"
