#!/bin/sh
# One round of the GPU VM test: builds a throwaway test disk from the INTERNAL install's files (read-only mount; GNOME may ask
# once), adds vm-gpu/out/libvulkan_virtio.so as gbos/patched/vulkan.venus.so and this repo's hook.sh, boots it in QEMU with
# Venus (host GPU, headless), waits, then prints a short summary of the guest's and the host renderer's graphics errors.
#   sh vm-gpu/test_boot.sh [WAIT_SECONDS=150]      KEEP=1 keeps /var/tmp/gbos-gputest (logs in lg/, screenshot s.png)
#   GPU=cpu sh vm-gpu/test_boot.sh                 plain virtio-vga and SwiftShader, as tools/run_vm.sh runs it
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd); WAIT=${1:-150}; W=/var/tmp/gbos-gputest
[ -f "$HERE/vm-gpu/out/libvulkan_virtio.so" ] || { echo "build first: sh vm-gpu/build_venus.sh"; exit 1; }
dev=$(lsblk -rno PATH,LABEL | awk '$2=="GBOSSYS" && $1 ~ /nvme/ {print $1}'); [ -n "$dev" ] || { echo "no internal GBOSSYS"; exit 1; }
findmnt -rn -S "$dev" >/dev/null || udisksctl mount -b "$dev" -o ro >/dev/null
R=$(findmnt -no TARGET "$dev")
rm -rf $W; mkdir -p $W; cd $W
truncate -s 6144M sys.img; mkfs.fat -F32 -n GBOSSYS sys.img >/dev/null
truncate -s 64M meta.img; mkfs.ext4 -q -L GBOS_META meta.img
truncate -s 4096M data.img; mkfs.ext4 -q -L GBOS_DATA -m 0 -O verity data.img
mcopy -i sys.img $R/busybox ::/; mmd -i sys.img ::gbos ::gbos/logs ::gbos/patched
for f in $R/gbos/*; do n=${f##*/}; case $n in logs|backup-*|gbos.cfg|hook.sh|patched) ;; *) mcopy -s -i sys.img "$f" ::gbos/;; esac; done
for f in $R/gbos/patched/*; do mcopy -i sys.img "$f" ::gbos/patched/; done
mcopy -i sys.img "$HERE/vm-gpu/out/libvulkan_virtio.so" ::gbos/patched/vulkan.venus.so
mcopy -i sys.img "$HERE/usb/hook.sh" ::gbos/hook.sh
sed 's/^#DEBUG_LOGS=1$/DEBUG_LOGS=1/' $R/gbos/gbos.cfg > gbos.cfg; mcopy -i sys.img gbos.cfg ::gbos/
udisksctl unmount -b "$dev" >/dev/null
cp /usr/share/edk2/ovmf/OVMF_VARS.fd vars.fd
if [ "${GPU:-venus}" = cpu ]; then MACH=q35,accel=kvm MEMOBJ= GPUDEV="-device virtio-vga -display none"
else MACH=q35,accel=kvm,memory-backend=mem MEMOBJ="-object memory-backend-memfd,id=mem,size=6144M,share=on"
  GPUDEV="-device virtio-vga-gl,blob=on,venus=on,hostmem=2G -display egl-headless"; fi
qemu-system-x86_64 -name gputest -machine $MACH -cpu host -m 6144 -smp 4 $MEMOBJ \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd -drive if=pflash,format=raw,file=vars.fd \
  -drive file=sys.img,if=none,id=d0,format=raw -device nvme,drive=d0,serial=t0 -drive file=meta.img,if=none,id=d1,format=raw -device nvme,drive=d1,serial=t1 \
  -drive file=data.img,if=none,id=d2,format=raw -device nvme,drive=d2,serial=t2 \
  -kernel "$HERE/usb/out/BOOTX64.EFI" -append "quiet loglevel=1 printk.ignore_loglevel=0 vt.global_cursor_default=0 console=ttynull" \
  -device e1000e,netdev=n0 -netdev user,id=n0 -device qemu-xhci -device usb-mouse -device usb-kbd \
  $GPUDEV -qmp unix:$W/q.sock,server,nowait > q.log 2>&1 &
QP=$!
sleep "$WAIT"
python3 -I - <<PY || true
import socket,json
s=socket.socket(socket.AF_UNIX); s.connect("$W/q.sock"); f=s.makefile('rw'); f.readline()
def cmd(c,**a):
    f.write(json.dumps({"execute":c,"arguments":a} if a else {"execute":c})+"\n"); f.flush()
    while True:
        r=json.loads(f.readline())
        if 'return' in r or 'error' in r: return r
cmd("qmp_capabilities"); print("screendump:", cmd("screendump",filename="$W/s.png",format="png"))
cmd("quit")
PY
sleep 3; kill $QP 2>/dev/null || true
mkdir lg; mcopy -s -i sys.img ::gbos/logs/boot-1 lg/ 2>/dev/null || true
echo "== hook"; grep -a -E "software rendering: Vulkan|VM: " lg/boot-1/kmsg.log | awk -F'[,;]' '{print substr($6,1,120)}' | head -3
echo "== guest (top errors)"; cat lg/boot-1/logcat.txt* 2>/dev/null | grep -aE " [EF] " | grep -aiE "vulkan|venus|gralloc|SurfaceFlinger|minigbm|VN_|virtio" | sed 's/^[0-9-]* [0-9:.]* *[0-9]* *[0-9]* //' | cut -c1-150 | sort | uniq -c | sort -rn | head -8
echo "== host renderer"; grep -a "vkr:" q.log | sed 's/\[[0-9]*\]//' | sort | uniq -c | sort -rn | head -4
echo "== vmawake: $(grep -a -E "gbos_vmawake.*(started|exited)" lg/boot-1/kmsg.log | awk -F"[,;]" "{print substr(\$6,1,90)}" | tr "\n" " ")"
echo "== boot_completed: $(grep -a -c 'sys.boot_completed=1' lg/boot-1/kmsg.log) lines; screenshot: $([ -f s.png ] && echo $W/s.png || echo none)"
[ -n "$KEEP" ] || { cd /; rm -rf $W; }
