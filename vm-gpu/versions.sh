# Pinned inputs of the GPU-accelerated VM build (sourced by fetch.sh and build_venus.sh). Each hash comes from an independent
# source, not from the download server: Mesa's from its release notes (docs.mesa3d.org/relnotes/26.2.5.html), the NDK's from
# Google's SDK repository manifest (dl.google.com/android/repository/repository2-3.xml).
#
# Mesa matches Fedora's own (mesa 26.2.5, virglrenderer 1.3), so the guest's Venus driver and the host's Venus renderer speak
# the same protocol version.
MESA_VERSION=26.2.5
MESA_URL=https://archive.mesa3d.org/mesa-$MESA_VERSION.tar.xz
MESA_SHA256=794b3d1729075dae7ebd47c7283b7ca0cdb5dec668f7f11cc0a5d82f6138a0a5

NDK_VERSION=r30
NDK_URL=https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-linux.zip
NDK_SIZE=738633529
NDK_SHA1=5107f898313790e449e87eee2183d9a20602dee9

# Android API the driver is built against: lapis is Android 17; 34 is old enough for every libc/NDK symbol used and new
# enough for AHardwareBuffer and the gralloc paths Mesa's Android WSI takes.
ANDROID_API=34

# Downloads and build trees (outside the repo: ~3 GB)
CACHE=${GBOS_GPU_CACHE:-$HOME/.cache/gbos-vm-gpu}
