# gbos-x13g2

My own additions for running [gbOS86](https://github.com/linuxkid473/gbos-x86) on a ThinkPad X13 Gen 2i (20WL). Personal use.
This repo holds only my files; gbos-x86 itself is not copied here. `apply.sh` puts them onto a gbos-x86 checkout.

| What | Files |
|---|---|
| Lenovo identity: Settings shows "ThinkPad X13 Gen 2i", brand LENOVO, in every partition's build.prop, whatever name Google's build uses (fingerprint stays Google's) | `patches/gbos-x86-changes.patch` (`usb/hook.sh`, `usb/gbos.cfg`) |
| Fingerprint HAL for the Synaptics match-on-chip sensor (06cb:00f9): AIDL V4 IFingerprint, WEAK, enrolling needs the lock-screen password | `fingerprint/` (source; `syn.h` ports libfprint's driver, LGPL-2.1), `usb/gbos_fp` (binary) |
| adb over a Thunderbolt cable: `thunderbolt_net` built for gbOS86's kernel, this side 10.42.0.2/24 | `usb/kmod/thunderbolt_net.ko`, `usb/tbnet.sh`, `kernel/isa_emu_patch/build_extra_module.sh`, `kernel/symvers_from_modules.py` |
| Tests | `tools/test_gbos_fp.sh`, `tools/test_tbnet.sh`, identity checks in the patch's `tools/test_device_model.sh` |

The patch also adds `gbos_fp` and `tbnet.sh` to gbos-x86's image and deploy scripts, documents the options in `gbos.cfg`
(`FINGERPRINT=0`, `TB_NET=0`, `TB_NET_IP`), and notes them in its README.

## Use

```sh
git clone https://github.com/linuxkid473/gbos-x86
./apply.sh ../gbos-x86
cd ../gbos-x86 && sh tools/test_gbos_fp.sh && sh tools/test_tbnet.sh && sh tools/test_device_model.sh
./build.sh --looper --data-size 100
```

After a newer gbos-x86: apply again on a fresh checkout. If `test_tbnet.sh` fails on vermagic or CRCs, upstream shipped a new
kernel: rebuild the module (`kernel/isa_emu_patch/build_extra_module.sh USB4_NET drivers/net/thunderbolt thunderbolt_net`,
see its header) and the fingerprint HAL if needed (`fingerprint/build.sh`).
