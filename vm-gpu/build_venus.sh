#!/bin/sh
# Build Mesa's Venus Vulkan ICD (libvulkan_virtio.so) for Android x86_64 with the pinned NDK, in the gbos-vmgpu container
# (docker build -t gbos-vmgpu vm-gpu; sh vm-gpu/fetch.sh first). Result: vm-gpu/out/libvulkan_virtio.so
#   sh vm-gpu/build_venus.sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/versions.sh"
[ -d "$CACHE/mesa-$MESA_VERSION" ] && [ -d "$CACHE/android-ndk-$NDK_VERSION" ] || { echo "run vm-gpu/fetch.sh first"; exit 1; }
export NDK_VERSION ANDROID_API MESA_VERSION
mkdir -p "$HERE/out" "$CACHE/build-venus"
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e NDK_VERSION -e ANDROID_API -e MESA_VERSION -v "$CACHE:/cache:z" -v "$HERE:/vmgpu:z" gbos-vmgpu sh /vmgpu/container_build.sh > "$CACHE/build-venus/build.log" 2>&1 && echo "built: $(ls -la $HERE/out/libvulkan_virtio.so)" || { echo "build failed; last lines of $CACHE/build-venus/build.log:"; tail -25 "$CACHE/build-venus/build.log"; exit 1; }
