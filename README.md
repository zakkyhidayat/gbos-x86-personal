# Personal Googlebook x86-64 script for ThinkPad X13 Gen 2i

My own additions for running Googlebook OS on x86-64 through [gbOS86](https://github.com/linuxkid473/gbos-x86) on a
**ThinkPad X13 Gen 2i** (machine type 20WL, Intel i5-1145G7, Synaptics 06cb:00f9 fingerprint reader). Personal use only.

This repo holds only my files. gbos-x86 itself is not copied here: `apply.sh` puts these files onto a gbos-x86 checkout and
applies `patches/gbos-x86-changes.patch` to the few upstream files they hook into.

Current base: upstream `729b9c3` (kernel #42, `6.18.21-gbos-whl`, module tree r5, release v40).

## What it changes and adds

### 1. Lenovo identity instead of "ASUS Googlebook 14"
Google's lapis build names the device ASUS / "ASUS Googlebook 14" in the `ro.product.<partition>.brand`, `.manufacturer`,
`.model` and `.marketname` of seven partitions (vendor, product, odm, odm_dlkm, system_ext, system_dlkm, vendor_dlkm).
gbOS86's own `DEVICE_MODEL` only covered the vendor model lines.

- `usb/hook.sh` (patch): `DEVICE_BRAND` / `DEVICE_MODEL` from `gbos.cfg` replace those values in all seven, whatever name
  Google's build uses, so a newer Google build is covered too. Values with `/ \ &` are refused.
- `usb/gbos.cfg` (patch): `DEVICE_BRAND="LENOVO"`, `DEVICE_MODEL="ThinkPad X13 Gen 2i"`.
- Kept on purpose: `ro.product.*.device=lapis` and every build fingerprint (`ASUS/lapis/lapis:17/...`), so Play Integrity
  and Google services keep seeing the build they know.

Result: Settings > About and the device name show **ThinkPad X13 Gen 2i**, brand **LENOVO**.

### 2. Fingerprint reader (new HAL)
Google's crosfp HAL only drives Google's own fingerprint MCU, so the X13's Synaptics sensor had no driver at all.

- `fingerprint/gbos_fp.c`: an `android.hardware.biometrics.fingerprint.IFingerprint/default` HAL (AIDL V4), written like
  gbOS86's `soft_gk`: plain C, no NDK, linked against the image's own libraries. Enroll, authenticate, remove, enumerate,
  challenges, lockout.
- `fingerprint/syn.h`: the sensor protocol, a port of libfprint's Synaptics driver (LGPL-2.1) to usbfs. Templates are stored
  and matched on the sensor itself.
- `usb/gbos_fp`: the built binary. `usb/hook.sh` (patch) starts it only when a Synaptics sensor is on USB at boot; its
  service declares the interface, so init drops crosfp's. `FINGERPRINT=0` turns it off.
- Security: registered as a **WEAK** (Class 2) sensor: unlocks the lock screen and weak-biometric app prompts, never
  Keystore keys (the match happens on a USB device the host cannot authenticate). Enrolling and clearing a lockout need a
  fresh lock-screen password token from soft_gk. Only system_server (uid 1000) may call it. Lockout: 30 s after every 5
  failures, permanent after 20, kept across reboots. Templates are named `GBOS-<install>-u<user>-<id>`: only the current
  user's own are offered to the sensor or deleted, so Fedora's fingerprints (fprintd) on the same sensor stay untouched and
  never unlock Android.
- Robust against what Android's Settings does to the sensor: its "touch the sensor" screen starts an enroll and cancels it
  at the first touch. A cancel the sensor does not take at once is retried (as libfprint does), a sensor that stops
  answering is reset on the next open, an I/O error during a requested cancel is reported as CANCELED, and the sensor's
  "busy" (102) and "finger still resting" (213) answers are retried instead of failing the setup.
- Accuracy is the sensor's own: matching runs in its firmware, and the HAL does not lower any threshold. A touch that adds
  nothing new to the template shows as "not recognised" during setup; lift and shift the finger slightly between touches.
- Debug: `logcat -s gbos_fp` shows each sensor message ID and result code (no fingerprint data).
- `fingerprint/syn_test` (from Linux, through docker): `probe`, `cycle` (enroll a throw-away template, identify, delete),
  `cancel` and `suw` (replay Settings' cancel-then-enroll flow).

### 3. adb over a Thunderbolt cable
These laptops have no USB device-mode controller, so adb over a USB cable cannot work (the official "coming soon"); Google's
image has no USB gadget setup either.

- `usb/kmod/thunderbolt_net.ko`: `CONFIG_USB4_NET`, which gbOS86's kernel leaves out, built for the shipped kernel by
  `kernel/isa_emu_patch/build_extra_module.sh`: the kernel's own config (from the IKCONFIG in `BOOTX64.EFI`), symbol CRCs
  recovered from the released module tree (`kernel/symvers_from_modules.py`), the same AOSP clang. Not signed (gbOS86's
  kernel does not enforce signatures).
- `usb/tbnet.sh`: gives `thunderbolt0` 10.42.0.2/24 and the routing rules Android leaves out. adb is not turned on by it and
  still asks to authorise the computer. `TB_NET=0` turns it off, `TB_NET_IP` changes the address.
- Use: on the other computer `nmcli con add type ethernet ifname thunderbolt0 ipv4.method manual ipv4.addresses
  10.42.0.1/24`, then `adb connect 10.42.0.2:<port>` (Wireless debugging's port, or 5555 after `adb tcpip 5555`).
- Wireless debugging and a USB Ethernet adapter (r8152, ax88179, cdc_ether in gbOS86's kernel) work too.

### 4. Quiet and faster boot
Measured on the laptop: about 67 s from power-on to `boot_completed`, with the whole kernel log scrolling on screen until the
Googlebook animation (the kernel's built-in command line has `loglevel=8 ignore_loglevel`). Most of the time was spent waiting
for hardware this laptop does not have:

| Where | Cost | Fix |
|---|---|---|
| `gscutil.rc` waits for Google's security chip (`wait /dev/tpm0 10`) | 10 s | `hook.sh` removes it, as gbOS86 already does for `gscd.rc` |
| Google's fstab has `userdata` with `wait`; `/data` is mounted by stage0, so `mount_all` waited 20 s for `/dev/block/by-name/userdata`, then skipped it | 20 s | `hook.sh` names that device `LABEL=gbos-data-mounted-by-stage0`: longer than any ext4 label, so fs_mgr skips it at once, the same skip without the wait. Nothing else in the entry changes |
| stage0 `modprobe i915` fails here (stage0 has no i915 for Iris Xe; hwdetect loads it), then sleeps | 2 s | `LOAD_I915=0` in `gbos.cfg` |
| KVM exit trace of the Trusty VM, ~30 MB written to the boot drive during boot | I/O and CPU | only with `KVM_TRACE=1` (both the ftrace events and the reader) |
| Debug logging on every boot: full logcat (~10 MB to the boot drive), KMS debug, audio/display/AI diagnostics (dumpsys, pings) | I/O and CPU | only with `DEBUG_LOGS=1`; `kmsg.log`, `crash.txt`, `hw.txt` and `hwdetect.txt` are still written |
| Kernel and init text drawn on the framebuffer console | slows the boot, and is ugly | `usb/quiet_boot.sh` |
| Crash loops: `timberslide` (ChromeOS EC log, no EC here) 70 restarts, `suspend_notification_service` 346 restarts in 6 min, started again and again for `suspend_diagnostics` | CPU, log noise | `timberslide.rc` removed; `suspend_diagnostics` masked. The notification service itself stays (system_server may ask for it, and should keep failing fast rather than wait). Idea from [vthonte](#credits) |

- `usb/quiet_boot.sh`, sourced from `gbos.cfg` as soon as the drive is found: the console only shows emergencies (a panic),
  the screen is cleared and the cursor hidden. Every message still goes to `logs/boot-N/kmsg.log`. If stage0 fails, its rescue
  shell brings the text back with the last 30 messages. The installer is left alone. `QUIET_BOOT=0` keeps the text.
- At shutdown and restart, `gbos.rc` unbinds the framebuffer console, so no text appears after the desktop goes away.
- Still visible: the first ~8 s of text, until the drive is found. That comes from the kernel's built-in command line
  (`loglevel=8 ignore_loglevel`) inside upstream's `BOOTX64.EFI`. Its config has `CMDLINE_BOOL=y` without `CMDLINE_OVERRIDE`,
  so options given by the firmware are appended after the built-in ones and win. A firmware boot entry with options hides it
  without touching the kernel (made once from Linux; it is not added to the boot order, pick "Googlebook" in the F12 menu;
  it keeps working when the SSD moves inside, since it points at the partition's GUID):

  ```sh
  N=$(sudo efibootmgr -C -d /dev/sda -p 1 -L Googlebook -l '\EFI\BOOT\BOOTX64.EFI' \
      -u 'quiet loglevel=1 printk.ignore_loglevel=0 vt.global_cursor_default=0 console=ttynull' | sed -n 's/^Boot\([0-9A-F]\{4\}\)\* Googlebook.*/\1/p')
  echo "Googlebook entry: Boot$N"
  ```
  `console=ttynull` (the kernel has `CONFIG_NULL_TTY=y`) also hides what stage0's shell prints to `/dev/console` (e.g.
  `mknod: /dev/mapper/control: File exists`); the boot menu, installer and rescue shell write to `/dev/tty1` and stay visible.
  ThinkPad's F12 menu only lists entries in the boot order: add it after Fedora with `sudo efibootmgr -o 0001,<N>,...`.
  Remove it with `sudo efibootmgr -b <N> -B`. Booting the drive the old way (its plain USB/NVMe entry) still works.
- Not changed: stage0's 6 s wait for a USB stick labelled `GBOS` after `GBOSSYS` appears (also in `BOOTX64.EFI`), and
  hwdetect's driver loading (~5 s).

### 5. Build and test helpers
- `tools/test_gbos_fp.sh`: soft_gk's token key and the sensor id list agree across files, hook.sh starts the HAL only with a
  sensor; `SENSOR=1` also probes the real sensor through docker.
- `tools/test_tbnet.sh`: the module's vermagic, all imported symbol CRCs and its kCFI hashes match the shipped kernel; the
  hook block adds the service only when the module loads.
- `tools/test_device_model.sh` (patch): the identity rewrite in all seven partitions, with a non-ASUS name.
- `tools/test_boot_quiet.sh`: `quiet_boot.sh` against a fake `/sys` and `/proc` (quiet, `QUIET_BOOT=0`, installer, rescue
  shell), the generated `gbos.rc` without the debug extras (and with the Trusty VM still started), and the fstab rewrite; give it the image's `fstab.android-desktop` to check on Google's real file.
- The patch also adds `gbos_fp`, `tbnet.sh` and `quiet_boot.sh` to gbos-x86's image, deploy and installer scripts and documents
  the options in its `gbos.cfg` and README.

## Credits
- [linuxkid473/gbos-x86](https://github.com/linuxkid473/gbos-x86) (gbOS86): everything this builds on.
- [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint): the Synaptics protocol in `fingerprint/syn.h` (LGPL-2.1).
- [vthonte/gbos86-persistent-dualboot](https://github.com/vthonte/gbos86-persistent-dualboot): the idea of turning off
  `timberslide` and the `suspend_notification_service` / `suspend_diagnostics` loop on non-Chromebook hardware.

## Use

```sh
git clone https://github.com/linuxkid473/gbos-x86
./apply.sh ../gbos-x86
cd ../gbos-x86 && sh tools/test_gbos_fp.sh && sh tools/test_tbnet.sh && sh tools/test_device_model.sh && sh tools/test_boot_quiet.sh
./build.sh --looper --data-size 100      # 128 GB drive; flash dist/gbOS86-looper-*.img with dd
```

## After a newer gbos-x86
Apply on a fresh checkout (`apply.sh` uses `git apply --3way`, so conflicts show as markers). If `test_tbnet.sh` fails on
vermagic or CRCs, upstream shipped a new kernel: rebuild the module in gbos-x86's build container
(`kernel/fetch_kernel_sources.sh`, then `build_extra_module.sh USB4_NET drivers/net/thunderbolt thunderbolt_net`, see its
header). `gbos_fp` only uses stable NDK interfaces and normally survives; rebuild it with `fingerprint/build.sh` if needed.

## Status on the laptop
Booted from a 128 GB external SSD (Lexar E6, looper image, kernel #42); the drive can later move to the internal slot,
since the partitions are found by label.

| | |
|---|---|
| Boot on kernel #42 (#37 panicked on Tiger Lake) | works |
| Settings > About: ThinkPad X13 Gen 2i, LENOVO | works |
| Fingerprint HAL registered, enrollment in Settings | works (3 fingers enrolled) |
| `thunderbolt_net` loads | works |
| Lock-screen unlock with a fingerprint | not checked yet |
| adb over a Thunderbolt cable (link, routing) | not checked yet |
| Boot time: 67.6 s -> 29.2 s to `boot_completed` (boot-4, boot-5) | works |
| Firmware entry with `quiet`: kernel text gone (boot-8, boot-9) | works |
| `console=ttynull` for stage0's own output | not checked yet |

Logs: `gbos/logs/boot-N/` on the GBOSSYS partition.
