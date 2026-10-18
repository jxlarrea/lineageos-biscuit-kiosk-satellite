#!/usr/bin/env bash
# Download stock Biscuit OTA and convert system.new.dat + system.transfer.list to system.img.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The checkout, downloads and build output: tens of GB, so it can live
# outside the repository (BISCUIT_WORKSPACE).
WORKSPACE_DIR="${BISCUIT_WORKSPACE:-$REPO_ROOT/workspace}"
STOCK_OTA_URL="${BISCUIT_STOCK_OTA_URL:-https://d1s31zyz7dcc2d.cloudfront.net/8811a0fc982bf3331dc54f5aec45d936/update-kindle-full_biscuit-272.6.4.1_user_641575220.bin}"
STOCK_OTA_BIN="${BISCUIT_STOCK_OTA_BIN:-$WORKSPACE_DIR/downloads/$(basename "$STOCK_OTA_URL")}"
OUT_DIR="${BISCUIT_STOCK_OTA_EXTRACT_DIR:-$WORKSPACE_DIR/extracted/biscuit-stock-272.6.4.1}"
SYSTEM_NEW_DAT="$OUT_DIR/system.new.dat"
SYSTEM_TRANSFER_LIST="$OUT_DIR/system.transfer.list"
SYSTEM_IMG="${BISCUIT_SYSTEM_IMG:-$OUT_DIR/system.img}"
BLOCK_SIZE=4096

mkdir -p "$(dirname "$STOCK_OTA_BIN")" "$OUT_DIR"

if [[ ! -f "$STOCK_OTA_BIN" ]]; then
  echo "Downloading stock Biscuit OTA: $STOCK_OTA_URL"
  curl -L --fail --retry 3 --continue-at - -o "$STOCK_OTA_BIN" "$STOCK_OTA_URL"
fi

if [[ -n "${BISCUIT_STOCK_OTA_SHA256:-}" ]]; then
  echo "$BISCUIT_STOCK_OTA_SHA256  $STOCK_OTA_BIN" | sha256sum -c -
fi

command -v unzip >/dev/null || { echo "ERROR: unzip required" >&2; exit 1; }

if [[ ! -f "$SYSTEM_NEW_DAT" || ! -f "$SYSTEM_TRANSFER_LIST" ]]; then
  echo "Extracting system.new.dat and system.transfer.list ..."
  unzip -p "$STOCK_OTA_BIN" system.new.dat > "$SYSTEM_NEW_DAT"
  unzip -p "$STOCK_OTA_BIN" system.transfer.list > "$SYSTEM_TRANSFER_LIST"
fi

if [[ -f "$SYSTEM_IMG" ]]; then
  echo "system.img ready: $SYSTEM_IMG"
  exit 0
fi

echo "Converting block OTA system.new.dat -> system.img ..."
python3 - "$SYSTEM_TRANSFER_LIST" "$SYSTEM_NEW_DAT" "$SYSTEM_IMG" "$BLOCK_SIZE" <<'PY'
import os, sys
transfer_path, dat_path, img_path, block_size_s = sys.argv[1:]
block_size = int(block_size_s)

lines = [l.strip() for l in open(transfer_path) if l.strip()]
version = int(lines[0])
if version not in (1, 2, 3, 4):
    raise SystemExit(f"unsupported transfer.list version: {version}")

commands = lines[4:] if version >= 2 else lines[2:]

def pairs(spec):
    nums = [int(x) for x in spec.split(',')]
    if not nums or nums[0] != len(nums) - 1 or (len(nums) - 1) % 2:
        raise SystemExit(f"bad range spec: {spec}")
    return list(zip(nums[1::2], nums[2::2]))

max_block = 0
for line in commands:
    parts = line.split()
    if len(parts) < 2:
        continue
    if parts[0] in {'new', 'erase', 'zero'}:
        for start, end in pairs(parts[1]):
            max_block = max(max_block, end)

with open(dat_path, 'rb') as dat, open(img_path, 'wb') as img:
    img.truncate(max_block * block_size)
    for line in commands:
        parts = line.split()
        if len(parts) < 2 or parts[0] != 'new':
            continue
        for start, end in pairs(parts[1]):
            size = (end - start) * block_size
            data = dat.read(size)
            if len(data) != size:
                raise SystemExit(f"short system.new.dat while writing {start}-{end}")
            img.seek(start * block_size)
            img.write(data)
    extra = dat.read(1)
    if extra:
        raise SystemExit("unused bytes left in system.new.dat")

print(f"wrote {img_path} ({os.path.getsize(img_path)} bytes)")
PY

echo "system.img ready: $SYSTEM_IMG"
