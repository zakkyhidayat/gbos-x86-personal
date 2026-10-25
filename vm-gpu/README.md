# GPU-accelerated Googlebook VM (work in progress)

Goal: run the VM (`tools/run_vm.sh`) with Venus (Vulkan over virtio-gpu) so the host's Intel GPU does the drawing, instead of
SwiftShader on the CPU. Googlebook draws everything through Vulkan (ANGLE for GLES, SurfaceFlinger's Vulkan RenderEngine, one
driver `vulkan.intel.so`), so one guest driver should accelerate all of it. Bare metal is never touched: everything here is used
only when a virtio GPU with 3D is present.

Host: Fedora has virglrenderer 1.3 (Venus) and QEMU 11.1 (`virtio-vga-gl,venus=on,blob=on,hostmem=`), `/dev/udmabuf`.

## Layout
| File | What |
|---|---|
| `versions.sh` | Pinned Mesa 26.2.5 (matches Fedora's) and Android NDK r30, hashes from independent sources |
| `fetch.sh` | Downloads into `~/.cache/gbos-vm-gpu` and verifies the hashes |
| `Dockerfile` | Build tools only (meson, ninja, glslang...); the compiler is the NDK |
| `build_venus.sh`, `container_build.sh` | Cross-build Mesa's Venus ICD for Android x86_64 -> `vm-gpu/out/libvulkan_virtio.so` (not tracked) |

## Phases (each ends with a check; stop at the first that fails)
1. **Build** Mesa's Venus ICD (`libvulkan_virtio.so`) for Android x86_64 in the container (`build_venus.sh`, not written yet).
2. **Load**: in a VM with `virtio-vga-gl,venus=on`, does it enumerate the host GPU (`vulkaninfo` / logcat)?
3. **Draw**: swap it in for SwiftShader in `hook.sh` (VM with 3D only) and see whether SurfaceFlinger starts and draws.
4. **Buffers**: minigbm's gralloc must create buffers Venus and QEMU can share; this is the likely hard part.
5. **`run_vm.sh --gpu`**, docs, measure smoothness.
Known risk: chaitan3/gbos-vm-linux used VirGL (GL) for SurfaceFlinger rather than Venus, so phase 3-4 may need that route.

Status: **phase 1 done**: `libvulkan_virtio.so` builds (ELF x86-64, Android 34, NDK r30, 1.6 MB; needs libdrm.so, libhardware.so,
liblog.so, libnativewindow.so, libsync.so from the guest). Fixes found on the way: `:z` on the docker mounts (Fedora's SELinux),
`-Dallow-fallback-for=libdrm` (builds libdrm from Mesa's wrap, hash-pinned by Mesa), libdrm's GPU backends off.
Not yet checked: that it loads in the guest at all (phase 2), and the hw-module entry point Android's loader uses.
