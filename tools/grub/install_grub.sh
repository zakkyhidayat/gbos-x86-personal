#!/bin/sh
# Fedora's GRUB as the boot menu for Fedora and Googlebook, with the googlebook-m3 Material 3 theme:
#   1. theme to /boot/grub2/themes/googlebook-m3 (made by tools/grub/make_theme.py)
#   2. /etc/grub.d/25_googlebook: a "Googlebook" entry after Fedora's that chainloads EFI/gbos/BOOTX64.EFI from Fedora's EFI
#      partition with the quiet options (GRUB passes them to the kernel as load options, like the firmware entry)
#   3. /etc/default/grub: graphical terminal at 1920x1200 with the theme (the original is kept as grub.before-googlebook-m3)
#   4. show the menu on every boot (Fedora hides it while only one system is installed: menu_auto_hide)
#   5. regenerate /boot/grub2/grub.cfg and check it
#   6. firmware entries: remove the external SSD's "Googlebook", rename "Googlebook (internal)" to "Googlebook"
#
#   sh tools/grub/install_grub.sh          dry run: shows every command, changes nothing
#   sh tools/grub/install_grub.sh --run    does it, asking before each step
# Undo: see docs/grub.md.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
THEME=$HERE/googlebook-m3 DEST=/boot/grub2/themes/googlebook-m3
OPTS='quiet loglevel=1 printk.ignore_loglevel=0 vt.global_cursor_default=0 console=ttynull'
RUN=; [ "$1" = --run ] && RUN=1
die() { echo "install_grub: $*" >&2; exit 1; }
step() {
  echo; echo "== $1"; shift; echo "   \$ $*"
  [ -n "$RUN" ] || return 0
  printf '   run this step? [yes/no] '; read a; [ "$a" = yes ] || die "stopped before: $*"
  "$@"
}

[ -f "$THEME/theme.txt" ] || die "no theme: run python3 tools/grub/make_theme.py first"
command -v grub2-mkconfig >/dev/null || die "grub2-mkconfig not found (Fedora's grub2-tools)"
ESPDEV=$(findmnt -no SOURCE /boot/efi) || die "Fedora's EFI partition is not mounted at /boot/efi"
ESPUUID=$(lsblk -no UUID "$ESPDEV"); ESPNUM=$(cat /sys/class/block/$(basename "$ESPDEV")/partition)
DISK=/dev/$(lsblk -no PKNAME "$ESPDEV")
[ -n "$ESPUUID" ] || die "no UUID for $ESPDEV"

ENTRY="#!/bin/sh
# Googlebook (gbOS86) beside Fedora: tools/install_internal.sh put its kernel on this EFI partition.
cat <<'EOF'
menuentry 'Googlebook' --class googlebook --id googlebook {
	insmod part_gpt
	insmod fat
	insmod chain
	search --no-floppy --fs-uuid --set=root $ESPUUID
	chainloader /EFI/gbos/BOOTX64.EFI $OPTS
}
EOF"

# firmware entries now
SSDNUM=$(efibootmgr -v | sed -n 's/^Boot\([0-9A-F]\{4\}\)\* Googlebook[[:space:]].*\\EFI\\BOOT\\BOOTX64\.EFI.*/\1/p')
INTNUM=$(efibootmgr | sed -n 's/^Boot\([0-9A-F]\{4\}\)\* Googlebook (internal).*/\1/p')
ORDER=$(efibootmgr | sed -n 's/^BootOrder: //p')
NEWORDER=$(echo "$ORDER" | tr ',' '\n' | grep -vx "${SSDNUM:-none}" | paste -sd,)

cat <<EOF
Fedora's EFI partition $ESPDEV (UUID $ESPUUID); Googlebook kernel expected at EFI/gbos/BOOTX64.EFI
Firmware entries: external SSD "Googlebook" = ${SSDNUM:-none}, "Googlebook (internal)" = ${INTNUM:-none}; order $ORDER -> $NEWORDER
EOF
[ -n "$RUN" ] || echo "(dry run: nothing is changed; --run to do it)"

set_key() {  # set_key KEY VALUE in /etc/default/grub
  if grep -q "^$1=" /etc/default/grub; then sudo sed -i "s|^$1=.*|$1=\"$2\"|" /etc/default/grub
  else echo "$1=\"$2\"" | sudo tee -a /etc/default/grub >/dev/null; fi
}

step "1/6 install the theme" \
  sh -c "sudo test -f /boot/efi/EFI/gbos/BOOTX64.EFI || { echo '   no EFI/gbos/BOOTX64.EFI on the EFI partition (tools/install_internal.sh)'; exit 1; }; \
    sudo rm -rf '$DEST' && sudo mkdir -p /boot/grub2/themes && sudo cp -r '$THEME' '$DEST' && sudo ls '$DEST' | tr '\n' ' ' && echo"
step "2/6 the Googlebook menu entry (/etc/grub.d/25_googlebook)" \
  sh -c "printf '%s\n' \"\$1\" | sudo tee /etc/grub.d/25_googlebook >/dev/null && sudo chmod 755 /etc/grub.d/25_googlebook && sudo cat /etc/grub.d/25_googlebook | sed -n '/menuentry/,/^}/p'" _ "$ENTRY"
if [ -n "$RUN" ]; then
  echo; echo "== 3/6 /etc/default/grub: GRUB_TERMINAL_OUTPUT=gfxterm, GRUB_GFXMODE=1920x1200,auto, GRUB_THEME=$DEST/theme.txt"
  printf '   run this step? [yes/no] '; read a; [ "$a" = yes ] || die "stopped at step 3"
  sudo test -f /etc/default/grub.before-googlebook-m3 || sudo cp -p /etc/default/grub /etc/default/grub.before-googlebook-m3
  set_key GRUB_TERMINAL_OUTPUT gfxterm; set_key GRUB_GFXMODE 1920x1200,auto; set_key GRUB_THEME "$DEST/theme.txt"
  grep -E '^GRUB_(TERMINAL_OUTPUT|GFXMODE|THEME|TIMEOUT)=' /etc/default/grub | sed 's/^/   /'
else
  echo; echo "== 3/6 /etc/default/grub: GRUB_TERMINAL_OUTPUT=gfxterm, GRUB_GFXMODE=1920x1200,auto, GRUB_THEME=$DEST/theme.txt (backup: /etc/default/grub.before-googlebook-m3)"
fi
step "4/6 show the menu on every boot" sudo grub2-editenv - unset menu_auto_hide
step "5/6 regenerate /boot/grub2/grub.cfg and check it" \
  sh -c "sudo grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 | tail -3 && sudo grep -q \"menuentry 'Googlebook'\" /boot/grub2/grub.cfg && sudo grep -q 'googlebook-m3/theme.txt' /boot/grub2/grub.cfg && echo '   grub.cfg has the Googlebook entry and the theme'"
if [ -n "$INTNUM$SSDNUM" ]; then
  CMD=":"
  [ -n "$SSDNUM" ] && CMD="$CMD && sudo efibootmgr -q -b $SSDNUM -B"
  [ -n "$INTNUM" ] && CMD="$CMD && sudo efibootmgr -q -b $INTNUM -B && sudo efibootmgr -q -C -b $INTNUM -d $DISK -p $ESPNUM -L Googlebook -l '\\EFI\\gbos\\BOOTX64.EFI' -u '$OPTS'"
  step "6/6 firmware entries: remove the SSD's, rename the internal one to \"Googlebook\"" \
    sh -c "$CMD && sudo efibootmgr -q -o $NEWORDER && efibootmgr | grep -E '^BootOrder|Googlebook'"
fi
[ -n "$RUN" ] && echo && echo "Done. On the next boot GRUB shows Fedora and Googlebook (5 s, then Fedora)."
:
