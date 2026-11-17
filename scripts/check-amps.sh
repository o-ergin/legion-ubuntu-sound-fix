#!/bin/bash
# READ-ONLY status check of both AW88399 amplifiers (no register writes).
# Run once while idle and once while sound is playing.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
modprobe i2c-dev
BUS=$(basename "$(readlink -f /sys/bus/i2c/devices/i2c-AWDZ8399:00/..)"); BUS=${BUS#i2c-}
rd() { local w; w=$(i2cget -f -y "$BUS" "$1" "$2" w); printf '0x%04x' $(( ((w & 0xff) << 8) | (w >> 8) )); }
for a in 0x35 0x34; do
	id=$(rd $a 0x00); st=$(rd $a 0x01); ct=$(rd $a 0x04)
	printf '%s id=%s SYSST=%s SYSCTRL=%s  power=%s pll_locked=%s no_clock=%s\n' "$a" "$id" "$st" "$ct" \
		"$([ $((ct & 1)) = 0 ] && echo ON || echo off)" "$([ $((st & 1)) = 1 ] && echo yes || echo no)" \
		"$([ $((st >> 5 & 1)) = 1 ] && echo yes || echo no)"
done
journalctl -k -b --no-pager | grep -iE "aw88399|AWDZ8399|picked fixup" | grep -v "Modules linked in" | tail -n 12
