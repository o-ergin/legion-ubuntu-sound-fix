#!/bin/bash
# legion-aw88399 apt hook, installed as /usr/lib/legion-aw88399/apt-hook.
# apt runs it after every dpkg run (DPkg::Post-Invoke). It also runs under unattended-upgrades.
#
# Why it exists: an apt upgrade installs the new kernel and the new linux-source-7.0.0, in no
# guaranteed order. If the kernel's postinst runs first, prepare.sh skips the build, because the
# matching source is not there yet. This hook runs after the whole transaction and builds the
# module then.
#
# It only acts on the kernel whose ABI matches the installed linux-source-7.0.0, since that is the
# only kernel buildable from it. It never fails apt: it always exits 0, and logs to
# /var/log/legion-aw88399.log.
set -u
PKG=legion-aw88399
LOG=/var/log/legion-aw88399.log
STATE=/var/lib/legion-aw88399

command -v dkms >/dev/null || exit 0
VER=$(find /usr/src -maxdepth 1 -name "$PKG-*" -printf '%f\n' 2>/dev/null | sed "s/^$PKG-//" | sort -V | tail -n1)
[ -n "$VER" ] || exit 0

SRC=$(dpkg-query -W -f='${db:Status-Abbrev} ${Version}' linux-source-7.0.0 2>/dev/null) || exit 0
[[ "$SRC" =~ ^ii\ +(7\.0\.0-([0-9]+)\..*)$ ]] || exit 0
SRCVER=${BASH_REMATCH[1]}
K=7.0.0-${BASH_REMATCH[2]}-generic

[ -d "/lib/modules/$K/build/include" ] || exit 0                        # headers not installed
compgen -G "/lib/modules/$K/updates/dkms/snd-hda-scodec-aw88399-legion.ko*" >/dev/null && exit 0
[ -e "$STATE/skipped-$K-$SRCVER" ] && exit 0                         # already tried with this source

mkdir -p "$STATE"
echo "legion-aw88399: building the speaker driver for kernel $K (log: $LOG)"
{
	echo "=== $(date -Is) apt-hook: dkms install $PKG/$VER for $K (source $SRCVER)"
	dkms install -m "$PKG" -v "$VER" -k "$K"
	rc=$?
	echo "=== exit $rc"
} >>"$LOG" 2>&1
if compgen -G "/lib/modules/$K/updates/dkms/snd-hda-scodec-aw88399-legion.ko*" >/dev/null; then
	echo "legion-aw88399: built for $K"
else
	# Skipped (exit 77) or failed. Don't retry on every apt run with the same source.
	touch "$STATE/skipped-$K-$SRCVER"
	echo "legion-aw88399: NOT built for $K, see $LOG"
fi
exit 0
