#!/bin/bash
# legion-aw88399-rebuild [KERNEL]: build and install the woofer driver for KERNEL (default: the
# running kernel). Installs the exact matching linux-source-7.0.0 and headers when needed. apt
# shows its usual confirmation prompt before changing any package.
# Installed as /usr/local/sbin/legion-aw88399-rebuild.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo legion-aw88399-rebuild ${1:-}"; exit 1; }
PKG=legion-aw88399
K="${1:-$(uname -r)}"
[[ "$K" =~ ^7\.0\.0-([0-9]+)-generic$ ]] || { echo "Only 7.0.0-NN-generic kernels are supported (got $K)."; exit 1; }
if modinfo -k "$K" snd-hda-scodec-aw88399-i2c >/dev/null 2>&1; then
	echo "Kernel $K already ships the mainline AW88399 driver. Nothing to build."; exit 0
fi

KV=$(dpkg-query -W -f='${Version}' "linux-modules-$K" 2>/dev/null) || { echo "Kernel $K is not installed."; exit 1; }
VER=$(find /usr/src -maxdepth 1 -name "$PKG-*" -printf '%f\n' | sed "s/^$PKG-//" | sort -V | tail -n1)
[ -n "$VER" ] || { echo "$PKG is not installed. Run scripts/install.sh from the repository."; exit 1; }

want=()
[ "$(dpkg-query -W -f='${Version}' linux-source-7.0.0 2>/dev/null || true)" = "$KV" ] || want+=("linux-source-7.0.0=$KV")
[ -d "/lib/modules/$K/build/include" ] || want+=("linux-headers-$K")
if [ ${#want[@]} -gt 0 ]; then
	echo "Installing: ${want[*]}"
	apt-get update -qq
	apt-get install --allow-downgrades "${want[@]}"
	apt-mark manual linux-source-7.0.0 >/dev/null
fi

rm -f /var/lib/legion-aw88399/skipped-"$K"-*
if dkms status -m "$PKG" -v "$VER" -k "$K" | grep -q installed; then
	echo "$PKG/$VER is already installed for $K. Nothing to do."
	exit 0
else
	dkms install -m "$PKG" -v "$VER" -k "$K"
fi
if [ "$K" = "$(uname -r)" ]; then
	echo "Done. Reboot to load it, then check: sudo legion-aw88399-diagnostics"
else
	echo "Done. It loads the next time you boot $K."
fi
