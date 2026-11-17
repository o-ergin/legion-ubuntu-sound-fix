#!/bin/bash
# legion-aw88399 login check, installed as /usr/lib/legion-aw88399/login-check.
# Runs as the logged-in user from /etc/xdg/autostart. Read-only. It shows a desktop notification
# only when the woofer driver should be active on the running kernel but isn't.
set -u
K=$(uname -r)
DEV=/sys/bus/i2c/devices/i2c-AWDZ8399:00

[ -e "$DEV" ] || exit 0                                       # not this hardware
[ "$(basename "$(readlink -f "$DEV/driver" 2>/dev/null)")" = aw88399-hda-legion ] && exit 0  # fix active
modinfo -k "$K" snd-hda-scodec-aw88399-i2c >/dev/null 2>&1 && exit 0  # mainline (7.3+) driver available
[[ "$K" =~ ^7\.0\.0-[0-9]+-generic$ ]] || exit 0              # kernel this package does not target

if compgen -G "/lib/modules/$K/updates/dkms/snd-hda-scodec-aw88399-legion.ko*" >/dev/null; then
	title="Speaker bass driver installed but not active"
	body="Kernel $K has the AW88399 driver, but it did not bind. Run: sudo legion-aw88399-diagnostics"
else
	title="Speaker bass driver missing for this kernel"
	body="Kernel $K is running without the AW88399 woofer driver (thin sound). Fix: sudo legion-aw88399-rebuild"
fi
command -v notify-send >/dev/null && notify-send -u normal -i audio-speakers -a "Legion speakers" "$title" "$body"
echo "$title: $body" >&2
exit 0
