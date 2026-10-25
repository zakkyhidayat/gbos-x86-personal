# Build container for Mesa's Venus Vulkan driver for Android x86_64 (vm-gpu/build_venus.sh). Only host tools: the compiler is
# the Android NDK from the cache (vm-gpu/fetch.sh), mounted in at run time.
#   docker build -t gbos-vmgpu vm-gpu
FROM debian:trixie
RUN apt-get update && apt-get install -y --no-install-recommends \
      meson ninja-build python3 python3-mako python3-yaml python3-packaging python3-ply \
      bison flex pkg-config glslang-tools ca-certificates curl git xz-utils unzip file binutils \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
