#!/usr/bin/env bash
# Launch a Biscuit CM14.1 OTA build in a detached container.
set -euo pipefail

IMAGE="cm14.1-ubuntu20:latest"
CONTAINER="cm14.1-biscuit-build"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The checkout, downloads and build output: tens of GB, so it can live
# outside the repository (BISCUIT_WORKSPACE).
WORKSPACE_DIR="${BISCUIT_WORKSPACE:-$REPO_ROOT/workspace}"
CM14="${CM14:-$WORKSPACE_DIR/cm14.1}"
OUT_DIR="$CM14/out-docker"
KERNEL_SOURCE="$CM14/kernel/amazon/biscuit"
KERNEL_SUPPORT="$CM14/device/amazon/biscuit/kernel-build-support"
KERNEL_OUT="$OUT_DIR/target/product/biscuit/obj/KERNEL_OBJ"
BUILD_TARGET="${BUILD_TARGET:-otapackage}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
CCACHE_DIR="${CCACHE_DIR:-$WORKSPACE_DIR/ccache}"
CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-50G}"
LUNCH_TARGET="${LUNCH_TARGET:-cm_biscuit-userdebug}"

case "$LUNCH_TARGET" in
  cm_biscuit-userdebug)
    PATCH_PROFILE="${PATCH_PROFILE:-full}"
    ;;
  biscuit_minimal-userdebug)
    PATCH_PROFILE="${PATCH_PROFILE:-minimal}"
    ;;
  *)
    echo "ERROR: unsupported LUNCH_TARGET '$LUNCH_TARGET'" >&2
    echo "expected cm_biscuit-userdebug or biscuit_minimal-userdebug" >&2
    exit 1
    ;;
esac

case "$PATCH_PROFILE" in
  full|minimal) ;;
  *) echo "ERROR: unsupported PATCH_PROFILE '$PATCH_PROFILE'" >&2; exit 1 ;;
esac

PATCH_PROFILE="$PATCH_PROFILE" "$REPO_ROOT/scripts/stage-tree.sh"
[[ -f "$KERNEL_SOURCE/Makefile" && \
   -f "$KERNEL_SOURCE/arch/arm/configs/biscuit_defconfig" && \
   -f "$KERNEL_SUPPORT/verity-keys" && \
   -f "$KERNEL_SUPPORT/include/generated/trapz_generated_kernel.h" ]] || {
  echo "ERROR: staged FireOS 6 kernel source/support is incomplete" >&2
  exit 1
}

if [[ "${CLEAN_BISCUIT_OUT:-0}" == 1 ]]; then
  rm -rf "$OUT_DIR/target/product/biscuit"
fi

install_if_changed() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    return 0
  fi
  install -m 0644 "$src" "$dst"
}

install_if_changed "$KERNEL_SUPPORT/verity-keys" "$KERNEL_OUT/verity-keys"
install_if_changed "$KERNEL_SUPPORT/include/generated/trapz_generated_kernel.h" \
  "$KERNEL_OUT/include/generated/trapz_generated_kernel.h"

# ponytail: incremental Android builds do not delete files removed from product manifests.
for stale in \
  cache.img \
  userdata.img \
  system/bin/6620_launcher \
  system/bin/linker64 \
  system/bin/wmt_loader \
  system/etc/firmware/ROMv2_lm_patch_1_0_hdr.bin \
  system/etc/firmware/ROMv2_lm_patch_1_1_hdr.bin \
  system/etc/firmware/WIFI_RAM_CODE_8163 \
  system/etc/biscuit-ledd/volume-muted.animation \
  system/lib64/libc.so \
  system/lib64/libcutils.so \
  system/lib64/libdl.so \
  system/lib64/liblog.so \
  system/lib64/libm.so \
  system/lib64/libstdc++.so; do
  rm -f "$OUT_DIR/target/product/biscuit/$stale"
done
rmdir "$OUT_DIR/target/product/biscuit/system/lib64" 2>/dev/null || true

if [[ "$LUNCH_TARGET" == biscuit_minimal-userdebug ]]; then
  rm -rf \
    "$OUT_DIR/target/product/biscuit/system/app" \
    "$OUT_DIR/target/product/biscuit/system/priv-app" \
    "$OUT_DIR/target/product/biscuit/system/framework" \
    "$OUT_DIR/target/product/biscuit/system/etc/biscuit-ledd" \
    "$OUT_DIR/target/product/biscuit/system/bin/biscuit-ledd" \
    "$OUT_DIR/target/product/biscuit/system/bin/biscuit-ledctl" \
    "$OUT_DIR/target/product/biscuit/system/bin/biscuit_service" \
    "$OUT_DIR/target/product/biscuit/system/bin/i2c-poke"
else
  for stale_app in \
    AudioFX \
    BasicDreams \
    Browser \
    Browser2 \
    Calculator \
    Calendar \
    Camera2 \
    CMFileManager \
    CMWallpapers \
    CMUpdater \
    CyanogenSetupWizard \
    DeskClock \
    Development \
    Eleven \
    Email \
    ExactCalculator \
    Exchange2 \
    Gallery2 \
    Jelly \
    Launcher2 \
    Launcher3 \
    LineageSetupWizard \
    LiveWallpapersPicker \
    LockClock \
    PhotoTable \
    PrintSpooler \
    SetupWizard \
    Terminal \
    ThemeChooser \
    Trebuchet \
    Updater \
    WallpaperCropper \
    WallpaperPicker; do
    rm -rf "$OUT_DIR/target/product/biscuit/system/app/$stale_app" \
           "$OUT_DIR/target/product/biscuit/system/priv-app/$stale_app"
  done
  # Amazon's wake word models, copied again from the manifests on every
  # build: a model set a manifest no longer names must not stay behind.
  rm -rf "$OUT_DIR/target/product/biscuit/system/etc/pryon"
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "ERROR: Docker image '$IMAGE' not found." >&2
  echo "Build it first:" >&2
  echo "  docker build -t $IMAGE -f $REPO_ROOT/docker/cm14.1-ubuntu20.Dockerfile $REPO_ROOT/docker/" >&2
  exit 1
fi

ln -sfn out-docker "$CM14/out"
mkdir -p "$CCACHE_DIR"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

docker run -d \
  --name "$CONTAINER" \
  -v "$REPO_ROOT:$REPO_ROOT" \
  -v "$WORKSPACE_DIR:$WORKSPACE_DIR" \
  -w "$CM14" \
  "$IMAGE" \
  bash -lc "
    set -e
    source build/envsetup.sh >/dev/null
    export OUT_DIR='$OUT_DIR'
    export USE_CCACHE=1
    export CCACHE_DIR='$CCACHE_DIR'
    prebuilts/misc/linux-x86/ccache/ccache -M '$CCACHE_MAXSIZE' >/dev/null || true
    export PATH=\"\$OUT_DIR/host/linux-x86/bin:\$PATH\"
    lunch '$LUNCH_TARGET' >/tmp/lunch.log
    make -j'$BUILD_JOBS' '$BUILD_TARGET'
  "

echo "Started $CONTAINER ($BUILD_TARGET, $LUNCH_TARGET, PATCH_PROFILE=$PATCH_PROFILE)."
echo "Monitor: docker logs -f $CONTAINER"
