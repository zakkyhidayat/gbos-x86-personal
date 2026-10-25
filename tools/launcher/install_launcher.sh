#!/bin/sh
# Install the "Googlebook VM" app launcher for this user: ~/.local/share/applications/googlebook-vm.desktop, which runs
# tools/run_vm.sh without a terminal (run_vm.sh then asks once through GNOME's polkit dialog), with the icon in this folder.
#   sh tools/launcher/install_launcher.sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd); RUNVM=$(cd "$HERE/.." && pwd)/run_vm.sh
D=$HOME/.local/share/googlebook-vm; APP=$HOME/.local/share/applications/googlebook-vm.desktop
mkdir -p "$D" "$(dirname "$APP")"
cp "$HERE/googlebook-vm.png" "$D/googlebook-vm.png"
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
