#!/bin/sh
# Checks the quiet/faster boot changes: usb/quiet_boot.sh (run against a fake /sys, /proc and tty), hook.sh's fstab rewrite (on a
# copy of Google's fstab.android-desktop), and that gscutil.rc, the KVM trace and the shutdown console are handled.
# Usage: sh tools/test_boot_quiet.sh [path/to/fstab.android-desktop]
cd "$(dirname "$0")/.." || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; bad=0
ok() { n=$((n+1)); echo "ok   $*"; }
no() { n=$((n+1)); bad=$((bad+1)); echo "FAIL $*"; }
chk() { d=$1; shift; if [ "$1" = '!' ]; then shift; if "$@"; then no "$d"; else ok "$d"; fi; elif "$@"; then ok "$d"; else no "$d"; fi; }

# --- quiet_boot.sh against a fake root
fake() {
  rm -rf $T/r; mkdir -p $T/r/sys/module/printk/parameters $T/r/proc/sys/kernel $T/r/sys/class/graphics/fbcon
  echo Y > $T/r/sys/module/printk/parameters/ignore_loglevel; echo "8 4 1 8" > $T/r/proc/sys/kernel/printk
  echo 1 > $T/r/sys/class/graphics/fbcon/cursor_blink; : > $T/r/tty1
  sed "s#\\([ >]\\)/sys/#\\1$T/r/sys/#g; s#\\([ >]\\)/proc/#\\1$T/r/proc/#g; s#/dev/tty1#$T/r/tty1#g" usb/quiet_boot.sh > $T/q.sh
}
run() { ( shell() { echo orig; }; log() { :; }; eval "$1"; . $T/q.sh; cp $T/r/tty1 $T/r/tty1.boot; cat $T/r/sys/module/printk/parameters/ignore_loglevel > $T/r/ign.boot; cat $T/r/proc/sys/kernel/printk > $T/r/printk.boot; shell x > $T/r/shellout 2>/dev/null ) }
fake; run "MODE=boot FROM=nvme"
chk "quiet: ignore_loglevel off" [ "$(cat $T/r/ign.boot)" = 0 ]
chk "quiet: console loglevel 1" [ "$(cat $T/r/printk.boot)" = 1 ]
chk "quiet: cursor blink off" [ "$(cat $T/r/sys/class/graphics/fbcon/cursor_blink)" = 0 ]
chk "quiet: screen cleared, cursor hidden" grep -q '?25l' $T/r/tty1.boot
chk "quiet: rescue shell brings the text back" [ "$(cat $T/r/sys/module/printk/parameters/ignore_loglevel)/$(cat $T/r/proc/sys/kernel/printk)" = 1/8 ]
fake; run "QUIET_BOOT=0 MODE=boot FROM=nvme"
chk "QUIET_BOOT=0: nothing changed" [ "$(cat $T/r/proc/sys/kernel/printk)" = "8 4 1 8" ]
chk "QUIET_BOOT=0: stage0's own shell kept" grep -qx orig $T/r/shellout
fake; run "SELMODE=install MODE=install FROM=stick"
chk "installer from the menu: left alone" [ "$(cat $T/r/proc/sys/kernel/printk)" = "8 4 1 8" ]
fake; run "MODE=install FROM=stick"
chk "MODE=install on the stick: left alone" [ "$(cat $T/r/proc/sys/kernel/printk)" = "8 4 1 8" ]
fake; run "MODE=install FROM=nvme"
chk "MODE=install but booting the drive: quiet" [ "$(cat $T/r/printk.boot)" = 1 ]
chk "gbos.cfg sources quiet_boot.sh" grep -q '^\[ -f /gbos/gbos/quiet_boot.sh \] && \. /gbos/gbos/quiet_boot.sh$' usb/gbos.cfg
for f in tools/make_gbos86_image.sh tools/deploy_stick.sh usb/install.sh; do chk "$f ships quiet_boot.sh" grep -q 'quiet_boot\.sh' $f; done

# --- hook.sh: fstab rewrite, run as hook.sh runs it
FS=${1:-}
[ -n "$FS" ] || { FS=$T/fstab; printf '%s\n' \
  'system /system erofs ro wait,logical,first_stage_mount,slotselect,avb=vbmeta' \
  '/dev/block/by-name/userdata /data ext4 rw,nodev,noatime,nosuid,errors=panic wait,check,quota,formattable,latemount,fileencryption=aes-256-xts:aes-256-cts,keydirectory=/metadata/vold/metadata_encryption,fsverity,reservedsize=128M,checkpoint=block' \
  '/dev/block/by-name/metadata /metadata ext4 noatime,nosuid,nodev,discard,data=journal,commit=1 wait,formattable,first_stage_mount,check' \
  '/devices/*/usb*           auto      auto     defaults voldmanaged=usb:auto' > $FS; }
F=$FS; eval "$(grep "^grep -v 'voldmanaged=usb' \$F | sed" usb/hook.sh | sed 's/ \\$//; s#> /tmp/fstab.android-desktop#> $T/out#')"
U=$(grep ' /data ' $T/out)
chk "fstab: /data entry keeps its options" [ "${U#* }" = "$(grep ' /data ' $FS | sed 's/^[^ ]* //')" ]
L=${U%% *}; L=${L#LABEL=}
chk "fstab: /data device is a LABEL= longer than 16 bytes (${#L})" [ "${U#LABEL=}" != "$U" ] && [ ${#L} -gt 16 ]
chk "fstab: other lines unchanged" [ "$(grep -v ' /data ' $T/out)" = "$(grep -v -e ' /data ' -e voldmanaged=usb $FS)" ]
nousb() { ! grep -q voldmanaged=usb $T/out; }
chk "fstab: vold USB rule still removed" nousb

# --- hook.sh: gbos.rc without the debug extras (the template as hook.sh writes it, then its DEBUG_LOGS/KVM_TRACE edits)
sed -n '/^  cat > \/tmp\/sysinit\/gbos.rc <<RC$/,/^RC$/p' usb/hook.sh | sed '1d;$d' > $T/rc.full
cp $T/rc.full $T/gbos.rc; log() { :; }
eval "$(sed -n '/^  if \[ "${DEBUG_LOGS:-0}" != 1 \]; then$/,/^  fi$/p; /^  \[ "${KVM_TRACE:-0}" = 1 \] || sed -i/p' usb/hook.sh | sed "s#/tmp/sysinit/gbos.rc#$T/gbos.rc#g")"
has() { grep -qx "    $1" $T/gbos.rc; }
for s in logcat audiodiag displaydiag aidiag; do chk "debug off: no start gbos_$s" ! has "start gbos_$s"; done
for s in crashlog sync ksu; do chk "debug off: gbos_$s still started" has "start gbos_$s"; done
chk "debug off: Trusty VM still started at early-fs" has "start trusty_security_protected_vm_launcher"
chk "kvm trace off: no ftrace event enabled" ! grep -q '^    write /sys/kernel/tracing/events/' $T/gbos.rc
chk "kvm trace off: no tracing_on 1 / buffer size" ! grep -q -e 'tracing_on 1' -e buffer_size_kb $T/gbos.rc
chk "kvm trace off: only those lines removed" [ $(($(wc -l < $T/rc.full) - $(wc -l < $T/gbos.rc))) = $((5 + 16)) ]
chk "drm.debug only with DEBUG_LOGS=1" grep -q '^\[ "${DEBUG_LOGS:-0}" = 1 \] && echo 0x04 > /sys/module/drm/parameters/debug' usb/hook.sh

# --- hook.sh: the rest
chk "gscutil.rc removed from init" grep -q '^  rm -f /tmp/sysinit/gscutil.rc' usb/hook.sh
chk "KVM trace only with KVM_TRACE=1" grep -q 'if \[ "${KVM_TRACE:-0}" != 1 \]; then' usb/hook.sh
chk "gbos.rc gets the shutdown block" grep -qx '\$QUIETRC' usb/hook.sh
chk "shutdown block unbinds the framebuffer console" grep -q 'write $v/bind 0' usb/hook.sh
chk "hook.sh parses" sh -n usb/hook.sh
chk "quiet_boot.sh parses" sh -n usb/quiet_boot.sh

echo "$((n-bad))/$n passed"
[ $bad = 0 ]
