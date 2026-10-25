#!/bin/sh
# Download the pinned Mesa source and Android NDK into the cache (vm-gpu/versions.sh) and verify them. Re-running only checks.
#   sh vm-gpu/fetch.sh
set -e
. "$(dirname "$0")/versions.sh"
mkdir -p "$CACHE"; cd "$CACHE"
get() {  # get FILE URL ALGO HASH
  if [ -f "$1" ] && echo "$4  $1" | "$3sum" -c --quiet - 2>/dev/null; then echo "$1: present, $3 ok"; return; fi
  echo "$1: downloading $2"
  curl -fsSL --retry 3 -o "$1.part" "$2"
  echo "$4  $1.part" | "$3sum" -c --quiet - || { echo "$1: $3 MISMATCH, removed"; rm -f "$1.part"; exit 1; }
  mv "$1.part" "$1"; echo "$1: $3 ok"
}
get mesa-$MESA_VERSION.tar.xz "$MESA_URL" sha256 "$MESA_SHA256"
get android-ndk-$NDK_VERSION-linux.zip "$NDK_URL" sha1 "$NDK_SHA1"
[ "$(stat -c %s android-ndk-$NDK_VERSION-linux.zip)" = "$NDK_SIZE" ] || { echo "NDK size differs from the manifest"; exit 1; }

[ -d mesa-$MESA_VERSION ] || { echo "unpacking Mesa"; tar xf mesa-$MESA_VERSION.tar.xz; }
[ -d android-ndk-$NDK_VERSION ] || { echo "unpacking the NDK"; unzip -q android-ndk-$NDK_VERSION-linux.zip; }
echo "ready in $CACHE"
