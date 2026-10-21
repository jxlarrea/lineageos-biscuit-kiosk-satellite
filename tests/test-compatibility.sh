#!/usr/bin/env bash
# Guard the CM14.1 Biscuit full/minimal layout and staged payload contract.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FULL_PATCH_DIR="$ROOT/patches/full"
MINIMAL_PATCH_DIR="$ROOT/patches/minimal"
KERNEL_PATCH_DIR="$ROOT/patches/kernel"
STAGE="$ROOT/scripts/stage-tree.sh"
BUILD="$ROOT/scripts/build.sh"
EXTRACTOR="$ROOT/scripts/extract-fireos6-blobs.sh"
DEVICE="$ROOT/device/amazon/biscuit"
VENDOR="$ROOT/vendor/amazon/mt8163-common"
WORKSPACE="${BISCUIT_WORKSPACE:-$ROOT/workspace}/cm14.1"

[[ -d "$DEVICE" ]]
[[ -d "$VENDOR" ]]
[[ ! -e "$ROOT/cm14.1" ]]
[[ "$(find "$FULL_PATCH_DIR" -maxdepth 1 -name '*.patch' | wc -l)" == 37 ]]
[[ "$(find "$MINIMAL_PATCH_DIR" -maxdepth 1 -name '*.patch' | wc -l)" == 7 ]]
[[ "$(find "$KERNEL_PATCH_DIR" -maxdepth 1 -name '*.patch' | wc -l)" == 3 ]]

printf '%s\n' "$FULL_PATCH_DIR"/*.patch | sed 's#.*/##' | diff -u - <(cat <<'EOF'
001-amonet-fstab.patch
002-amonet2-bcb-slotselect.patch
003-skip-unused-ota-images.patch
004-amazon-log-shim.patch
005-audio-legacy-symbols.patch
006-headless-system-props.patch
007-headless-no-gpu-property.patch
008-mt8163-wifi-interface-property.patch
009-bluetooth-board-cflags.patch
010-biscuit-bluetooth-noinput-pairing.patch
011-biscuit-bluetooth-noinput-prototype.patch
012-biscuit-bluetooth-headless-speaker.patch
013-biscuit-disable-pan-profile.patch
014-insecure-adb-default-props.patch
015-biscuit-hostname-mdns.patch
016-biscuit-flac-decoder.patch
017-software-egl-fallback.patch
018-hwui-egl-config-fallback.patch
019-headless-hwui-disable.patch
020-headless-hwc1-fake-display.patch
021-biscuit-radio-launchers.patch
022-biscuit-sta-only-wifi.patch
023-biscuit-mic-mute.patch
024-biscuit-disable-framework-p2p.patch
025-amazon-audio-wrapper.patch
026-biscuit-audio-route-wrapper.patch
027-biscuit-audio-route-forwarding.patch
028-biscuit-audio-gpio-mic-mute.patch
029-biscuit-zram-lzo.patch
030-biscuit-action-button-broadcast.patch
031-biscuit-speaker-amp-after-codec.patch
032-headless-framebuffer-surface-usage.patch
033-biscuit-wifi-power-save-off.patch
034-biscuit-drop-asp-pipeline-log.patch
035-biscuit-speaker-highpass-limiter.patch
036-biscuit-mic-array-speaker-null.patch
037-biscuit-volume-button-claim.patch
EOF
)

printf '%s\n' "$MINIMAL_PATCH_DIR"/*.patch | sed 's#.*/##' | diff -u - <(cat <<'EOF'
001-amonet2-bcb-slotselect.patch
002-skip-unused-ota-images.patch
003-insecure-adb-default-props.patch
004-sta-only-wpa-supplicant.patch
005-wpa-passphrase.patch
006-sepolicy-exfat-ntfs-types.patch
007-framework-free-systemimage-trim.patch
EOF
)

printf '%s\n' "$KERNEL_PATCH_DIR"/*.patch | sed 's#.*/##' | diff -u - <(cat <<'EOF'
010-netfilter-xt-compat-percpu.patch
020-force-ramdisk-root.patch
030-filter-bootloader-cmdline.patch
EOF
)

grep -Fqx 'PATCH_PROFILE="${PATCH_PROFILE:-full}"' "$STAGE"
grep -Fqx 'PROFILE_PATCH_DIR="$REPO_ROOT/patches/$PATCH_PROFILE"' "$STAGE"
grep -Fq 'PATCH_REVERSE_ONLY=1 "$REPO_ROOT/scripts/apply-patches.sh" "$CM14" 1 "$dir"' "$STAGE"
grep -Fq 'PATCH_REAPPLY=1 PATCH_STATE_DIR="$PATCH_STATE_DIR" \' "$STAGE"
python3 - "$STAGE" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index('switch_patch_profile_if_needed()')
end = text.index('\nmkdir -p "$(dirname "$ARCHIVE")"', start)
switch = text[start:end]
assert 'reset_profile_patch_outputs()' in text
assert 'patches/full/*.patch' in text
assert 'patches/minimal/*.patch' in text
assert switch.index('PATCH_REVERSE_ONLY=1') < switch.index('reset_profile_patch_outputs')
assert 'reset_generated_full_patch_outputs' not in text
assert 'reset_generated_minimal_patch_outputs' not in text
PY
grep -Fq '"$REPO_ROOT/scripts/apply-patches.sh" "$CM14" 1 "$PROFILE_PATCH_DIR"' "$STAGE"
grep -Fq 'TARGET_BISCUIT_MINIMAL' "$MINIMAL_PATCH_DIR/007-framework-free-systemimage-trim.patch"
grep -Fqx '"$REPO_ROOT/scripts/apply-patches.sh" "$KERNEL_DEST" 4 "$REPO_ROOT/patches/kernel"' "$STAGE"
grep -Fqx 'LUNCH_TARGET="${LUNCH_TARGET:-cm_biscuit-userdebug}"' "$BUILD"
grep -Fqx '  biscuit_minimal-userdebug)' "$BUILD"
grep -Fqx 'PATCH_PROFILE="$PATCH_PROFILE" "$REPO_ROOT/scripts/stage-tree.sh"' "$BUILD"
grep -Fqx 'CM14="${CM14:-$WORKSPACE_DIR/cm14.1}"' "$STAGE"
grep -Fqx 'CM14="${CM14:-$WORKSPACE_DIR/cm14.1}"' "$BUILD"
if [[ -f "$WORKSPACE/system/core/liblog/logger_write.c" ]]; then
  count="$(grep -c 'LIBLOG_ABI_PUBLIC int lab126_log_write' "$WORKSPACE/system/core/liblog/logger_write.c" || true)"
  [[ "$count" == 0 || "$count" == 1 ]]
fi

grep -Fqx 'TARGET_RELEASETOOLS_EXTENSIONS := $(LOCAL_PATH)' "$DEVICE/BoardConfig.mk"
grep -Fqx 'TARGET_FORCE_INSECURE_ADB := true' "$DEVICE/BoardConfig.mk"
grep -Fqx 'BOARD_BLUETOOTH_BDROID_CFLAGS += -DBTM_LOCAL_IO_CAPS=BTM_IO_CAP_NONE' "$DEVICE/BoardConfig.mk"
grep -Fqx '    BiscuitEmptyLauncher' "$DEVICE/device.mk"
grep -Fqx '    BiscuitService' "$DEVICE/device.mk"
grep -Fqx '    biscuit_service \' "$DEVICE/device.mk"
grep -Fqx '    biscuit-ledd \' "$DEVICE/device.mk"
grep -Fqx '    biscuit-ledctl \' "$DEVICE/device.mk"
grep -Fqx '    biscuit-pryond \' "$DEVICE/device.mk"
grep -Fqx '    ro.biscuit.pryon=1' "$DEVICE/device.mk"
grep -Fqx '    i2c-poke \' "$DEVICE/device.mk"
grep -Fqx '    audio_effects.conf \' "$DEVICE/device.mk"
grep -Fqx '    libstagefright_soft_flacdec \' "$DEVICE/device.mk"
grep -Fqx '    sensors.mt8163 \' "$DEVICE/device.mk"
grep -Fqx '    biscuit_audiotrack_test \' "$DEVICE/device.mk"
grep -Fqx '    biscuit_audiorecord_test \' "$DEVICE/device.mk"
grep -Fqx '    biscuit_asp_beam_probe \' "$DEVICE/device.mk"
grep -Fqx '    biscuit_mic_test \' "$DEVICE/device.mk"
grep -Fqx '    tinymix \' "$DEVICE/device.mk"
grep -Fqx '    tinyplay \' "$DEVICE/device.mk"
grep -Fqx '    tinycap \' "$DEVICE/device.mk"
grep -Fqx '    tinypcminfo' "$DEVICE/device.mk"
grep -Fqx 'PRODUCT_PACKAGES := $(filter-out $(BISCUIT_NO_SCREEN_PACKAGES),$(PRODUCT_PACKAGES))' "$DEVICE/device.mk"

grep -Fqx '    chown root audio /sys/devices/soc/1000b000.pinctrl/mt_gpio' "$DEVICE/rootdir/init.device.rc"
grep -Fqx '    chmod 0664 /sys/devices/soc/1000b000.pinctrl/mt_gpio' "$DEVICE/rootdir/init.device.rc"
grep -Fqx 'service biscuit-pryond /system/bin/biscuit-pryond' "$DEVICE/rootdir/init.device.rc"
grep -Fqx '    socket biscuit-pryon stream 0666 system system' "$DEVICE/rootdir/init.device.rc"
grep -Fqx '# ponytail: CM14 Biscuit uses STA only; P2P-only fields make STA-only wpa_supplicant abort.' "$DEVICE/wpa_supplicant_overlay.conf"
! grep -Fq 'p2p_no_group_iface' "$DEVICE/wpa_supplicant_overlay.conf"

grep -Fqx 'lib/hw/hwcomposer.mt8163.so:lib/hw/hwcomposer.mt8163.so:ec66527090a97538914a5d883cf5b43013aea69905f29c9e4af490eb8a48e79a:13568' "$VENDOR/biscuit-headless-hwc-files.txt"
grep -Fqx 'system/vendor/bin/wmt_loader:vendor/bin/wmt_loader:de9ee285a09a7db5b079233f7c9129c5484ecb6701b54da45e2a29f310e74ff9:17992' "$VENDOR/biscuit-radio-files.txt"
grep -Fqx 'system/vendor/bin/wmt_launcher:vendor/bin/wmt_launcher:1f34425d727ea64524c9edaeac5e6b295df7a6054703dcc79b164021560252e5:31448' "$VENDOR/biscuit-radio-files.txt"
grep -Fqx 'system/vendor/lib/libbt-vendor.so:vendor/lib/libbt-vendor.so:aab202280e09941a812983c7b7fb259fcb48bf43912f05f8cf7e47e32380ec87:13844' "$VENDOR/biscuit-bluetooth-files.txt"
grep -Fqx 'system/vendor/lib/libbluetooth_mtk.so:vendor/lib/libbluetooth_mtk.so:12e24abe8fcaaf9423fa143e432165b6877fab88222d8de55305bfeb364bdaa0:30268' "$VENDOR/biscuit-bluetooth-files.txt"
grep -Fqx 'MANIFEST="$REPO_ROOT/vendor/amazon/mt8163-common/fireos6-audio-files.txt"' "$EXTRACTOR"
grep -Fqx 'HWC_MANIFEST="$REPO_ROOT/vendor/amazon/mt8163-common/biscuit-headless-hwc-files.txt"' "$EXTRACTOR"
grep -Fqx 'RADIO_MANIFEST="$REPO_ROOT/vendor/amazon/mt8163-common/biscuit-radio-files.txt"' "$EXTRACTOR"
grep -Fqx 'BT_MANIFEST="$REPO_ROOT/vendor/amazon/mt8163-common/biscuit-bluetooth-files.txt"' "$EXTRACTOR"
grep -Fqx 'PRYON_MANIFEST="$REPO_ROOT/vendor/amazon/mt8163-common/biscuit-pryon-files.txt"' "$EXTRACTOR"
[[ "$(grep -vc '^#' "$VENDOR/biscuit-pryon-files.txt")" == 28 ]]
grep -Fq ':lib/libtvm_modelops_ww_v5_cnet.so:' "$VENDOR/biscuit-pryon-files.txt"
grep -Fq ':etc/pryon/alexa-en-US/pryon.manifest:' "$VENDOR/biscuit-pryon-files.txt"
grep -Fqx 'DAVS_MANIFEST="$REPO_ROOT/vendor/amazon/mt8163-common/biscuit-davs-model-files.txt"' "$EXTRACTOR"
grep -Fqx 'DAVS_DIR="${DAVS_MODELS:-$REPO_ROOT/../amazon-davs-models}"' "$EXTRACTOR"
grep -Fqx 'en-US alexa-en-US echo-en-US computer-en-US' "$DEVICE/pryon/locales.txt"
grep -Fq 'device/amazon/biscuit/pryon/locales.txt:$(TARGET_COPY_OUT_SYSTEM)/etc/pryon/locales.txt' "$DEVICE/device.mk"
# Every set locales.txt names is in the DAVS manifest, but the firmware's Alexa.
for set in $(grep -v '^#' "$DEVICE/pryon/locales.txt" | cut -d' ' -f2- | tr ' ' '\n' | sort -u); do
  [[ "$set" == alexa-en-US ]] || grep -q "^$set/pryon.manifest:" "$VENDOR/biscuit-davs-model-files.txt"
done
grep -Fqx 'system/lib/libpryon.so:lib/pryon/libpryon.so:920dc04d2253706a1c20b14477a3460bdc36d7ee84b3fb27a55cdf5823189748:10388280' "$VENDOR/biscuit-pryon-files.txt"
grep -Fq 'thresholds["accept-threshold"] = 0.18' "$EXTRACTOR"
grep -Fqx 'MINIMAL_VENDOR_MK_TMP="$TMP/mt8163-common-minimal-vendor.mk"' "$EXTRACTOR"
grep -Fq 'Fire OS 6.5.7.4 MT8163 radio/Wi-Fi closure for framework-free Biscuit minimal.' "$EXTRACTOR"

bash "$ROOT/tests/test-minimal-product.sh"

echo 'PASS CM14 Biscuit full/minimal layout and payload contract'
