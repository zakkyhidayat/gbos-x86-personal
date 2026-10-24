# Googlebook VM

`tools/run_vm.sh` boots the installed Googlebook under QEMU/KVM from Fedora, for testing apps. It is a **throwaway
snapshot**: what is booted is only ever read, everything the VM writes (data, settings, logs) goes to temporary qcow2
overlays in `/var/tmp/gbos-vm.*`, deleted when the VM exits. The next real boot sees exactly what was there before.

```sh
sh ~/Documents/gbos-x86/tools/run_vm.sh            # the external SSD if plugged in, else the internal install
sh ~/Documents/gbos-x86/tools/run_vm.sh --internal # the internal install even with the SSD plugged in
adb connect 127.0.0.1:5556                         # then approve the prompt in the VM (approval is not kept)
adb -s 127.0.0.1:5556 install app.apk
```

| Source | What the VM gets | Boots through |
|---|---|---|
| External SSD | The whole drive (must carry all four GBOS labels; never the disk Linux runs from) | OVMF from the drive's EFI partition |
| Internal install | **Only** `GBOSSYS`, `GBOS_META`, `GBOS_DATA`, as three disks; Linux's own partitions are never passed | The kernel given directly (`usb/out/BOOTX64.EFI`, identical to `EFI/gbos/BOOTX64.EFI`) with the same quiet options |
| `--disk IMG`, `--parts SYS META DATA` | Image files (for testing the script) | as above |

- `sudo` is only used to give this user **read** access to the drive or partitions (`setfacl`), removed on exit. QEMU runs as
  the user. Partitions mounted in Fedora are unmounted first.
- Defaults: 6 GB RAM, 4 CPUs (`MEM=`, `CPUS=`), user-mode network (Android sees Ethernet), adb forwarded to `127.0.0.1:5556`.

## Using it
- **Mouse:** click into the window to capture it, **Ctrl+Alt+G** to release. It is a plain USB mouse: Android ignores QEMU's
  `usb-tablet` (an absolute pointer). The SDL window locks the desktop's pointer while captured; QEMU's GTK window does not on
  Wayland (`VM_DISPLAY=gtk` for its menus anyway).
- **Graphics** are drawn on the CPU (SwiftShader): fine for apps, not smooth.
- **Not in the VM:** fingerprint, Wi-Fi (Ethernet instead), Bluetooth ("keeps stopping" is expected), real sound.
- The `Gtk-WARNING … gtk.css` lines in the terminal are harmless: Fedora's QEMU loads its GTK module even for SDL.

## How it was made to work
Out of the box, Android's SurfaceFlinger crashed in a VM: gbOS86's kernel has no virtual GPU driver, only `simpledrm`.
- **virtio-gpu driver:** `usb/kmod/virtio-gpu.ko` and `virtio_dma_buf.ko`, built for the shipped kernel
  ([kernel-modules.md](kernel-modules.md)). `hook.sh` loads them only when a virtio GPU (PCI `1af4:1050`) exists, which is
  never the case on the laptop itself.
- **Rendering:** Google's minigbm already has a `virtio_gpu` backend, so gbOS86's software-rendering path (SwiftShader
  Vulkan, minigbm gralloc and libgbm with that backend) turns on by itself once the driver is bound.
- **Colours:** virtio-gpu creates every "dumb" buffer as XRGB8888 (bytes B,G,R,X), while Android fills them as RGBA
  (R,G,B,A), so red and blue were swapped. `kernel/isa_emu_patch/virtio-gpu-dumb-rgba.patch` creates them as RGBA.

## Checked
- External SSD: boots to the desktop with the real account and apps; colours and mouse right.
- `--parts` (the same path as `--internal`) with three images built from the drive's files: boots to Android's setup;
  the base images had the same md5 before and after a session that wrote 457 MB; the overlays were removed.
- `--internal` on the real partitions: not run yet.

## Faster graphics (not done)
GPU acceleration through the host's Intel GPU would use VirGL (OpenGL ES) and Venus (Vulkan) over `virtio-gpu-gl`, with guest
Mesa drivers built for Android, as [chaitan3/gbos-vm-linux](https://github.com/chaitan3/gbos-vm-linux) does for Google's
recovery image. Passing the Intel GPU itself to the VM is not possible on this laptop: it is the only GPU (Fedora's screen
would go dark), GVT-g ended with 10th generation and SR-IOV is official from 12th (this is 11th, Tiger Lake).
