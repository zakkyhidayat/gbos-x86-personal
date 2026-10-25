#!/bin/sh
# Install the "Googlebook VM" app launcher for this user: the icon (make_icon.py, from a wallpaper you provide; the wallpaper
# is not in this repo) and ~/.local/share/applications/googlebook-vm.desktop, which runs tools/run_vm.sh without a terminal
# (run_vm.sh then asks once through GNOME's polkit dialog).
#   sh tools/launcher/install_launcher.sh [WALLPAPER]     default: ~/Downloads/aluminium-os-stock-3636x3636-26364.jpeg
set -e
HERE=$(cd "$(dirname "$0")" && pwd); RUNVM=$(cd "$HERE/.." && pwd)/run_vm.sh
WP=${1:-$HOME/Downloads/aluminium-os-stock-3636x3636-26364.jpeg}
D=$HOME/.local/share/googlebook-vm; APP=$HOME/.local/share/applications/googlebook-vm.desktop
[ -f "$WP" ] || { echo "no wallpaper at $WP (give its path as the first argument)"; exit 1; }
mkdir -p "$D" "$(dirname "$APP")"
python3 -I "$HERE/make_icon.py" "$WP" "$D/googlebook-vm.png"
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
