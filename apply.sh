#!/bin/sh
# Put this overlay onto a gbos-x86 checkout (github.com/linuxkid473/gbos-x86): copies the files of this repo into it and
# applies patches/gbos-x86-changes.patch to the upstream files it changes. Made against upstream 729b9c3 (kernel #42, modules r5); on a newer
# upstream the patch is applied with --3way, so conflicts show up as conflict markers instead of failing silently.
# Usage: ./apply.sh /path/to/gbos-x86
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
G=${1:?usage: $0 /path/to/gbos-x86}
[ -f "$G/usb/hook.sh" ] && git -C "$G" rev-parse --git-dir >/dev/null 2>&1 || { echo "$G is not a gbos-x86 checkout"; exit 1; }
cd "$HERE"
for f in fingerprint/build.sh fingerprint/gbos_fp.c fingerprint/syn.h fingerprint/syn_test.c \
	 kernel/isa_emu_patch/build_extra_module.sh kernel/symvers_from_modules.py \
	 tools/test_gbos_fp.sh tools/test_tbnet.sh usb/gbos_fp usb/kmod/thunderbolt_net.ko usb/tbnet.sh; do
  mkdir -p "$G/$(dirname "$f")"
  cp -p "$f" "$G/$f"
done
git -C "$G" apply --3way "$HERE/patches/gbos-x86-changes.patch"
echo "applied to $G (upstream $(git -C "$G" rev-parse --short HEAD)); run its tools/test_gbos_fp.sh, test_tbnet.sh and test_device_model.sh"
