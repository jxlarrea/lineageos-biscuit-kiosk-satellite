#!/usr/bin/env bash
# Verify the Amonet 2 BCB slotselect fallback patch and its known metadata.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CM14="${CM14:-${BISCUIT_WORKSPACE:-$ROOT/workspace}/cm14.1}"
CORE="$CM14/system/core"
PATCH="$ROOT/patches/full/002-amonet2-bcb-slotselect.patch"
MINIMAL_PATCH="$ROOT/patches/minimal/001-amonet2-bcb-slotselect.patch"
STAGE="$ROOT/scripts/stage-tree.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/system/core/fs_mgr"
git -C "$CORE" show HEAD:fs_mgr/fs_mgr_slotselect.c \
  >"$WORK/system/core/fs_mgr/fs_mgr_slotselect.c"
patch --batch --forward --fuzz=0 --dry-run -d "$WORK" -p1 <"$PATCH" >/dev/null
patch --batch --forward --fuzz=0 -d "$WORK" -p1 <"$PATCH" >/dev/null

grep -Fqx '#define AMONET_BCB_MAGIC "ABB"' \
  "$WORK/system/core/fs_mgr/fs_mgr_slotselect.c"
grep -Fqx '#define AMONET_BCB_VERSION 1' \
  "$WORK/system/core/fs_mgr/fs_mgr_slotselect.c"
grep -Fqx '    out_suffix[1] = '\''a'\'' + slot;' \
  "$WORK/system/core/fs_mgr/fs_mgr_slotselect.c"
cmp -s "$PATCH" "$MINIMAL_PATCH"
grep -Fqx 'PATCH_PROFILE="${PATCH_PROFILE:-full}"' \
  "$STAGE"
grep -Fqx 'PROFILE_PATCH_DIR="$REPO_ROOT/patches/$PATCH_PROFILE"' \
  "$STAGE"
grep -Fq 'PATCH_REAPPLY=1 PATCH_STATE_DIR="$PATCH_STATE_DIR" \' \
  "$STAGE"
grep -Fq '"$REPO_ROOT/scripts/apply-patches.sh" "$CM14" 1 "$PROFILE_PATCH_DIR"' \
  "$STAGE"

python3 - <<'PY'
def suffix(bcb):
    if len(bcb) < 7 or bcb[:4] != b"\0ABB" or bcb[4] != 1:
        return None
    slot = 1 if (bcb[6] & 0x0f) > (bcb[5] & 0x0f) else 0
    bootable = lambda metadata: bool(metadata & 0x80 or metadata & 0x70)
    if not bootable(bcb[5 + slot]):
        slot = 1 - slot
        if not bootable(bcb[5 + slot]):
            return None
    return "_" + "ab"[slot]

# Live Amonet 2 BCB header: version 1, A prio=15/tries=2/success=1,
# B prio=14/tries=3/success=0.
assert suffix(bytes((0, 0x41, 0x42, 0x42, 1, 0xaf, 0x3e))) == "_a"
assert suffix(bytes((0, 0x41, 0x42, 0x42, 1, 0x0f, 0x3e))) == "_b"
assert suffix(bytes((0, 0x41, 0x42, 0x42, 1, 0x0f, 0x0e))) is None
assert suffix(bytes((0, 0x42, 0x41, 0x44, 1, 0xaf, 0x3e))) is None
PY

echo 'PASS CM14 Amonet 2 BCB slotselect contract'
