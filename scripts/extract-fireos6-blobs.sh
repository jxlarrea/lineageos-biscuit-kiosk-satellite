#!/usr/bin/env bash
# Stage verified Fire OS 6 audio plus the proven stock Biscuit headless HWC closure.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CM14="${CM14:-$REPO_ROOT/workspace/cm14.1}"
OTA_URL="https://d1s31zyz7dcc2d.cloudfront.net/2026/8/3/f49aaff7-dd63-4d9c-9e9a-c17498267de5/update-kindle-biscuit_puffin-NS6574_user_7623_0013121734532.bin"
OTA_SHA256="64ab6d2dd85f8093abdd62c275d229c7e9fdd68e4d46892b48bdbd1d100d46d8"
OTA="$REPO_ROOT/workspace/downloads/$(basename "$OTA_URL")"
SYSTEM_IMG="$REPO_ROOT/workspace/extracted/biscuit-fireos-6.5.7.4/system.img"
SYSTEM_SHA256="eccfa850c3009d5454f69a411c0b757be642059b3224cae8fc941fa0dd22c570"
MANIFEST="$REPO_ROOT/vendor/amazon/mt8163-common/fireos6-audio-files.txt"
STOCK_HWC_SYSTEM_IMG="$REPO_ROOT/workspace/extracted/biscuit-stock-272.6.4.1/system.img"
STOCK_HWC_SYSTEM_SHA256="bd928aa5087b8d8c40095c784dfc159cc2555ed4130d617b258bfd0a06659f7c"
STOCK_HWC_OTA_SHA256="28bc050e4a2af79c9ca66e251de7bf04c42ce8d7934dd97673d3d04f5fa0917b"
HWC_MANIFEST="$REPO_ROOT/vendor/amazon/mt8163-common/biscuit-headless-hwc-files.txt"
RADIO_MANIFEST="$REPO_ROOT/vendor/amazon/mt8163-common/biscuit-radio-files.txt"
BT_MANIFEST="$REPO_ROOT/vendor/amazon/mt8163-common/biscuit-bluetooth-files.txt"
COMMON_OUT="$CM14/vendor/amazon/mt8163-common"
PROP="$COMMON_OUT/proprietary"
mkdir -p "$REPO_ROOT/workspace/tmp"
TMP="$(mktemp -d "$REPO_ROOT/workspace/tmp/cm14-fireos6-audio.XXXXXXXXXX")"
STAGED_PROP="$TMP/proprietary"
VENDOR_MK_TMP="$TMP/mt8163-common-vendor.mk"
MINIMAL_VENDOR_MK_TMP="$TMP/mt8163-common-minimal-vendor.mk"
trap 'rm -rf "$TMP"' EXIT

for tool in 7z curl python3 readelf sha256sum stat unzip; do
  command -v "$tool" >/dev/null || { echo "ERROR: required tool not found: $tool" >&2; exit 1; }
done
[[ -d "$CM14/build" ]] || { echo "ERROR: CM14.1 is not synced at $CM14" >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "ERROR: missing audio manifest: $MANIFEST" >&2; exit 1; }
[[ -f "$HWC_MANIFEST" ]] || { echo "ERROR: missing headless HWC manifest: $HWC_MANIFEST" >&2; exit 1; }
[[ -f "$RADIO_MANIFEST" ]] || { echo "ERROR: missing Biscuit radio manifest: $RADIO_MANIFEST" >&2; exit 1; }
[[ -f "$BT_MANIFEST" ]] || { echo "ERROR: missing Biscuit Bluetooth manifest: $BT_MANIFEST" >&2; exit 1; }

mkdir -p "$(dirname "$OTA")" "$(dirname "$SYSTEM_IMG")" "$REPO_ROOT/workspace/tmp"
if [[ ! -f "$OTA" ]]; then
  curl --fail --location --progress-bar -o "$OTA" "$OTA_URL"
fi
printf '%s  %s\n' "$OTA_SHA256" "$OTA" | sha256sum -c -
unzip -t "$OTA" >/dev/null

if [[ ! -f "$SYSTEM_IMG" ]] || ! printf '%s  %s\n' "$SYSTEM_SHA256" "$SYSTEM_IMG" | sha256sum -c - >/dev/null 2>&1; then
  rm -f "$SYSTEM_IMG"
  python3 "$REPO_ROOT/scripts/extract-fireos6-payload.py" "$OTA" system "$SYSTEM_IMG"
fi
printf '%s  %s\n' "$SYSTEM_SHA256" "$SYSTEM_IMG" | sha256sum -c -

if [[ ! -f "$STOCK_HWC_SYSTEM_IMG" ]] || ! printf '%s  %s\n' "$STOCK_HWC_SYSTEM_SHA256" "$STOCK_HWC_SYSTEM_IMG" | sha256sum -c - >/dev/null 2>&1; then
  rm -f "$STOCK_HWC_SYSTEM_IMG"
  BISCUIT_STOCK_OTA_SHA256="$STOCK_HWC_OTA_SHA256" \
    "$REPO_ROOT/scripts/prepare-biscuit-stock-system-image.sh"
fi
printf '%s  %s\n' "$STOCK_HWC_SYSTEM_SHA256" "$STOCK_HWC_SYSTEM_IMG" | sha256sum -c -

rm -rf "$STAGED_PROP"
mkdir -p "$STAGED_PROP"
copy_files=()
blob_count=0

install_if_changed() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    return 0
  fi
  install -m 0644 "$src" "$dst"
}

sync_proprietary_tree() {
  mkdir -p "$PROP"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --no-times --checksum --delete "$STAGED_PROP/" "$PROP/"
  else
    rm -rf "$PROP"
    mkdir -p "$(dirname "$PROP")"
    cp -a "$STAGED_PROP" "$PROP"
  fi
}

extract_file() {
  local image="$1" source="$2" destination="$3" expected_sha="$4" expected_size="$5"
  rm -rf "$TMP/unpack"
  7z x -y -o"$TMP/unpack" "$image" "$source" >/dev/null 2>&1 || true
  local extracted="$TMP/unpack/$source"
  [[ -f "$extracted" ]] || { echo "ERROR: missing source file: $source" >&2; exit 1; }
  [[ "$(stat -c %s "$extracted")" == "$expected_size" ]] || { echo "ERROR: wrong size: $source" >&2; exit 1; }
  [[ "$(sha256sum "$extracted" | awk '{print $1}')" == "$expected_sha" ]] || {
    echo "ERROR: SHA-256 mismatch: $source" >&2; exit 1;
  }
  local mode=0644
  case "$destination" in
    bin/*|vendor/bin/*) mode=0755 ;;
  esac
  install -D -m "$mode" "$extracted" "$STAGED_PROP/$destination"
  copy_files+=("vendor/amazon/mt8163-common/proprietary/$destination:\$(TARGET_COPY_OUT_SYSTEM)/$destination")
  ((blob_count += 1))
}

while IFS=: read -r source destination expected_sha expected_size; do
  [[ -z "$source" || "$source" == \#* ]] && continue
  [[ "$destination" != /* && "$destination" != *".."* ]] || {
    echo "ERROR: unsafe destination in manifest: $destination" >&2; exit 1;
  }
  extract_file "$SYSTEM_IMG" "$source" "$destination" "$expected_sha" "$expected_size"
done < "$MANIFEST"
audio_count="$blob_count"

hwc_count=0
while IFS=: read -r source destination expected_sha expected_size; do
  [[ -z "$source" || "$source" == \#* ]] && continue
  [[ "$destination" != /* && "$destination" != *".."* ]] || {
    echo "ERROR: unsafe destination in HWC manifest: $destination" >&2; exit 1;
  }
  extract_file "$STOCK_HWC_SYSTEM_IMG" "$source" "$destination" "$expected_sha" "$expected_size"
  ((hwc_count += 1))
done < "$HWC_MANIFEST"
[[ "$hwc_count" == 1 ]] || { echo "ERROR: expected one headless HWC blob, got $hwc_count" >&2; exit 1; }

radio_count=0
radio_copy_files=()
while IFS=: read -r source destination expected_sha expected_size; do
  [[ -z "$source" || "$source" == \#* ]] && continue
  [[ "$destination" != /* && "$destination" != *".."* ]] || {
    echo "ERROR: unsafe destination in radio manifest: $destination" >&2; exit 1;
  }
  extract_file "$SYSTEM_IMG" "$source" "$destination" "$expected_sha" "$expected_size"
  radio_copy_files+=("vendor/amazon/mt8163-common/proprietary/$destination:\$(TARGET_COPY_OUT_SYSTEM)/$destination")
  ((radio_count += 1))
done < "$RADIO_MANIFEST"
[[ "$radio_count" == 7 ]] || { echo "ERROR: expected 7 radio files, got $radio_count" >&2; exit 1; }

bt_count=0
while IFS=: read -r source destination expected_sha expected_size; do
  [[ -z "$source" || "$source" == \#* ]] && continue
  [[ "$destination" != /* && "$destination" != *".."* ]] || {
    echo "ERROR: unsafe destination in Bluetooth manifest: $destination" >&2; exit 1;
  }
  extract_file "$SYSTEM_IMG" "$source" "$destination" "$expected_sha" "$expected_size"
  ((bt_count += 1))
done < "$BT_MANIFEST"
[[ "$bt_count" == 2 ]] || { echo "ERROR: expected 2 Bluetooth files, got $bt_count" >&2; exit 1; }

for config in \
  etc/a2dp_audio_policy_configuration.xml \
  etc/audio_device.xml \
  etc/audio_policy.conf \
  etc/audio_policy_configuration.xml \
  etc/audio_policy_volumes.xml \
  etc/r_submix_audio_policy_configuration.xml \
  etc/usb_audio_policy_configuration.xml; do
  rm -rf "$TMP/unpack"
  7z x -y -o"$TMP/unpack" "$SYSTEM_IMG" "system/$config" >/dev/null 2>&1 || true
  [[ -f "$TMP/unpack/system/$config" ]] || { echo "ERROR: missing Fire OS audio config: $config" >&2; exit 1; }
  install -D -m 0644 "$TMP/unpack/system/$config" "$STAGED_PROP/$config"
  if [[ "$config" == etc/audio_device.xml ]]; then
    # Fire OS sets the four TI microphone ADCs to a 20 dB analog preamp and
    # relies on Amazon's audio processor for the rest of the gain. That
    # processor never starts on this build, so raise the preamp to 36 dB:
    # speech then reaches apps at a normal level and the loudest speech
    # measured still peaks about 4 dB below full scale.
    sed -i -E 's/(name="ADC_[A-D] MICPGA Volume Ctrl" value=)"40"/\1"72"/' "$STAGED_PROP/$config"
    [[ "$(grep -c 'MICPGA Volume Ctrl" value="72"' "$STAGED_PROP/$config")" == 4 ]] || {
      echo "ERROR: could not raise the microphone preamp in $config" >&2; exit 1;
    }
  fi
  copy_files+=("vendor/amazon/mt8163-common/proprietary/$config:\$(TARGET_COPY_OUT_SYSTEM)/$config")
done

rm -rf "$TMP/algorithms"
7z x -y -o"$TMP/algorithms" "$SYSTEM_IMG" 'system/vendor/etc/audio-algorithms/*' >/dev/null 2>&1 || true
algorithm_dir="$TMP/algorithms/system/vendor/etc/audio-algorithms"
[[ -d "$algorithm_dir" ]] || { echo "ERROR: missing Fire OS audio algorithms" >&2; exit 1; }
algorithm_count="$(find "$algorithm_dir" -type f -printf . | wc -c | tr -d '[:space:]')"
[[ "$algorithm_count" == 40 ]] || {
  echo "ERROR: unexpected Fire OS audio algorithm count" >&2; exit 1;
}
install -d "$STAGED_PROP/vendor/etc"
cp -a "$algorithm_dir" "$STAGED_PROP/vendor/etc/audio-algorithms"

hal="$STAGED_PROP/lib/hw/audio.primary_amazon.mt8163.so"
printf '%s  %s\n' \
  '26aa25fa71141745c97e1fe67a73589767022513f4f1c54441454f9247270cc8' \
  "$hal" | sha256sum -c - >/dev/null

{
  cat <<'MK'
# Generated by scripts/extract-fireos6-blobs.sh.
# Fire OS 6.5.7.4 audio closure plus stock Biscuit's proven headless HWC; blobs are intentionally untracked.
LOCAL_PATH := $(call my-dir)

PRODUCT_COPY_FILES += \
MK
  for ((i = 0; i < ${#copy_files[@]}; i++)); do
    suffix=$' \\'
    [[ $i -eq $((${#copy_files[@]} - 1)) ]] && suffix=''
    printf '    %s%s\n' "${copy_files[$i]}" "$suffix"
  done
  cat <<'MK'

PRODUCT_COPY_FILES += \
    $(call find-copy-subdir-files,*,$(LOCAL_PATH)/proprietary/vendor/etc/audio-algorithms,$(TARGET_COPY_OUT_SYSTEM)/vendor/etc/audio-algorithms)
MK
} > "$VENDOR_MK_TMP"

{
  cat <<'MK'
# Generated by scripts/extract-fireos6-blobs.sh.
# Fire OS 6.5.7.4 MT8163 radio/Wi-Fi closure for framework-free Biscuit minimal.
LOCAL_PATH := $(call my-dir)

PRODUCT_COPY_FILES += \
MK
  for ((i = 0; i < ${#radio_copy_files[@]}; i++)); do
    suffix=$' \\'
    [[ $i -eq $((${#radio_copy_files[@]} - 1)) ]] && suffix=''
    printf '    %s%s\n' "${radio_copy_files[$i]}" "$suffix"
  done
} > "$MINIMAL_VENDOR_MK_TMP"

sync_proprietary_tree
install_if_changed "$VENDOR_MK_TMP" "$COMMON_OUT/mt8163-common-vendor.mk"
install_if_changed "$MINIMAL_VENDOR_MK_TMP" "$COMMON_OUT/mt8163-common-minimal-vendor.mk"

echo "Staged $audio_count verified Fire OS 6 audio blobs, 40 algorithm files, $hwc_count headless HWC blob, $radio_count Biscuit radio files, $bt_count Bluetooth files, and a minimal radio makefile."
