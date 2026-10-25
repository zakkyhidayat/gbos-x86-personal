# Quiet and fast boot

Measured on this laptop from the boot logs: **67.6 s → 29.2 s** from power-on to Android's `boot_completed`. Before, the
whole kernel log scrolled on screen until the Googlebook animation and again at shutdown.

## Where the time went

| Where | Cost | Fix |
|---|---|---|
| `gscutil.rc` waits for Google's security chip (`wait /dev/tpm0 10` at post-fs), then fails | 10 s | `hook.sh` removes it from init, as gbOS86 already does for `gscd.rc` |
| Google's fstab mounts `userdata` with `wait`; `/data` is already mounted by stage0, so `mount_all` waited 20 s for `/dev/block/by-name/userdata` and then skipped it | 20 s | `hook.sh` names that device `LABEL=gbos-data-mounted-by-stage0`. fs_mgr gives up on a label longer than ext4's 16 bytes before it waits (the same skip, at once), and such a label can never match a disk. Checked against AOSP's `fs_mgr.cpp`; nothing else in the entry changes |
| stage0 runs `modprobe i915`, which fails here (stage0 has no i915 for Iris Xe; hwdetect loads it later), then sleeps | 2 s | `LOAD_I915=0` in `gbos.cfg` |
| Trusty VM exit trace: ~30 MB written to the boot drive while Android starts | I/O, CPU | Only with `KVM_TRACE=1` (the ftrace events in `gbos.rc` and the reader in `hook.sh`) |
| Debug logging on every boot: full logcat (~10 MB), KMS debug, audio/display/AI diagnostics (dumpsys, pings) | I/O, CPU | Only with `DEBUG_LOGS=1` |
| Kernel and init text drawn on the framebuffer console | slows the boot | `usb/quiet_boot.sh` and the boot entry options (below) |
| Crash loops: `timberslide` (copies the ChromeOS EC log; no EC here) 70 restarts, `suspend_notification_service` 346 restarts in 6 min | CPU, log noise | See [Crash loops](#crash-loops) |

Not changed, because they are inside upstream's `BOOTX64.EFI`: stage0's 6 s wait for a USB stick labelled `GBOS` after
`GBOSSYS` appears, and hwdetect's driver loading (~5 s).

## Hiding the text
Three layers, each covering a stretch the others cannot:

1. **Boot entry options** (from power-on). The kernel's built-in command line has `loglevel=8 ignore_loglevel`. Its
   config has `CONFIG_CMDLINE_BOOL=y` without `CMDLINE_OVERRIDE`, so options from the firmware boot entry are appended after the
   built-in ones and win. The Googlebook entries pass:

   | Option | Effect |
   |---|---|
   | `quiet loglevel=1` | Only emergencies (a panic) reach the screen |
   | `printk.ignore_loglevel=0` | Undoes the built-in `ignore_loglevel` |
   | `vt.global_cursor_default=0` | No blinking text cursor |
   | `console=ttynull` | `/dev/console` goes nowhere (`CONFIG_NULL_TTY=y`), which also hides what stage0's shell prints, e.g. `mknod: /dev/mapper/control: File exists`. The boot menu, installer and rescue shell write to `/dev/tty1` and stay visible |

2. **`usb/quiet_boot.sh`** (from ~8 s, when the drive is found), sourced from `gbos.cfg`: sets the same console level,
   clears the screen and hides the cursor. That covers booting without the options too (e.g. the firmware's generic USB
   entry). If stage0 fails, its rescue shell first brings the text back with the last 30 messages. The installer is left
   alone (it needs the screen and cursor).
3. **Shutdown and restart:** `gbos.rc` unbinds the framebuffer console at `on shutdown`, so the kernel's last "Restarting
   system" / "Power down" (an emergency-level message) has nowhere to appear.

Every message still goes to `gbos/logs/boot-N/kmsg.log`. `QUIET_BOOT=0` in `gbos.cfg` turns layers 2 and 3 off; for layer 1,
pick the firmware's plain entry for the drive instead.

## Crash loops
- **`timberslide`** copies the ChromeOS EC console log from `/dev/cros_ec`, which this laptop does not have: `hook.sh` removes
  `timberslide.rc`. Nothing depends on it.
- **`suspend_notification_service`** needs Google's `suspend_notifier` kernel module, which does not load on gbOS86's kernel,
  so it exits at once; `suspend_diagnostics` asked for it about once a second, and each request started it again. Only
  `suspend_diagnostics` (a diagnostics daemon with no interface) is masked. The notification service itself stays declared,
  because system_server's desktop services may ask for it, and they should keep failing fast rather than wait forever for a
  service that is no longer declared.

Idea from [vthonte/gbos86-persistent-dualboot](https://github.com/vthonte/gbos86-persistent-dualboot), which removes both
services.

## Boot entries
Made once from Linux with `efibootmgr`, which writes the laptop's firmware settings (not a disk). Now: `Boot0001` Fedora
(GRUB, with Googlebook in its menu: [grub.md](grub.md)) and `Boot0000` Googlebook. ThinkPad's F12 menu only
lists entries that are in the boot order, so each one is put right after Fedora:

```sh
OPTS='quiet loglevel=1 printk.ignore_loglevel=0 vt.global_cursor_default=0 console=ttynull'
# the internal install (now Boot0000 "Googlebook"): kernel on Fedora's EFI partition
sudo efibootmgr -C -d /dev/nvme0n1 -p 1 -L Googlebook -l '\EFI\gbos\BOOTX64.EFI' -u "$OPTS"
# an external drive (its own EFI partition); the SSD's entry was removed once the internal install existed
sudo efibootmgr -C -d /dev/sda -p 1 -L 'Googlebook (SSD)' -l '\EFI\BOOT\BOOTX64.EFI' -u "$OPTS"
sudo efibootmgr -o 0001,<new>,...          # keep Fedora (0001) first
sudo efibootmgr -b <N> -B                  # remove an entry
```

## Tests
`tools/test_boot_quiet.sh`: `quiet_boot.sh` against a fake `/sys` and `/proc` (quiet, `QUIET_BOOT=0`, installer from the menu
or `MODE=install`, rescue shell), the generated `gbos.rc` without the debug extras (and with the Trusty VM still started),
the crash-loop changes, and the fstab rewrite. Pass it the image's `fstab.android-desktop` to check Google's real file.
