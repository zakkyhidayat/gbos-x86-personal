#!/bin/sh
# Boot Googlebook (gbOS86) in QEMU/KVM from Linux as a throwaway snapshot, for testing apps. What is booted is only ever
# READ: everything the VM writes (data, settings, logs) goes to temporary qcow2 overlays deleted when the VM exits, so the
# next real boot sees exactly what was there before.
#
#   sh tools/run_vm.sh                 the external gbOS86 drive if it is plugged in, else the internal install (below)
#   sh tools/run_vm.sh --internal      the internal install beside Linux (tools/install_internal.sh): only its three
#                                      partitions GBOSSYS, GBOS_META, GBOS_DATA are given to the VM, never Linux's own
#   sh tools/run_vm.sh --disk IMG      a whole-disk image file (for testing this script)
#   sh tools/run_vm.sh --parts SYS META DATA   three partition image files, like --internal (for testing)
#   adb connect 127.0.0.1:5556         adb into the VM (USB debugging must already be on in that Android)
# Mouse: a plain USB mouse (Android ignores QEMU's usb-tablet, an absolute pointer). Click into the window to capture it,
# Ctrl+Alt+G releases it. SDL locks the host pointer while captured; QEMU's GTK window does not on Wayland (the desktop's
# cursor kept moving): VM_DISPLAY=gtk for its menus anyway.
#   VM_DISPLAY=none VM_EXTRA="-qmp unix:/tmp/q.sock,server,nowait"   headless (for tests)
#
# Graphics: the VM has a virtio GPU; hook.sh loads gbos/kmod/virtio-gpu.ko for it (built by
# kernel/isa_emu_patch/build_extra_module.sh) and Android draws with SwiftShader on the CPU: works, not fast. No fingerprint,
# Wi-Fi (the VM's network shows as Ethernet), Bluetooth (its app may say it keeps stopping) or real sound.
# Needs: qemu-system-x86_64 with SDL (qemu-ui-sdl), OVMF (edk2-ovmf), /dev/kvm. sudo only to let this user READ the drive or
# partitions (setfacl), undone on exit. QEMU itself runs as this user.
set -e
MEM=${MEM:-6144} CPUS=${CPUS:-4}
OVMF_CODE=${OVMF_CODE:-/usr/share/edk2/ovmf/OVMF_CODE.fd} OVMF_VARS=${OVMF_VARS:-/usr/share/edk2/ovmf/OVMF_VARS.fd}
HERE=$(cd "$(dirname "$0")/.." && pwd)
KERNEL=$HERE/usb/out/BOOTX64.EFI
OPTS='quiet loglevel=1 printk.ignore_loglevel=0 vt.global_cursor_default=0 console=ttynull'
die() { echo "run_vm: $*" >&2; [ -t 2 ] || notify-send -i dialog-error "Googlebook VM" "$*" 2>/dev/null; exit 1; }
[ -w /dev/kvm ] || die "/dev/kvm is not usable by $(id -un)"
[ -f "$OVMF_CODE" ] || die "OVMF not found ($OVMF_CODE): install edk2-ovmf"

ROOTDISK=/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE / | sed 's/\[.*//')" 2>/dev/null)
label_on() { lsblk -rno PATH,LABEL "$2" 2>/dev/null | awk -v l="$1" '$2 == l { print $1 }'; }   # label_on LABEL disk
external() { lsblk -rno PATH,LABEL | awk '$2 == "GBOSSYS" { print $1 }' | while read p; do
  d=/dev/$(lsblk -no PKNAME "$p")
  case "$d" in /dev/loop*) continue;; esac   # an attached image file (e.g. the built looper image) is not a drive
  [ "$d" != "$ROOTDISK" ] && echo "$d"; done; }
unmount_all() { for p in "$@"; do
  if findmnt -rn -S "$p" >/dev/null; then udisksctl unmount -b "$p" >/dev/null 2>&1 || die "$p is mounted and could not be unmounted"; fi
done; }

MODE=$1
[ -z "$MODE" ] && { [ -n "$(external)" ] && MODE=--external || MODE=--internal; }
DRIVES=; ACL=
case "$MODE" in
  --disk) [ -f "$2" ] || die "no such image: $2"; DRIVES=$2;;
  --parts) for f in "$2" "$3" "$4"; do [ -f "$f" ] || die "no such image: $f"; done; DRIVES="$2 $3 $4";;
  --external)
    d=$(external); [ -n "$d" ] || die "no external gbOS86 drive plugged in"
    [ $(echo "$d" | wc -l) = 1 ] || die "more than one external gbOS86 drive: $(echo $d)"
    # The drive must be the gbOS86 one and nothing else: all four labels on it.
    for l in GBOS_DATA GBOS_EFI GBOS_META GBOSSYS; do [ -n "$(label_on $l "$d")" ] || die "$d has no $l partition"; done
    unmount_all $(lsblk -rno PATH "$d" | tail -n +2)
    echo "gbOS86 drive: $d ($(lsblk -dno MODEL,SIZE "$d" | tr -s ' '))"
    DRIVES=$d;;
  --internal)
    # Only the three gbOS86 partitions on this Linux's disk; the VM never sees Linux's own partitions.
    s=$(label_on GBOSSYS "$ROOTDISK") m=$(label_on GBOS_META "$ROOTDISK") a=$(label_on GBOS_DATA "$ROOTDISK")
    [ -n "$s" ] && [ -n "$m" ] && [ -n "$a" ] || die "no internal gbOS86 install on $ROOTDISK (tools/install_internal.sh)"
    [ -f "$KERNEL" ] || die "no $KERNEL"
    unmount_all "$s" "$m" "$a"
    echo "internal gbOS86: $s $m $a (kernel $KERNEL)"
    DRIVES="$s $m $a";;
  *) die "unknown option $MODE";;
esac
for d in $DRIVES; do [ -b "$d" ] && [ ! -r "$d" ] && ACL="$ACL $d"; done
T=$(mktemp -d /var/tmp/gbos-vm.XXXXXX)
HELPER=
if [ -n "$ACL" ] && [ -t 0 ]; then
  echo "sudo: giving $(id -un) read access to$ACL until the VM exits"
  for d in $ACL; do sudo setfacl -m "u:$(id -un):r" "$d"; done
elif [ -n "$ACL" ]; then
  # No terminal (started from the app launcher): one polkit prompt (GNOME's dialog, fingerprint or password). A root helper
  # grants read access, waits for QEMU to exit, then takes the access back, so there is no second prompt at the end.
  pkexec sh -c 'u=$1 t=$2; shift 2; for d; do setfacl -m "u:$u:r" "$d"; done; : > "$t/acl.ok"
    until [ -f "$t/qemu.pid" ] || [ ! -d "$t" ]; do sleep 1; done
    while kill -0 "$(cat "$t/qemu.pid" 2>/dev/null)" 2>/dev/null; do sleep 2; done
    for d; do setfacl -x "u:$u" "$d"; done' _ "$(id -un)" "$T" $ACL &
  HELPER=1; i=0
  until [ -f "$T/acl.ok" ]; do
    sleep 1; i=$((i + 1))
    { [ $i -lt 120 ] && kill -0 $! 2>/dev/null; } || { rm -rf "$T"; die "authorization refused or timed out"; }
  done
fi
cleanup() {
  rm -rf "$T"
  [ -n "$HELPER" ] && return 0   # the root helper removes the access itself once QEMU has exited
  for d in $ACL; do sudo setfacl -x "u:$(id -un)" "$d" 2>/dev/null; done
  [ -z "$ACL" ] || echo "read access to$ACL removed"
}
trap cleanup EXIT INT TERM
# Throwaway overlays: each drive is a read-only backing file, every write lands in $T and is deleted with it.
set --; i=0
for d in $DRIVES; do
  qemu-img create -q -f qcow2 -F raw -b "$(readlink -f "$d")" "$T/d$i.qcow2"
  set -- "$@" -drive file="$T/d$i.qcow2",if=none,id=d$i,format=qcow2 -device nvme,drive=d$i,serial=gbosvm$i
  i=$((i + 1))
done
# A whole disk boots through the firmware from its EFI partition; three bare partitions have none, so the kernel is given
# directly (the same file as the internal install's EFI/gbos/BOOTX64.EFI) with the same options as its boot entry.
[ $i = 3 ] && set -- "$@" -kernel "$KERNEL" -append "$OPTS"
cp "$OVMF_VARS" "$T/vars.fd"
echo "starting the VM (writes go to $T, deleted on exit); adb: adb connect 127.0.0.1:5556"
qemu-system-x86_64 -name gbOS86-snapshot -machine q35,accel=kvm -cpu host -m "$MEM" -smp "$CPUS" \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" -drive if=pflash,format=raw,file="$T/vars.fd" "$@" \
  -device e1000e,netdev=n0 -netdev user,id=n0,hostfwd=tcp:127.0.0.1:5556-:5555 \
  -device qemu-xhci -device usb-mouse -device usb-kbd -device virtio-vga -display "${VM_DISPLAY:-sdl}" $VM_EXTRA &
echo $! > "$T/qemu.pid"
wait $! || die "QEMU exited with an error"
