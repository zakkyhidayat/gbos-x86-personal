# Fingerprint reader

Google's `crosfp` HAL only drives Google's own fingerprint MCU (a ChromeOS EC), so the X13's **Synaptics 06cb:00f9**
match-on-chip USB sensor had no driver at all. `gbos_fp` is a new `android.hardware.biometrics.fingerprint.IFingerprint/default`
HAL for it.

## Files
| File | What |
|---|---|
| `fingerprint/gbos_fp.c` | The HAL (Apache-2.0). Plain C like gbOS86's `soft_gk`: no NDK, binder transactions written by hand with `libbinder_ndk`, AIDL V4 |
| `fingerprint/syn.h` | The sensor protocol over usbfs, a port of libfprint's Synaptics driver (LGPL-2.1-or-later) |
| `fingerprint/syn_test.c` | Drives the sensor from Linux (see [Testing](#testing)) |
| `fingerprint/build.sh` | Builds against the image's own libraries (libc, libdl, libbinder_ndk, liblog, libcrypto), `-fstack-protector-strong` |
| `usb/gbos_fp` | The built binary |

## How it starts
`usb/hook.sh` (patch) looks for a Synaptics sensor from libfprint's product list on USB at boot. Only if one is found, it adds
the `gbos_fp` service to `gbos.rc` (class hal, user system, groups system and usb, SELinux label `hal_fingerprint_default`)
with `interface aidl android.hardware.biometrics.fingerprint.IFingerprint/default`. Init refuses a second definition of the
same interface, so Google's crosfp is dropped. `FINGERPRINT=0` in `gbos.cfg` turns it off.

## What it supports
Enroll, authenticate, remove, enumerate, generate/revoke challenge, authenticator id, lockout and reset lockout. The sensor
stores and matches the templates itself; the HAL never sees fingerprint images. Up to 5 fingers per user.

## Security
- **WEAK (Class 2) sensor.** It unlocks the lock screen and apps that accept weak biometrics, but never Keystore keys: the
  match happens on a USB device the host cannot authenticate, so it must not be STRONG.
- **Enrolling and clearing a lockout need a fresh lock-screen password token** (a `HardwareAuthToken` HMAC-signed by
  gbOS86's software Gatekeeper `soft_gk`, checked against the HAL's own challenge).
- **Only system_server (uid 1000)** may call it.
- **Lockout:** 30 s after every 5 failures, permanent (password needed) after 20; kept across reboots in
  `/data/vendor/crosfp/gbos_fp/`.
- **Per install and per user:** templates are named `GBOS-<install>-u<user>-<id>`. Only the current install's and user's
  own templates are offered to the sensor or deleted. Fedora's fingerprints (fprintd) on the same sensor are never touched and
  never unlock Android, and a reinstall (new `/data`) starts with none.

## Robustness
Android's Settings "touch the sensor" screen starts an enroll and cancels it at the first touch, which left the sensor stuck
at first. Now:
- a cancel the sensor does not take at once is retried, reading the pending messages in between (as libfprint does);
- a sensor that stopped answering is reset on the next open;
- an I/O error after a requested cancel is reported as CANCELED, not as an error;
- "busy" (102) cancels the old operation and starts again; "finger still resting" (213) at the start of an enroll is retried
  with a short pause.

## Accuracy
Matching runs in the sensor's firmware; the HAL does not change any threshold. During setup, a touch that adds nothing new
shows as "not recognised": lift the finger and move it slightly between touches.

## Debugging
`adb logcat -s gbos_fp` shows each sensor message ID and result code (no fingerprint data).

## Testing
From Linux with the sensor (stop fprintd first, it resets the same sensor):

| Command | What it does |
|---|---|
| `syn_test probe` | Find the sensor, read its version, initialise, power down. Touches no template |
| `syn_test cycle` | Enroll a throw-away template `GBOS-TEST-<random>`, identify it, delete it |
| `syn_test cancel` | Start an enroll and cancel it at the first touch, then check the sensor still answers |
| `syn_test suw` | Settings' whole flow: the cancel above, then a real enroll |

`tools/test_gbos_fp.sh` checks that soft_gk's token key and the sensor ID list agree across files and that hook.sh only adds
the HAL with a sensor; `SENSOR=1` also probes the real sensor through docker.

## Status
Enrollment in Settings works (3 fingers on the SSD install). Unlocking the lock screen with a fingerprint is not checked yet.
