#!/bin/bash
# legion-aw88399 diagnostics. READ-ONLY: it changes nothing and writes no amplifier registers.
# Paste the output into a bug report. It leaves out serial numbers, UUIDs and the hostname.
# Run with sudo to include the amplifier registers. Without sudo, it skips those.
# Installed as /usr/local/sbin/legion-aw88399-diagnostics.
set -u
K=$(uname -r)
sec() { printf '\n## %s\n' "$1"; }
have_root=no; [ "$(id -u)" = 0 ] && have_root=yes

echo "# legion-aw88399 diagnostics ($(date -I))"
sec "System"
echo "dmi: $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/class/dmi/id/product_name 2>/dev/null) / $(cat /sys/class/dmi/id/product_version 2>/dev/null)"
echo "bios: $(cat /sys/class/dmi/id/bios_version 2>/dev/null)"
echo "kernel: $K"
. /etc/os-release 2>/dev/null && echo "os: ${PRETTY_NAME:-?}"
echo "secure boot: $(mokutil --sb-state 2>/dev/null | head -n1 || echo unknown)"
echo "cmdline (audio-related): $(tr ' ' '\n' </proc/cmdline | grep -iE 'snd|dsp|sof|aw88399' | tr '\n' ' ')"

sec "Packages"
dpkg-query -W -f='${Package} ${Version}\n' dkms linux-source-7.0.0 "linux-modules-$K" "linux-headers-$K" pipewire wireplumber 2>&1
dkms status legion-aw88399 2>&1
ls /usr/src | grep legion-aw88399 || echo "no /usr/src/legion-aw88399-*"

sec "Install footprint"
for f in /lib/firmware/updates/awinic/aw88399_acf_17aa3906.bin /lib/firmware/updates/awinic/aw88399_acf_17aa3907.bin \
	/lib/firmware/awinic/aw88399_acf_17aa3906.bin* /lib/firmware/awinic/aw88399_acf_17aa3907.bin*; do
	[ -e "$f" ] && echo "$(sha256sum "$f" | cut -c1-16)…  $f"
done
cat /etc/modprobe.d/legion-aw88399.conf 2>/dev/null | grep -v '^#' || echo "no /etc/modprobe.d/legion-aw88399.conf"
for f in /etc/apt/apt.conf.d/99legion-aw88399 /usr/lib/legion-aw88399/apt-hook /usr/lib/legion-aw88399/login-check \
	/usr/local/sbin/legion-aw88399-rebuild /etc/xdg/autostart/legion-aw88399-check.desktop; do
	[ -e "$f" ] && echo "present: $f" || echo "MISSING: $f"
done
ls /var/lib/legion-aw88399/ 2>/dev/null | sed 's/^/state: /'

sec "Modules"
for m in snd-hda-codec-alc269 snd-soc-aw88399-lib snd-hda-scodec-aw88399-legion snd-hda-scodec-aw88399-i2c snd-soc-aw88399; do
	printf '%-32s %s\n' "$m" "$(modinfo -k "$K" -F filename "$m" 2>/dev/null || echo '(not available)')"
done
lsmod | grep -E '^(snd_hda_codec_alc269|snd_soc_aw88399|snd_hda_scodec_aw88399|snd_hda_intel|snd_sof)' || true

sec "ACPI / I2C"
for d in /sys/bus/i2c/devices/i2c-AWDZ8399*; do
	[ -e "$d" ] || { echo "no i2c-AWDZ8399 device"; break; }
	echo "$(basename "$d"): name $(cat "$d/name" 2>/dev/null) driver=$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)"
done
for d in /sys/bus/acpi/devices/AWDZ8399*; do [ -e "$d" ] && echo "acpi $(basename "$d"): status=$(cat "$d/status" 2>/dev/null)"; done

sec "HDA codec"
for c in /proc/asound/card*/codec#*; do
	grep -q "^Codec: Realtek" "$c" 2>/dev/null || continue
	echo "$c"; grep -E "^(Codec|Vendor Id|Subsystem Id|Revision Id):" "$c"
	for n in 0x14 0x17 0x21; do
		echo "  Node $n:"; awk -v n="Node $n" '$0 ~ "^"n" " {p=1; next} /^Node / {p=0} p' "$c" |
			grep -E "Pin Default|Pin-ctls|Amp-Out vals|Connection|^\s+0x" | sed 's/^/    /'
	done
done

sec "Amplifier registers"
if [ $have_root = yes ]; then
	modprobe i2c-dev
	BUS=$(basename "$(readlink -f /sys/bus/i2c/devices/i2c-AWDZ8399:00/.. 2>/dev/null)" 2>/dev/null); BUS=${BUS#i2c-}
	if [ -n "$BUS" ] && command -v i2cget >/dev/null; then
		rd() { local w; w=$(i2cget -f -y "$BUS" "$1" "$2" w 2>/dev/null) || { echo "ERR"; return; }; printf '0x%04x' $(( ((w & 0xff) << 8) | (w >> 8) )); }
		for a in 0x35 0x34; do echo "$a id=$(rd $a 0x00) SYSST=$(rd $a 0x01) SYSCTRL=$(rd $a 0x04)"; done
		echo "(SYSCTRL bit0=1 means powered down. Amps run only while a stream is open.)"
	else echo "i2c bus or i2cget (i2c-tools) not available"; fi
else echo "skipped (run with sudo to include)"; fi

sec "Kernel log"
journalctl -k -b -o cat --no-pager 2>/dev/null | grep -iE "aw88399|AWDZ8399|picked fixup|alc287|snd_hda_intel.*(error|fail)|legion-aw88399" |
	grep -v "Modules linked in" | tail -n 40 || dmesg 2>/dev/null | grep -iE "aw88399|AWDZ8399|picked fixup" | tail -n 40
[ -r /var/log/legion-aw88399.log ] && { sec "Rebuild log (last 15 lines)"; tail -n 15 /var/log/legion-aw88399.log; }
exit 0
