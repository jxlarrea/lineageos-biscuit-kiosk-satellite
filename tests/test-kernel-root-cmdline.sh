#!/usr/bin/env bash
# Verify the permanent Fire OS root dm-0 bypass and headless root ADB contract.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/patches/kernel/020-force-ramdisk-root.patch"
CMDLINE_FILTER_PATCH="$ROOT/patches/kernel/030-filter-bootloader-cmdline.patch"
ADB_PATCH="$ROOT/patches/full/014-insecure-adb-default-props.patch"
MINIMAL_ADB_PATCH="$ROOT/patches/minimal/003-insecure-adb-default-props.patch"
STAGE="$ROOT/scripts/stage-tree.sh"
BOARD="$ROOT/device/amazon/biscuit/BoardConfig.mk"

for line in \
  '+CONFIG_CMDLINE="console=tty0 console=ttyMT0,921600n1 root=/dev/ram rdinit=/init vmalloc=496M slub_max_order=0 slub_debug=O loglevel=4 gpt bootopt=64S3,32N2,32N2 androidboot.hardware=mt8163 androidboot.selinux=permissive buildvariant=userdebug"' \
  '+# CONFIG_CMDLINE_FROM_BOOTLOADER is not set' \
  '+CONFIG_CMDLINE_FORCE=y'; do
  grep -Fqx "$line" "$PATCH"
done

! grep -q 'androidboot.slot_suffix' "$PATCH"
! grep -q '^[-+]CONFIG_DM_\|^[-+]# CONFIG_DM_' "$PATCH"
grep -Fqx '"$REPO_ROOT/scripts/apply-patches.sh" "$KERNEL_DEST" 4 "$REPO_ROOT/patches/kernel"' "$STAGE"
[[ "$(find "$ROOT/patches/kernel" -maxdepth 1 -name '*.patch' | wc -l)" == 3 ]]

for allowed in '"androidboot.serialno="' '"androidboot.bootreason="' '"boot_reason="'; do
  grep -Fq "$allowed" "$CMDLINE_FILTER_PATCH"
done
for forbidden in '"root=' '"dm=' '"androidboot.slot_suffix='; do
  ! grep -Fq "$forbidden" "$CMDLINE_FILTER_PATCH"
done
grep -Fq 'CONFIG_CMDLINE_FORCE' "$PATCH"
grep -Fq 'drivers/of/fdt.c' "$CMDLINE_FILTER_PATCH"
grep -Fq 'biscuit_append_safe_fdt_bootargs(cmdline, biscuit_bootargs)' "$CMDLINE_FILTER_PATCH"
! grep -Fq 'atags_parse.c' "$CMDLINE_FILTER_PATCH"

grep -Fqx 'PATCH_PROFILE="${PATCH_PROFILE:-full}"' "$STAGE"
grep -Fqx 'PROFILE_PATCH_DIR="$REPO_ROOT/patches/$PATCH_PROFILE"' "$STAGE"
grep -Fq 'PATCH_REAPPLY=1 PATCH_STATE_DIR="$PATCH_STATE_DIR" \' "$STAGE"
grep -Fq '"$REPO_ROOT/scripts/apply-patches.sh" "$CM14" 1 "$PROFILE_PATCH_DIR"' "$STAGE"
grep -Fqx 'TARGET_FORCE_INSECURE_ADB := true' "$BOARD"
for patch in "$ADB_PATCH" "$MINIMAL_ADB_PATCH"; do
  for line in \
    '+ifeq ($(TARGET_FORCE_INSECURE_ADB),true)' \
    '+ADDITIONAL_DEFAULT_PROPERTIES := $(filter-out ro.adb.secure=% ro.secure=% cm.service.adb.root=%,$(ADDITIONAL_DEFAULT_PROPERTIES))' \
    '+    ro.adb.secure=0 \' \
    '+    ro.secure=0 \' \
    '+    cm.service.adb.root=1'; do
    grep -Fqx "$line" "$patch"
  done
done

echo 'PASS CM14 persistent ramdisk-root and root-ADB contract'
