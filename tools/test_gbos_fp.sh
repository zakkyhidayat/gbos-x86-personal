#!/bin/sh
# Test of the gbos_fp fingerprint HAL wiring: the keys and id lists that must agree across files, and usb/hook.sh's sensor
# detection and gbos.rc service block (cut out of hook.sh and run on a fake /sys/bus/usb/devices, so the shipped code is tested).
# With SENSOR=1 it also runs fingerprint/syn_test probe in docker against the real sensor (read-only: version, init, power down).
# Run: sh tools/test_gbos_fp.sh            (SENSOR=1 sh tools/test_gbos_fp.sh on a laptop with the sensor)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/gbosfp.XXXXXX"); trap 'rm -rf "$W"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok   $*"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "FAIL $*"; }
H=$ROOT/usb/hook.sh
F=$ROOT/fingerprint

# soft_gk signs the password tokens gbos_fp checks: the key must be the same string
k1=$(grep -o 'auth_key\[32\] = "[^"]*"' "$ROOT/gatekeeper/soft_gk.c")
k2=$(grep -o 'auth_key\[32\] = "[^"]*"' "$F/gbos_fp.c")
[ -n "$k1" ] && [ "$k1" = "$k2" ] && ok "HardwareAuthToken key identical in soft_gk.c and gbos_fp.c" || bad "auth_key differs: '$k1' vs '$k2'"

# the sensors hook.sh starts gbos_fp for are the ones syn.h drives
p1=$(sed -n '/^static const uint16_t syn_pids/,/^};/p' "$F/syn.h" | grep -o '0x[0-9a-f]\{4\}' | sed 's/0x//' | tr '\n' ' ' | sed 's/ $//')
p2=$(sed -n 's/^GBOS_FP_PIDS="\(.*\)"$/\1/p' "$H")
[ -n "$p1" ] && [ "$p1" = "$p2" ] && ok "product ids identical in syn.h and hook.sh ($(echo $p1 | wc -w))" || bad "id lists differ: syn.h '$p1' vs hook.sh '$p2'"

# hook.sh: detection function and the FPRC block
awk '/^GBOS_FP_PIDS=/{p=1} p{print} p&&/^}/{exit}' "$H" > "$W/detect.sh"
awk '/^  FPRC=$/{p=1} p{print} p&&/^  fi$/{exit}' "$H" > "$W/block.sh"
[ -s "$W/detect.sh" ] && [ -s "$W/block.sh" ] && ok "detection and service block extracted from hook.sh" || { bad "blocks not found in hook.sh"; exit 1; }
usbdev() { mkdir -p "$W/usb/$1"; echo "$2" > "$W/usb/$1/idVendor"; echo "$3" > "$W/usb/$1/idProduct"; }
run() {	# prints FPRC, after: FINGERPRINT value
  ( G=$W/g; USBDEVS=$W/usb; FINGERPRINT=$1; log() { :; }
    . "$W/detect.sh"; . "$W/block.sh"; printf '%s' "$FPRC" )
}
mkdir -p "$W/g" && : > "$W/g/gbos_fp" && chmod +x "$W/g/gbos_fp"
usbdev 3-1 8087 0026		# Intel Bluetooth
usbdev 3-2 06cb 0001		# a Synaptics device that is not a fingerprint sensor
[ -z "$(run 1)" ] && ok "no sensor: no gbos_fp service" || bad "service added without a sensor"
usbdev 3-3 06cb 00f9		# X13 Gen 2i sensor
out=$(run 1)
echo "$out" | grep -q '^service gbos_fp /postinstall/gbos/gbos_fp$' && ok "X13 sensor: gbos_fp service added" || bad "no service for 06cb:00f9"
echo "$out" | grep -q '06cb:00f9' && ok "service comment names the sensor" || bad "sensor id missing from the block"
for l in '    class hal' '    user system' '    group system usb' '    seclabel u:r:hal_fingerprint_default:s0' \
	 '    interface aidl android.hardware.biometrics.fingerprint.IFingerprint/default' '    mkdir /data/vendor/crosfp 0770 system system'; do
  echo "$out" | grep -qxF "$l" && ok "block has:$l" || bad "block lacks:$l"
done
echo "$out" | grep -q 'user root\|group root' && bad "gbos_fp would run as root" || ok "gbos_fp does not run as root"
[ -z "$(run 0)" ] && ok "FINGERPRINT=0: no service" || bad "FINGERPRINT=0 ignored"
rm "$W/g/gbos_fp"
[ -z "$(run 1)" ] && ok "binary missing from the stick: no service" || bad "service added without the binary"

# gbos.rc gets the block, the image and deploy scripts ship the binary
grep -q '^\$FPRC$' "$H" && ok "hook: \$FPRC is written into gbos.rc" || bad "hook: \$FPRC never written into gbos.rc"
grep -q 'soft_gk gbos_fp' "$ROOT/tools/make_gbos86_image.sh" && ok "make_gbos86_image.sh copies gbos_fp" || bad "image lacks gbos_fp"
grep -q 'soft_gk gbos_fp' "$ROOT/tools/deploy_stick.sh" && ok "deploy_stick.sh copies gbos_fp" || bad "deploy lacks gbos_fp"
[ -x "$ROOT/usb/gbos_fp" ] && ok "usb/gbos_fp built" || bad "usb/gbos_fp missing (fingerprint/build.sh)"
sh -n "$H" && ok "sh -n hook.sh" || bad "syntax"

if [ "${SENSOR:-0}" = 1 ]; then
  dev=$(for d in /sys/bus/usb/devices/*; do [ "$(cat $d/idVendor 2>/dev/null)" = 06cb ] || continue
	  printf '/dev/bus/usb/%03d/%03d\n' "$(cat $d/busnum)" "$(cat $d/devnum)"; done | head -1)
  if [ -n "$dev" ] && out=$(docker run --rm --device "$dev" -v "$F:/fp:z" "${IMAGE:-gbos-fpbuild}" /fp/syn_test probe 2>&1); then
    echo "$out" | sed 's/^/     /'
    echo "$out" | grep -q SYN_TEST_PASS && ok "real sensor: probe passes" || bad "real sensor: probe failed"
  else
    bad "real sensor: no Synaptics device or docker run failed: ${out:-}"
  fi
fi

echo "$n checks, $fail failed"
[ $fail = 0 ] && echo GBOS_FP_TEST_PASS
exit $fail
