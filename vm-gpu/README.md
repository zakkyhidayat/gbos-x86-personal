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
| `test_boot.sh` | One test round: throwaway disk from the internal install + Venus driver + QEMU headless, prints a short error summary (`sh vm-gpu/test_boot.sh [seconds]`, `KEEP=1` keeps logs and screenshot) |
| `build_venus.sh`, `container_build.sh` | Cross-build Mesa's Venus ICD for Android x86_64 -> `vm-gpu/out/libvulkan_virtio.so` (not tracked) |

## Phases (each ends with a check; stop at the first that fails)
1. **Build** Mesa's Venus ICD (`libvulkan_virtio.so`) for Android x86_64 in the container (`build_venus.sh`, not written yet).
2. **Load**: in a VM with `virtio-vga-gl,venus=on`, does it enumerate the host GPU (`vulkaninfo` / logcat)?
3. **Draw**: swap it in for SwiftShader in `hook.sh` (VM with 3D only) and see whether SurfaceFlinger starts and draws.
4. **Buffers**: minigbm's gralloc must create buffers Venus and QEMU can share; this is the likely hard part.
5. **`run_vm.sh --gpu`**, docs, measure smoothness.
Known risk: chaitan3/gbos-vm-linux used VirGL (GL) for SurfaceFlinger rather than Venus, so phase 3-4 may need that route.

Status: **phases 1-2 done, phase 3-4 blocked on buffer sharing.**
- Phase 1: `libvulkan_virtio.so` builds (ELF x86-64, Android 34, NDK r30, 1.6 MB; `HMI` symbol present).
- Phase 2 (tested in QEMU `virtio-vga-gl,blob=on,venus=on,hostmem=2G -display egl-headless` + memfd memory backend, test image
  from the internal install's files): `hook.sh` bound it over `vulkan.intel.so`, and the host's `virgl_render_server` created
  Venus contexts for bootanimation and surfaceflinger: the driver loads and talks to the host GPU.
- Phase 3-4 fails: every frame, `vk_common_GetAndroidHardwareBufferPropertiesANDROID` -> `vn_get_memory_dma_buf_properties` ->
  host `vkGetMemoryResourcePropertiesMESA: invalid res_id`, then `vkCreateDevice` fails in SurfaceFlinger ("failed to do deferred
  gralloc buffer bind", 17k times). Android's gralloc (minigbm) hands Venus dma-bufs that are plain virtio-gpu 2D/dumb resources;
  Venus can only import blob resources the host knows. The screen stays "Display output is not active".
- Way forward (not done): make minigbm allocate blob resources (its virtio-gpu cross-domain path), which is Google's prebuilt
  binary, or take chaitan3/gbos-vm-linux's route (VirGL GL for SurfaceFlinger + Venus for apps, with its Mesa gralloc patch).
  Either is a patch-the-guest-graphics-stack project, not a driver swap.
- Tried: chaitan3's `mesa-android-mapper5.patch` (u_gralloc reads buffer info through IMapper 5; fetched by `fetch.sh`, hash-pinned, applied
  by `container_build.sh`). Same result: `invalid res_id`, SurfaceFlinger `vkCreateDevice` fails, "Display output is not active".
  So the problem is not Mesa's buffer-info lookup but that minigbm's buffers are not blob resources the host can import.
- Next experiment (not done): find out how minigbm allocates here (logcat of the gralloc HAL, `virtgpu` ioctls) and whether it can be
  told to use blob resources; or test chaitan3's VirGL-for-SurfaceFlinger split.
The `venus` choice in `hook.sh` stays: it only triggers with a virgl-capable virtio GPU and `gbos/patched/vulkan.venus.so`, which
is not shipped, so nothing changes until the buffer problem is solved.
