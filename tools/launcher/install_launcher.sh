#!/bin/sh
# Install the "Googlebook VM" app launcher for this user: ~/.local/share/applications/googlebook-vm.desktop, which runs
# tools/run_vm.sh without a terminal (run_vm.sh then asks once through GNOME's polkit dialog), with the icon in this folder.
#   sh tools/launcher/install_launcher.sh                 use googlebook-vm.png from this folder
#   sh tools/launcher/install_launcher.sh WALLPAPER       draw a new icon with make_icon.py, WALLPAPER on the laptop's screen
set -e
HERE=$(cd "$(dirname "$0")" && pwd); RUNVM=$(cd "$HERE/.." && pwd)/run_vm.sh
D=$HOME/.local/share/googlebook-vm; APP=$HOME/.local/share/applications/googlebook-vm.desktop
mkdir -p "$D" "$(dirname "$APP")"
if [ -n "$1" ]; then
  [ -f "$1" ] || { echo "no wallpaper at $1"; exit 1; }
  python3 -I "$HERE/make_icon.py" "$1" "$D/googlebook-vm.png"
else
  cp "$HERE/googlebook-vm.png" "$D/googlebook-vm.png"
fi
cat > "$APP" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Googlebook VM
Comment=Boot the installed Googlebook as a throwaway snapshot (nothing is kept)
Exec=sh $RUNVM
Icon=$D/googlebook-vm.png
Terminal=false
Categories=System;Emulator;
Keywords=android;googlebook;qemu;vm;
StartupWMClass=qemu-system-x86_64
DESKTOP
desktop-file-validate "$APP"
update-desktop-database "$(dirname "$APP")" 2>/dev/null || true
echo "installed: $APP (icon $D/googlebook-vm.png)"
