#!/bin/sh
# Build gbos_fp like soft_gk (gatekeeper/build.sh): Android clang, no NDK, linked against the image's own
# libraries in libs/ (system/lib64: libbinder_ndk, libcrypto, liblog; libc, libdl from the runtime APEX).
# The compiler defaults to the gbos-kbuild toolchain; any clang + ld.lld works: CC=clang LD=ld.lld ./build.sh
# Also builds syn_test, the host-side sensor test (tools/test_gbos_fp.sh), with the host's cc.
set -e
C=/build/inputs/clang-r584948c
CC=${CC:-$C/bin/clang-22}
LD=${LD:-$C/bin/ld.lld}
READELF=${READELF:-$C/bin/llvm-readelf}
HOSTCC=${HOSTCC:-cc}
cd "$(dirname "$0")"
$CC --target=x86_64-linux-android36 -O2 -fPIE -fstack-protector-strong -ffreestanding \
  -fvisibility=hidden -Wall -Wextra -Werror -c gbos_fp.c -o gbos_fp.o
$LD -pie --dynamic-linker=/system/bin/linker64 -z noexecstack -z now -z relro --hash-style=gnu \
  --no-undefined -e _start -o gbos_fp gbos_fp.o -Llibs -lc -lbinder_ndk -llog -lcrypto -ldl
$READELF -d gbos_fp | grep -E 'NEEDED|FLAGS'
cp gbos_fp ../usb/gbos_fp
$HOSTCC -O2 -Wall -Wextra -Werror -o syn_test syn_test.c
