# Extra kernel modules

gbOS86 ships a prebuilt kernel (`usb/out/BOOTX64.EFI`, kernel #42 `6.18.21-gbos-whl`) and module tree (r5). Three drivers it
leaves out are built here **for that exact kernel, without rebuilding it**:

| Module | Config | For | Loaded by `hook.sh` when |
|---|---|---|---|
| `thunderbolt_net.ko` | `USB4_NET` | adb over a Thunderbolt cable ([adb.md](adb.md)) | the `thunderbolt` driver is loaded and `TB_NET` is not 0 |
| `virtio_dma_buf.ko` | `VIRTIO_DMA_SHARED_BUFFER` | needed by virtio-gpu | a virtio GPU (PCI `1af4:1050`) exists: only in a VM |
| `virtio-gpu.ko` | `DRM_VIRTIO_GPU` | Android's display in the VM ([vm.md](vm.md)) | the same |

They are not signed: gbOS86's kernel does not enforce module signatures (`MODULE_SIG_FORCE` off), so they load and taint the
kernel like any out-of-tree module.

## Matching the shipped kernel exactly
A module only loads if it matches the running kernel. `kernel/isa_emu_patch/build_extra_module.sh` guesses nothing:

| Must match | Taken from |
|---|---|
| Config | The shipped kernel's own, read from the `IKCONFIG` inside `BOOTX64.EFI` (lz4 payload), plus `CONFIG_<SYM>=m` |
| Compiler | The same AOSP clang (r584948b), so kCFI type hashes and the mitigation thunks agree |
| Version magic | The shipped module tree's release (`6.18.21-gbos-whl`), checked against the result |
| Symbol CRCs (`MODVERSIONS`) | Recovered from the shipped modules by `kernel/symvers_from_modules.py` (each module's `__versions` table lists the CRC of every symbol it imports) |

**Symbols no shipped module imports** have no CRC to recover. `EXTRA_CRC_OBJS` names the kernel objects that export them; the
script compiles just those objects with the same config and compiler and takes genksyms' `#SYMVER name crc` lines from their
`.cmd` files. It refuses if any CRC already known from the shipped modules differs. For virtio-gpu, 160 CRCs were added this
way across 15 objects, and the 152 already known for those objects all matched.

`PATCH` applies a patch to the copied source (with `git apply`; the container has no `patch`). `EXTRA_SYMBOLS` passes the
`Module.symvers` of a module built earlier (virtio-gpu imports from virtio_dma_buf).

## Commands
In gbos-x86's build container (`gbos-kbuild`, with the kernel sources in the `gbos-ksrc` volume from
`kernel/fetch_kernel_sources.sh`), from the gbos-x86 checkout:

```sh
B="docker run --rm -v gbos-ksrc:/build -v $PWD:/repo"
S=/repo/kernel/isa_emu_patch/build_extra_module.sh
OBJS="drivers/dma-buf/dma-buf.o drivers/dma-buf/dma-fence.o drivers/dma-buf/dma-fence-array.o kernel/dma/mapping.o
  drivers/gpu/drm/drm_plane.o drivers/gpu/drm/drm_connector.o drivers/gpu/drm/drm_drv.o drivers/gpu/drm/drm_file.o
  drivers/gpu/drm/drm_fbdev_shmem.o drivers/gpu/drm/drm_gem.o drivers/gpu/drm/drm_prime.o drivers/gpu/drm/drm_gem_shmem_helper.o
  drivers/virtio/virtio.o mm/page_size_compat.o lib/strncpy_from_user.o"

$B gbos-kbuild sh $S USB4_NET drivers/net/thunderbolt thunderbolt_net
$B -e EXTRA_CRC_OBJS=drivers/dma-buf/dma-buf.o gbos-kbuild sh $S DRM_VIRTIO_GPU drivers/virtio virtio_dma_buf
$B -e "EXTRA_CRC_OBJS=$OBJS" -e PATCH=kernel/isa_emu_patch/virtio-gpu-dumb-rgba.patch \
   -e EXTRA_SYMBOLS=/build/extmod/virtio_dma_buf/Module.symvers gbos-kbuild sh $S DRM_VIRTIO_GPU drivers/gpu/drm/virtio virtio-gpu
sudo chown $(id -u):$(id -g) usb/kmod/*.ko        # the container writes them as root
```
Each run ends with `EXTRA_MODULE_DONE` and prints the module's `vermagic` and dependencies; the results land in `usb/kmod/`.

## Checks
- `tools/test_tbnet.sh`: `thunderbolt_net`'s vermagic, every imported symbol's CRC and its kCFI hashes against the shipped
  kernel; and that `hook.sh` only adds the network service when the module loads.
- virtio-gpu and virtio_dma_buf: proven by booting the VM (a wrong CRC refuses to load, a wrong kCFI hash would panic on the
  first indirect call).

## Rebuilding for a new kernel
When upstream ships a new kernel (`test_tbnet.sh` fails on vermagic or CRCs): fetch its sources and module tree
(`kernel/fetch_kernel_sources.sh`), then run the three commands again. If a new symbol is missing a CRC, the build stops
with modpost's "undefined" list: find the exporting files (`grep -rn "EXPORT_SYMBOL.*(name)"` in the source) and add their
`.o` to `EXTRA_CRC_OBJS`.
