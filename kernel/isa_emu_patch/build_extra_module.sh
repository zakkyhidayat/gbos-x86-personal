#!/bin/sh
# Build one more module for the SHIPPED kernel without rebuilding it. Runs in gbos-kbuild:
#   docker run --rm -v gbos-ksrc:/build -v <repo>:/repo gbos-kbuild sh /repo/kernel/isa_emu_patch/build_extra_module.sh \
#     USB4_NET drivers/net/thunderbolt thunderbolt_net
# The module must match the running kernel exactly, so nothing is guessed:
#   - config: the shipped kernel's own, read from the IKCONFIG embedded in usb/out/BOOTX64.EFI, plus CONFIG_<SYM>=m
#   - symbol CRCs (CONFIG_MODVERSIONS): kernel/symvers_from_modules.py recovers them from the shipped usb/modules tree
#   - compiler: the same AOSP clang (r584948b), so kCFI type hashes and the mitigation thunks agree
#   - vermagic: the shipped tree's kernel release (6.18.21-gbos-whl since kernel #38), checked against the result
# The module is built out of tree from a copy of the kernel's own directory and lands in usb/kmod/ (tracked, loaded
# with insmod by usb/hook.sh, like btusb), so the downloaded usb/modules tree stays as released. It is not signed:
# CONFIG_MODULE_SIG_FORCE is off, so it loads (tainting the kernel, like any out-of-tree module).
set -e
SYM=$1 DIR=$2 MOD=$3
[ -n "$MOD" ] || { echo "usage: $0 CONFIG_SYMBOL kernel/dir module_name"; exit 1; }
C=/build/inputs/clang-r584948b
[ -x $C/bin/clang ] || C=/build/inputs/clang-r584948c
export PATH=$C/bin:$PATH LD_LIBRARY_PATH=$C/lib:${LD_LIBRARY_PATH:-}
R=/repo
TREE=$(ls -d $R/usb/modules/lib/modules/*/ | head -1); TREE=${TREE%/}
REL=$(basename "$TREE")
# The release is CONFIG_LOCALVERSION plus whatever setlocalversion appends: "+" for kernels built from a modified checkout
# (#37, tree r4), nothing since #38 pins it (tree r5). LOCALVERSION set (even empty) stops setlocalversion guessing.
case "$REL" in *+) LV=+;; *) LV=;; esac
O=/build/out_extra
M="make -C /build/src O=$O ARCH=x86_64 LLVM=$C/bin/ CC=$C/bin/clang LOCALVERSION=$LV"
rm -rf $O && mkdir -p $O /build/extmod

# shipped config: BOOTX64.EFI carries an lz4 (legacy) kernel payload, inside it IKCFG_ST <gzip> IKCFG_ED
python3 - "$R/usb/out/BOOTX64.EFI" "$O/.config" <<'EOF'
import gzip, subprocess, sys
d = open(sys.argv[1], 'rb').read()
p = d.find(b'\x02\x21\x4c\x18')
k = subprocess.run(['lz4', '-dc'], input=d[p:], capture_output=True).stdout
i = k.find(b'IKCFG_ST'); j = k.find(b'IKCFG_ED', i)
open(sys.argv[2], 'wb').write(gzip.decompress(k[i + 8:j]))
EOF
grep -q '^CONFIG_MODVERSIONS=y' $O/.config || { echo "embedded config not found"; exit 1; }
/build/src/scripts/config --file $O/.config --module "$SYM"
$M olddefconfig >/dev/null
grep -q "^CONFIG_$SYM=m" $O/.config || { echo "CONFIG_$SYM=m did not survive olddefconfig (missing dependency?)"; exit 1; }
$M modules_prepare >/dev/null
got=$($M -s kernelrelease)
[ "$got" = "$REL" ] || { echo "kernel release $got differs from the shipped $REL"; exit 1; }

python3 $R/kernel/symvers_from_modules.py "$TREE" $O/Module.symvers
rm -rf /build/extmod/$MOD && cp -a /build/src/$DIR /build/extmod/$MOD
$M M=/build/extmod/$MOD modules 2>&1 | tee /build/extmod/$MOD.log | tail -n 20
if grep -q 'WARNING: modpost:.*undefined\|has no CRC' /build/extmod/$MOD.log; then
  echo "modpost could not resolve every imported symbol's CRC: refusing to ship"; exit 1
fi
KO=/build/extmod/$MOD/$MOD.ko
$C/bin/llvm-strip --strip-debug $KO
VM=$(modinfo -F vermagic $KO)
case "$VM" in "$REL "*) ;; *) echo "vermagic '$VM' does not start with $REL"; exit 1;; esac
cp $KO $R/usb/kmod/$MOD.ko
modinfo $R/usb/kmod/$MOD.ko | grep -E '^(filename|alias|depends|vermagic)'
echo EXTRA_MODULE_DONE
