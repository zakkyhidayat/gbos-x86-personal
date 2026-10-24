#!/bin/sh
# Test of Thunderbolt networking: usb/kmod/thunderbolt_net.ko must fit the shipped kernel exactly (vermagic, every imported
# symbol's CRC, kCFI type hashes), and usb/hook.sh's block (cut out and run with a fake /proc/modules and insmod) must add
# the gbos_tbnet service only when the module loads. Needs the downloaded usb/modules tree.
# Run: sh tools/test_tbnet.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/tbnet.XXXXXX"); trap 'rm -rf "$W"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok   $*"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "FAIL $*"; }
H=$ROOT/usb/hook.sh
KO=$ROOT/usb/kmod/thunderbolt_net.ko
TREE=$(ls -d "$ROOT"/usb/modules/lib/modules/*/ 2>/dev/null | head -1); TREE=${TREE%/}
[ -f "$KO" ] && [ -d "$TREE" ] || { bad "need usb/kmod/thunderbolt_net.ko and the usb/modules tree"; exit 1; }

# the module against the shipped kernel
REL=$(basename "$TREE")
vm=$(modinfo -F vermagic "$KO")
[ "$vm" = "$(modinfo -F vermagic "$TREE/kernel/drivers/thunderbolt/thunderbolt.ko")" ] && ok "vermagic identical to the tree's ($REL)" || bad "vermagic '$vm'"
[ "$(modinfo -F depends "$KO")" = thunderbolt ] && ok "depends only on thunderbolt" || bad "depends: $(modinfo -F depends "$KO")"
modinfo -F alias "$KO" | grep -q '^tbsvc:knetwork' && ok "binds the Thunderbolt network service" || bad "no tbsvc alias"
python3 -I "$ROOT/kernel/symvers_from_modules.py" "$TREE" "$W/symvers" >/dev/null
python3 -I - "$KO" "$W/symvers" > "$W/crc.txt" <<'EOF'
import struct, sys
d = open(sys.argv[1], 'rb').read()
shoff, = struct.unpack_from('<Q', d, 0x28); shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x3a)
h = [struct.unpack_from('<IIQQQQIIQQ', d, shoff + i * shentsize) for i in range(shnum)]
nm = lambda o: d[h[shstrndx][4] + o:d.index(b'\0', h[shstrndx][4] + o)].decode()
v = [x for x in h if nm(x[0]) == '__versions'][0]
want = {l.split('\t')[1]: int(l.split('\t')[0], 16) for l in open(sys.argv[2])}
bad = 0; total = 0
for off in range(v[4], v[4] + v[5], 64):
    crc, = struct.unpack_from('<Q', d, off); name = d[off + 8:d.index(b'\0', off + 8)].decode(); total += 1
    if want.get(name) != crc & 0xffffffff:
        bad += 1; print('MISMATCH', name)
print(f'{total} {bad}')
EOF
read total mism < "$(tail -1 "$W/crc.txt" > "$W/t"; echo "$W/t")"
[ "$mism" = 0 ] && [ "$total" -gt 20 ] && ok "all $total imported symbol CRCs match the shipped kernel" || bad "CRC mismatches: $(cat "$W/crc.txt")"
cfi() { objdump -d --no-show-raw-insn "$1" | awk "/<__cfi_$2>:/{p=1} p&&/mov/{print \$NF; exit}"; }
a=$(cfi "$KO" tbnet_open); b=$(cfi "$TREE/kernel/drivers/net/usb/r8152.ko" rtl8152_open)
[ -n "$a" ] && [ "$a" = "$b" ] && ok "kCFI hash of ndo_open ($a) equals the shipped r8152's" || bad "kCFI hash differs: '$a' vs '$b'"

# hook.sh block
awk '/^TBRC=$/{p=1} p{print} p&&/^fi$/{exit}' "$H" > "$W/block.sh"
[ -s "$W/block.sh" ] && ok "TB block extracted from hook.sh" || { bad "TB block not found"; exit 1; }
mkdir -p "$W/g/kmod" && : > "$W/g/kmod/thunderbolt_net.ko"
run() {	# $1: /proc/modules content, $2: insmod result, $3: TB_NET
  printf '%s\n' "$1" > "$W/modules"
  sed "s#/proc/modules#$W/modules#" "$W/block.sh" > "$W/b.sh"
  ( G=$W/g; TB_NET=$3; TB_NET_IP=; rc=$2; log() { :; }; dmesg() { :; }; insmod() { return $rc; }
    . "$W/b.sh"; printf '%s' "$TBRC" )
}
out=$(run 'thunderbolt 491520 0 - Live 0x0' 0 1)
echo "$out" | grep -q '^service gbos_tbnet /system/bin/sh /postinstall/gbos/tbnet.sh 10.42.0.2$' && ok "Thunderbolt machine: gbos_tbnet service with the default address" || bad "no service: $out"
echo "$out" | grep -qx '    start gbos_tbnet' && ok "started at boot_completed" || bad "never started"
[ -z "$(run 'iwlwifi 1 0 - Live 0x0' 0 1)" ] && ok "no Thunderbolt driver: nothing added" || bad "added without Thunderbolt"
[ -z "$(run 'thunderbolt 1 0 - Live 0x0' 1 1)" ] && ok "insmod fails: no service" || bad "service despite a failed insmod"
[ -z "$(run 'thunderbolt 1 0 - Live 0x0' 0 0)" ] && ok "TB_NET=0: nothing added" || bad "TB_NET=0 ignored"
grep -q '^\$TBRC$' "$H" && ok "hook: \$TBRC written into gbos.rc" || bad "hook: \$TBRC never written"
grep -q 'gbos_fp tbnet.sh' "$ROOT/tools/make_gbos86_image.sh" && grep -q 'gbos_fp tbnet.sh' "$ROOT/tools/deploy_stick.sh" && ok "image and deploy scripts copy tbnet.sh" || bad "tbnet.sh not shipped"
sh -n "$H" && sh -n "$ROOT/usb/tbnet.sh" && ok "sh -n hook.sh tbnet.sh" || bad "syntax"

echo "$n checks, $fail failed"
[ $fail = 0 ] && echo TBNET_TEST_PASS
exit $fail
