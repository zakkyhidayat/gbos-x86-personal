#!/bin/sh
# Put gbOS86 on the internal disk BESIDE the running Fedora (dual boot), from Fedora itself:
#   1. shrink Fedora's btrfs (online) and then its partition, freeing SIZE_GIB at the end of the disk
#   2. add GBOSSYS (FAT32, 8 GiB), GBOS_META (ext4, 64 MiB), GBOS_DATA (ext4, the rest) there, found by label as on the SSD
#   3. copy gbos/ (system image, scripts, modules, firmware) from the external gbOS86 drive; /data starts empty (fresh setup)
#   4. the kernel goes to Fedora's EFI partition as EFI/gbos/BOOTX64.EFI (Fedora's updates never touch that folder)
#   5. a firmware boot entry "Googlebook (internal)" with the quiet options, after Fedora in the boot order
#
#   sh tools/install_internal.sh            dry run: shows the computed layout and every command, changes nothing
#   sh tools/install_internal.sh --run      does it, asking before each step (sudo for the disk steps)
#
# Afterwards: boot Googlebook with the external drive UNPLUGGED (both disks carry the same labels).
set -e
SIZE_GIB=${SIZE_GIB:-72} SYS_GIB=8 META_MIB=64
OPTS='quiet loglevel=1 printk.ignore_loglevel=0 vt.global_cursor_default=0 console=ttynull'
HERE=$(cd "$(dirname "$0")/.." && pwd)
RUN=; [ "$1" = --run ] && RUN=1
die() { echo "install_internal: $*" >&2; exit 1; }
step() {  # step "what" command...   dry run: print; --run: ask, then run
  echo; echo "== $1"; shift; echo "   \$ $*"
  [ -n "$RUN" ] || return 0
  printf '   run this step? [y/n] '; read a; case "$a" in y|Y|yes) ;; *) false;; esac || die "stopped before: $*"
  "$@"
}

# --- the internal disk: the one holding Fedora's /, root on its LAST partition, btrfs, nothing of gbOS86 on it yet
ROOT=$(findmnt -no SOURCE / | sed 's/\[.*//')
[ "$(findmnt -no FSTYPE /)" = btrfs ] || die "/ is not btrfs"
PN=$(basename "$ROOT"); DN=$(lsblk -no PKNAME "$ROOT"); DISK=/dev/$DN
PNUM=$(cat /sys/class/block/$PN/partition)
case $DN in nvme*|mmcblk*) PP=${DISK}p;; *) PP=$DISK;; esac
N1=$((PNUM + 1)) N2=$((PNUM + 2)) N3=$((PNUM + 3))
SYS_SECT=$((SYS_GIB * 2097152)) META_SECT=$((META_MIB * 2048))
# Resume: steps 1-3 done (by an earlier --run) when the three partitions follow Fedora's, in this layout, still unformatted.
RESUME=
if [ "$(lsblk -no PARTLABEL ${PP}$N1 2>/dev/null)/$(lsblk -no PARTLABEL ${PP}$N2 2>/dev/null)/$(lsblk -no PARTLABEL ${PP}$N3 2>/dev/null)" = GBOSSYS/GBOS_META/GBOS_DATA ]; then
  s() { cat /sys/class/block/$(basename $1)/$2; }
  [ "$(s ${PP}$N1 start)" = $(( $(s $ROOT start) + $(s $ROOT size) )) ] && [ "$(s ${PP}$N1 size)" = $SYS_SECT ] \
    && [ "$(s ${PP}$N2 start)" = $(( $(s ${PP}$N1 start) + SYS_SECT )) ] && [ "$(s ${PP}$N2 size)" = $META_SECT ] \
    && [ "$(s ${PP}$N3 start)" = $(( $(s ${PP}$N2 start) + META_SECT )) ] || die "GBOS partitions exist but not in the expected layout"
  [ -z "$(lsblk -no FSTYPE ${PP}$N1 ${PP}$N2 ${PP}$N3 | tr -d ' \n')" ] || die "the GBOS partitions already have filesystems: steps 1-4 are done"
  RESUME=1
else
  [ "$(lsblk -rno TYPE "$DISK" | grep -c part)" = "$PNUM" ] || die "$ROOT is not the last partition of $DISK"
  lsblk -rno PARTLABEL,LABEL "$DISK" | grep -q 'GBOS' && die "$DISK already has GBOS partitions"
fi
SS=$(cat /sys/block/$DN/queue/logical_block_size); [ "$SS" = 512 ] || die "sector size $SS, expected 512"
TOTAL=$(cat /sys/block/$DN/size)
P3START=$(cat /sys/class/block/$PN/start) P3SIZE=$(cat /sys/class/block/$PN/size)

# --- the layout (512-byte sectors), 1 MiB aligned. GPT keeps its backup copy in the last 33 sectors.
LAST=$((TOTAL - 34))
NEED=$((SIZE_GIB * 2097152))
GSTART=$(( (LAST + 1 - NEED) / 2048 * 2048 ))
NEWP3=$((GSTART - P3START))
[ -n "$RESUME" ] && GSTART=$(cat /sys/class/block/$(basename ${PP}$N1)/start) NEWP3=$P3SIZE
[ $NEWP3 -gt 0 ] && { [ $NEWP3 -lt $P3SIZE ] || [ -n "$RESUME" ]; } || die "nothing to shrink"
FS_BYTES=$(( (NEWP3 - 2097152) * 512 ))   # btrfs 1 GiB smaller than its new partition: never past the end
USED=$(df -B1 --output=used / | tail -1)
[ $FS_BYTES -gt $((USED + 20 * 1073741824)) ] || die "Fedora would have under 20 GiB free after the shrink"

ESP=$(findmnt -no TARGET /boot/efi); [ -n "$ESP" ] || die "Fedora's EFI partition is not mounted at /boot/efi"
ESPDEV=$(findmnt -no SOURCE /boot/efi); ESPNUM=$(cat /sys/class/block/$(basename $ESPDEV)/partition)
[ "/dev/$(lsblk -no PKNAME $ESPDEV)" = "$DISK" ] || die "EFI partition is not on $DISK"
KERNEL=$HERE/usb/out/BOOTX64.EFI; [ -f "$KERNEL" ] || die "no $KERNEL"

# --- the source: the external gbOS86 drive's GBOSSYS (only read)
SRC=$(lsblk -rno PATH,LABEL | awk -v d="$DISK" '$2 == "GBOSSYS" && index($1, d) != 1 { print $1 }')
[ -n "$SRC" ] || die "plug in the external gbOS86 drive (its GBOSSYS partition is the source)"
SRCMNT=$(findmnt -no TARGET "$SRC" || true)
[ -n "$SRCMNT" ] || { udisksctl mount -b "$SRC" -o ro >/dev/null; SRCMNT=$(findmnt -no TARGET "$SRC"); }
[ -f "$SRCMNT/gbos/super.img" ] || die "$SRC has no gbos/super.img"

gib() { echo "$(( $1 * 512 / 1073741824 )) GiB"; }
cat <<EOF
Internal disk $DISK ($(lsblk -dno MODEL "$DISK" | tr -s ' ')), $(gib $TOTAL)
  Fedora $ROOT (btrfs, $((USED / 1073741824)) GiB used): $(gib $P3SIZE) -> $(gib $NEWP3), filesystem -> $((FS_BYTES / 1073741824)) GiB
  new ${PP}$N1 GBOSSYS   FAT32 $SYS_GIB GiB      (copy of $SRC's gbos/, without logs and backups)
  new ${PP}$N2 GBOS_META ext4  $META_MIB MiB
  new ${PP}$N3 GBOS_DATA ext4  $(gib $((LAST + 1 - GSTART - SYS_SECT - META_SECT)))  (empty: Googlebook's setup runs on first boot)
  kernel   $ESP/EFI/gbos/BOOTX64.EFI
  boot entry "Googlebook (internal)": $OPTS
EOF
[ -n "$RUN" ] || echo "(dry run: nothing is changed; --run to do it)"
if [ -n "$RUN" ]; then
  echo; echo "Shrinking a filesystem that is in use is normally safe on btrfs, but an interruption (power loss) could lose data."
  printf 'Is your Fedora data backed up elsewhere? [y/n] '; read a; case "$a" in y|Y|yes) ;; *) false;; esac || die "back up first"
fi

if [ -n "$RESUME" ]; then echo; echo "== 1-3/7 already done (Fedora shrunk, partitions ${PP}$N1-$N3 in place): continuing at 4/7"; else
step "1/7 shrink Fedora's btrfs (online, moves data off the end; may take minutes)" \
  sudo btrfs filesystem resize "1:$FS_BYTES" /
step "2/7 shrink Fedora's partition to $(gib $NEWP3) (stays bigger than its filesystem)" \
  sh -c "S=\$(sudo btrfs filesystem show --raw / | awk '\$1 == \"devid\" && \$2 == 1 { print \$4 }') && [ -n \"\$S\" ] && [ \$S -le $FS_BYTES ] \
    || { echo \"   btrfs is still \$S bytes, not <= $FS_BYTES: partition left as it is\"; exit 1; } \
    && echo '$P3START,$NEWP3' | sudo sfdisk -q --no-reread --no-tell-kernel -N $PNUM $DISK && sudo partx -u -n $PNUM $DISK"
step "3/7 add the three gbOS86 partitions" \
  sh -c "printf 'start=$GSTART, size=$SYS_SECT, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name=GBOSSYS\nsize=$META_SECT, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=GBOS_META\ntype=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=GBOS_DATA\n' | sudo sfdisk -q --append --no-reread --no-tell-kernel $DISK && { sudo partx -a -n $N1:$N3 $DISK 2>/dev/null || true; } && [ -b ${PP}$N1 ] && [ -b ${PP}$N3 ]"
fi
step "4/7 make the filesystems (as gbOS86's installer does)" \
  sh -c "sudo mkfs.fat -F 32 -n GBOSSYS ${PP}$N1 >/dev/null && sudo mke2fs -F -q -t ext4 -L GBOS_META ${PP}$N2 && sudo mke2fs -F -q -t ext4 -m 0 -O verity -L GBOS_DATA ${PP}$N3"
step "5/7 copy gbos/ from $SRC to the new GBOSSYS, then compare every file" \
  sh -c "D=\$(mktemp -d) && sudo mount -o uid=$(id -u),gid=$(id -g) ${PP}$N1 \"\$D\" && cp -r '$SRCMNT/busybox' \"\$D/\" && mkdir -p \"\$D/gbos/logs\" \
    && for f in '$SRCMNT'/gbos/*; do case \"\${f##*/}\" in logs|backup-*) ;; *) cp -r \"\$f\" \"\$D/gbos/\";; esac; done && sync \
    && (cd '$SRCMNT' && find busybox gbos -path gbos/logs -prune -o -path 'gbos/backup-*' -prune -o -type f -print) | while read f; do cmp -s '$SRCMNT'/\"\$f\" \"\$D/\$f\" || { echo \"DIFFERS: \$f\"; exit 1; }; done \
    && echo \"   copied and verified: \$(du -sh \"\$D\" | cut -f1)\" && sudo umount \"\$D\" && rmdir \"\$D\""
step "6/7 put the kernel on Fedora's EFI partition" \
  sh -c "sudo mkdir -p '$ESP/EFI/gbos' && sudo cp '$KERNEL' '$ESP/EFI/gbos/BOOTX64.EFI' && sudo cmp '$KERNEL' '$ESP/EFI/gbos/BOOTX64.EFI' && echo '   verified'"
step "7/7 boot entry \"Googlebook (internal)\", after Fedora in the boot order" \
  sh -c "N=\$(sudo efibootmgr -C -d $DISK -p $ESPNUM -L 'Googlebook (internal)' -l '\\EFI\\gbos\\BOOTX64.EFI' -u '$OPTS' | sed -n 's/^Boot\\([0-9A-F]\\{4\\}\\)\\* Googlebook (internal).*/\\1/p') \
    && O=\$(efibootmgr | sed -n 's/^BootOrder: //p') && F=\${O%%,*} && sudo efibootmgr -q -o \"\$F,\$N,\${O#*,}\" && efibootmgr | grep -E '^BootOrder|Googlebook'"
[ -n "$RUN" ] && echo && echo "Done. Unplug the external drive, restart, F12 -> \"Googlebook (internal)\"."
:
