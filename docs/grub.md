# Boot menu (GRUB, Material 3)

![The googlebook-m3 GRUB theme, rendered by GRUB 2.12 in QEMU](img/grub.png)

Fedora already boots through GRUB (shim → `EFI/fedora/grubx64.efi` → `/boot/grub2/grub.cfg`), but hides it: Fedora sets
`menu_auto_hide` while only one system is installed, and draws GRUB in text mode (`GRUB_TERMINAL_OUTPUT="console"`), so no
theme can show. `tools/grub/install_grub.sh` turns it into the boot menu for both systems.

## The theme: `googlebook-m3`
Made by `tools/grub/make_theme.py` (Pillow + `grub2-mkfont`) for the 1920x1200 panel:
- Material 3 dark scheme from a blue seed: surface `#111318`, a `surface-container` card with 40 px corners, the selected row
  as a `secondary-container` pill, icons on `primary` circles.
- M3 Expressive shapes in the background: a 12-lobe "cookie" (primary container) and an 8-lobe "flower" (tertiary container).
- Adwaita Sans: the title, subtitle and key hints are drawn into the background at real weights; menu labels (26 px) and the
  countdown (18 px) use GRUB fonts made from the same font (Latin and arrows only, to keep them small).
- Icons by GRUB class: `fedora` (Fedora's entries carry `grub_class fedora`), `googlebook`, `efi`.

GRUB draws a row's pixmap box *around* the row, padded by the corner images' size, so `item_height` is the visible row minus
twice the corner radius, every row gets a transparent box of the same size, and `item_spacing` makes up the rest.

Checked in a real GRUB 2.12 (`grub2-mkstandalone` + OVMF in QEMU at 1920x1200): layout, selection moving with the arrow keys,
countdown. The same test chainloaded the real `BOOTX64.EFI` with the options below (with `console=ttyS0` instead of
`ttynull`): the kernel was quiet and stage0's output went to the serial port, so GRUB passes the options through.

## `tools/grub/install_grub.sh`
Dry run by default; `--run` asks before each step (`y` continues, anything else stops).

| Step | What |
|---|---|
| 1 | Copy the theme to `/boot/grub2/themes/googlebook-m3` (checks that `EFI/gbos/BOOTX64.EFI` exists) |
| 2 | `/etc/grub.d/25_googlebook`: after Fedora's entries, before "UEFI Firmware Settings" |
| 3 | `/etc/default/grub`: `GRUB_TERMINAL_OUTPUT="gfxterm"`, `GRUB_GFXMODE="1920x1200,auto"`, `GRUB_THEME=…/theme.txt`; the original is kept as `/etc/default/grub.before-googlebook-m3` |
| 4 | `grub2-editenv - unset menu_auto_hide`: the menu shows on every boot (5 s, `GRUB_TIMEOUT`), then the default (Fedora) |
| 5 | `grub2-mkconfig -o /boot/grub2/grub.cfg`, then checks the entry and the theme are in it |
| 6 | Firmware entries: removes the external SSD's "Googlebook" and recreates "Googlebook (internal)" under the same number as "Googlebook" (same kernel and options) |

The Googlebook entry:
```
menuentry 'Googlebook' --class googlebook --id googlebook {
	insmod part_gpt
	insmod fat
	insmod chain
	search --no-floppy --fs-uuid --set=root 4F51-E681
	chainloader /EFI/gbos/BOOTX64.EFI quiet loglevel=1 printk.ignore_loglevel=0 vt.global_cursor_default=0 console=ttynull
}
```
`chainloader` hands the rest of the line to the kernel's EFI stub as load options, exactly like the firmware entry does
(Secure Boot is off on this laptop; with it on, shim's GRUB would refuse the unsigned kernel). Fedora's kernel updates go
through BLS entries and do not need `grub2-mkconfig`, so the Googlebook entry stays.

## Changing it
Edit `make_theme.py` (colours in `C`, layout constants at the top), run it, then step 1 again (`sudo cp -r`); no
`grub2-mkconfig` needed unless the font names change.

## Undo
```sh
sudo cp -p /etc/default/grub.before-googlebook-m3 /etc/default/grub
sudo rm /etc/grub.d/25_googlebook; sudo rm -r /boot/grub2/themes/googlebook-m3
sudo grub2-editenv - set menu_auto_hide=1
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```
The firmware "Googlebook" entry (F12) is not affected.
