#!/bin/bash
# DKMS PRE_BUILD for legion-aw88399: assemble sources that match the TARGET kernel exactly.
# Refuses to build (so the stock drivers stay in use) when anything does not match.
set -euo pipefail
KVER="${1:?usage: prepare.sh <kernelver>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG=linux-source-7.0.0
TARBALL=/usr/src/$PKG/$PKG.tar.bz2
die() { echo "legion-aw88399: NOT BUILDING for $KVER: $*" >&2; exit 1; }

[[ "$KVER" =~ ^7\.0\.0-([0-9]+)-generic$ ]] || die "only 7.0.0-NN-generic kernels are supported"
ABI="${BASH_REMATCH[1]}"
SRCVER="$(dpkg-query -W -f='${Version}' $PKG 2>/dev/null)" || die "$PKG is not installed"
[[ "$SRCVER" == "7.0.0-${ABI}."* ]] || die "$PKG is $SRCVER but this kernel needs 7.0.0-${ABI}.x (sudo apt install $PKG; sudo dkms autoinstall)"
[ -r "$TARBALL" ] || die "missing $TARBALL"

T="$HERE/.ksrc"
[[ "$T" == */.ksrc ]] && rm -rf -- "$T"
mkdir -p "$T"
tar -xjf "$TARBALL" -C "$T" --strip-components=1 \
	$PKG/sound/hda/common $PKG/sound/hda/codecs/generic.h $PKG/sound/hda/codecs/helpers \
	$PKG/sound/hda/codecs/side-codecs/hda_component.h \
	$PKG/sound/hda/codecs/realtek/alc269.c $PKG/sound/hda/codecs/realtek/realtek.h \
	$PKG/sound/soc/codecs/aw88395

if grep -q "AWDZ8399" "$T/sound/hda/codecs/realtek/alc269.c"; then
	die "this kernel already has AW88399 HDA support; use the stock driver"
fi
(cd "$T" && patch -p1 --fuzz=0 --no-backup-if-mismatch --quiet < "$HERE/patches/alc269-legion-aw88399.patch") ||
	die "patches/alc269-legion-aw88399.patch does not apply cleanly to this kernel's alc269.c"

mkdir -p "$HERE/common" "$HERE/codecs/realtek" "$HERE/codecs/side-codecs" "$HERE/codecs/helpers" "$HERE/lib/aw88395"
cp "$T"/sound/hda/common/*.h "$HERE/common/"
cp "$T"/sound/hda/codecs/generic.h "$HERE/codecs/"
cp "$T"/sound/hda/codecs/helpers/*.c "$HERE/codecs/helpers/"
cp "$T"/sound/hda/codecs/side-codecs/hda_component.h "$HERE/codecs/side-codecs/"
cp "$T"/sound/hda/codecs/realtek/alc269.c "$T"/sound/hda/codecs/realtek/realtek.h "$HERE/codecs/realtek/"
cp "$T"/sound/soc/codecs/aw88395/*.h "$HERE/lib/aw88395/"
rm -rf -- "$T"
echo "legion-aw88399: sources prepared for $KVER from $PKG $SRCVER"
