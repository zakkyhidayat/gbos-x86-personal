#!/bin/sh
# Boot the gbOS86 drive (the external SSD, found by its GBOSSYS label) in QEMU/KVM from Linux, as a throwaway snapshot:
# for testing apps. The drive is only ever READ. Everything the VM writes (data, settings, logs) goes to a temporary qcow2
# overlay that is deleted when the VM exits, so the next boot on the laptop itself sees the drive exactly as before.
#
#   sh tools/run_vm.sh                 window (GTK), 6 GB RAM, 4 CPUs
#   sh tools/run_vm.sh --disk IMG      a disk image file instead of the SSD (for testing this script)
#   adb connect 127.0.0.1:5556         adb into the VM (USB debugging must already be on in the drive's Android)
#   VM_DISPLAY=none VM_EXTRA="-qmp unix:/tmp/q.sock,server,nowait"   headless (for tests)
#
# Graphics: the VM has a virtio GPU; hook.sh loads gbos/kmod/virtio-gpu.ko for it (built by
# kernel/isa_emu_patch/build_extra_module.sh) and Android draws with SwiftShader on the CPU: works, not fast. No fingerprint,
# Wi-Fi (the VM's network shows as Ethernet), Bluetooth (its app may say it keeps stopping) or real sound.
# Needs: qemu-system-x86_64 with GTK, OVMF (edk2-ovmf), /dev/kvm. sudo only to let this user READ the drive (setfacl), undone
# on exit. QEMU itself runs as this user.
set -e
MEM=${MEM:-6144} CPUS=${CPUS:-4}
OVMF_CODE=${OVMF_CODE:-/usr/share/edk2/ovmf/OVMF_CODE.fd} OVMF_VARS=${OVMF_VARS:-/usr/share/edk2/ovmf/OVMF_VARS.fd}
die() { echo "run_vm: $*" >&2; exit 1; }
[ -w /dev/kvm ] || die "/dev/kvm is not usable by $(id -un)"
[ -f "$OVMF_CODE" ] || die "OVMF not found ($OVMF_CODE): install edk2-ovmf"

DISK=; ACL=
if [ "$1" = --disk ]; then
  DISK=$2; [ -f "$DISK" ] || die "no such image: $DISK"
else
  sys=$(lsblk -rno PATH,LABEL | awk '$2 == "GBOSSYS" { print $1 }')
  [ -n "$sys" ] || die "no GBOSSYS partition found: plug in the gbOS86 drive"
  [ $(echo "$sys" | wc -l) = 1 ] || die "more than one GBOSSYS partition: $(echo $sys)"
  DISK=/dev/$(lsblk -no PKNAME "$sys")
  [ -b "$DISK" ] || die "cannot find the disk of $sys"
  # The drive must be the gbOS86 one and nothing else: all four labels on it, and not the disk this Linux runs from.
  labels=$(lsblk -rno LABEL "$DISK" | sort | tr '\n' ' ')
  for l in GBOS_DATA GBOS_EFI GBOS_META GBOSSYS; do case " $labels" in *" $l "*) ;; *) die "$DISK has no $l partition (labels: $labels)";; esac; done
  root=$(findmnt -no SOURCE / | sed 's/\[.*//'); [ "/dev/$(lsblk -no PKNAME "$root" 2>/dev/null)" != "$DISK" ] || die "$DISK holds this Linux's /"
  # Nothing on it may be mounted while the VM reads it (a mounted FAT changes under the VM). udisks mounts are this user's.
  for p in $(lsblk -rno PATH "$DISK" | tail -n +2); do
    if findmnt -rn -S "$p" >/dev/null; then udisksctl unmount -b "$p" >/dev/null || die "$p is mounted and could not be unmounted"; fi
  done
  echo "gbOS86 drive: $DISK ($(lsblk -dno MODEL,SIZE "$DISK" | tr -s ' '))"
  if [ ! -r "$DISK" ]; then
    echo "sudo: giving $(id -un) read access to $DISK until the VM exits"
    sudo setfacl -m "u:$(id -un):r" "$DISK"; ACL=1
  fi
fi

T=$(mktemp -d /var/tmp/gbos-vm.XXXXXX)
cleanup() {
  rm -rf "$T"
  [ -n "$ACL" ] && sudo setfacl -x "u:$(id -un)" "$DISK" 2>/dev/null && echo "read access to $DISK removed"
  :
}
trap cleanup EXIT INT TERM
# Throwaway overlay: the drive is its read-only backing file, every write lands in $T and is deleted with it.
qemu-img create -q -f qcow2 -F raw -b "$(readlink -f "$DISK")" "$T/overlay.qcow2"
cp "$OVMF_VARS" "$T/vars.fd"
echo "starting the VM (writes go to $T, deleted on exit); adb: adb connect 127.0.0.1:5556"
qemu-system-x86_64 -name gbOS86-snapshot -machine q35,accel=kvm -cpu host -m "$MEM" -smp "$CPUS" \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" -drive if=pflash,format=raw,file="$T/vars.fd" \
  -drive file="$T/overlay.qcow2",if=none,id=d0,format=qcow2 -device nvme,drive=d0,serial=gbosvm \
  -device e1000e,netdev=n0 -netdev user,id=n0,hostfwd=tcp:127.0.0.1:5556-:5555 \
  -device qemu-xhci -device usb-tablet -device usb-kbd -device virtio-vga -display "${VM_DISPLAY:-gtk}" $VM_EXTRA
