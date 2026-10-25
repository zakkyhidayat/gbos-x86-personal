#!/bin/sh
# Runs inside the gbos-vmgpu container (called by build_venus.sh): cross-builds Mesa's Venus ICD for Android x86_64.
set -e
NDK=/cache/android-ndk-$NDK_VERSION/toolchains/llvm/prebuilt/linux-x86_64
T=x86_64-linux-android$ANDROID_API
B=/cache/build-venus
cat > $B/android-x86_64.ini <<INI
[binaries]
c = '$NDK/bin/$T-clang'
cpp = '$NDK/bin/$T-clang++'
ar = '$NDK/bin/llvm-ar'
strip = '$NDK/bin/llvm-strip'
pkg-config = 'false'
[host_machine]
system = 'android'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
[properties]
needs_exe_wrapper = true
INI
cd /cache/mesa-$MESA_VERSION
rm -rf $B/b
meson setup $B/b -Dallow-fallback-for=libdrm -Dlibdrm:intel=disabled -Dlibdrm:radeon=disabled -Dlibdrm:amdgpu=disabled -Dlibdrm:nouveau=disabled -Dlibdrm:vmwgfx=disabled -Dlibdrm:freedreno=disabled -Dlibdrm:etnaviv=disabled -Dlibdrm:exynos=disabled -Dlibdrm:omap=disabled -Dlibdrm:tegra=disabled -Dlibdrm:vc4=disabled -Dlibdrm:cairo-tests=disabled -Dlibdrm:valgrind=disabled -Dlibdrm:tests=false --cross-file $B/android-x86_64.ini --buildtype=release -Dstrip=true \
  -Dplatforms=android -Dplatform-sdk-version=$ANDROID_API -Dandroid-stub=true -Dandroid-libbacktrace=disabled \
  -Dvulkan-drivers=virtio -Dgallium-drivers= -Dvulkan-layers= -Dllvm=disabled \
  -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dgles1=disabled -Dgles2=disabled -Dopengl=false \
  -Dbuild-tests=false -Dtools= -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dzstd=disabled -Dxmlconfig=disabled
ninja -C $B/b
find $B/b -name libvulkan_virtio.so -exec cp {} /vmgpu/out/ \;
