#!/usr/bin/env bash
# Run the TWRP update script against a fake amzn_bcbtool and updater, and check
# the rest of the system update contract.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OTA="$REPO_ROOT/device/amazon/biscuit/biscuit-service/ota"
SERVICE="$REPO_ROOT/device/amazon/biscuit/biscuit-service"
TMPDIR="$(TMPDIR=/tmp mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

sh -n "$OTA/twrp-update.sh"
openssl pkey -pubin -in "$OTA/release-key.pem" -noout

# A fake BCB: the active slot and whether slot B ever booted.
cat >"$TMPDIR/bcbtool" <<'EOF'
#!/bin/sh
state=$(dirname "$0")/bcb
. "$state"
case "$1" in
    dump) echo "Active slot: $active" ;;
    get_active) echo "$active" ;;
    set_active) [ "$FAIL_SET_ACTIVE" = "$2" ] && exit 1
        active=$2; [ "$2" = b ] && b_success=1
        echo "active=$active b_success=$b_success" >"$state" ;;
    get) echo "$b_success" ;;
esac
EOF
# A fake updater that records the system partition it was pointed at.
cat >"$TMPDIR/updater" <<'EOF'
#!/bin/sh
readlink -f "$LINKS/current-system" >"$LINKS/../updated-system"
case "$MODE" in
    ok) echo "ui_print Patching system image unconditionally..."; exit 0 ;;
    early) echo "ui_print assert failed"; exit 7 ;;
    late) echo "ui_print Patching system image unconditionally..."; exit 7 ;;
esac
EOF
chmod +x "$TMPDIR/bcbtool" "$TMPDIR/updater"

# run <slot> <updater mode> <active> <b_success>
run() {
    local case_dir="$TMPDIR/case"
    rm -rf "$case_dir"
    mkdir -p "$case_dir/cache" "$case_dir/by-name" "$case_dir/links" "$case_dir/tmp"
    for p in system_a system_b boot_a boot_b; do : >"$case_dir/by-name/$p"; done
    cp "$TMPDIR/bcbtool" "$case_dir/bcbtool"
    echo "active=$3 b_success=$4" >"$case_dir/bcb"
    [ -n "${NO_ZIP:-}" ] || : >"$case_dir/cache/update.zip"
    [ -n "${NO_UPDATER:-}" ] || cp "$TMPDIR/updater" "$case_dir/cache/update-binary"
    [ -n "$1" ] && echo "$1" >"$case_dir/cache/slot"
    MODE="$2" LINKS="$case_dir/links" \
        BISCUIT_OTA_DIR="$case_dir/cache" BISCUIT_OTA_BCB="$case_dir/bcbtool" \
        BISCUIT_OTA_BY_NAME="$case_dir/by-name" BISCUIT_OTA_LINKS="$case_dir/links" \
        BISCUIT_OTA_TMP="$case_dir/tmp" FAIL_SET_ACTIVE="${FAIL_SET_ACTIVE:-}" \
        sh "$OTA/twrp-update.sh"
    RESULT=$(cat "$case_dir/cache/result")
    . "$case_dir/bcb"
    UPDATED=$(basename "$(cat "$case_dir/updated-system" 2>/dev/null)" 2>/dev/null || true)
    [ ! -e "$case_dir/cache/slot" ]
}

expect() {
    [[ "$RESULT" == "$1" && "$active" == "$2" && "$UPDATED" == "$3" ]] || {
        echo "FAIL: got '$RESULT' active=$active updated=$UPDATED, want '$1' active=$2 updated=$3" >&2
        exit 1
    }
}

run a ok b 1; expect "ok a" a system_a
run b ok a 0; expect "ok b" a system_b
run b late a 0; expect "failed b updater exited with 7" a system_b
run a early b 1; expect "failed a updater exited with 7" a system_a
run a late b 1; expect "failed a updater exited with 7, slot B is active" b system_a
run a late a 0; expect "failed a updater exited with 7" a system_a
run "" ok a 1; expect "failed  no slot to install into" a ""
FAIL_SET_ACTIVE=b run b ok a 1; expect "failed b could not switch to slot b" a ""
NO_ZIP=1 run a ok b 1; expect "failed a update.zip is missing" b ""
NO_UPDATER=1 run a ok b 1; expect "failed a update-binary is missing" b ""

# The build ships the script and key and stamps the release.
grep -Fq 'biscuit-service/ota/twrp-update.sh:$(TARGET_COPY_OUT_SYSTEM)/etc/biscuit-ota/twrp-update.sh' \
    "$REPO_ROOT/device/amazon/biscuit/device.mk"
grep -Fq 'biscuit-service/ota/release-key.pem:$(TARGET_COPY_OUT_SYSTEM)/etc/biscuit-ota/release-key.pem' \
    "$REPO_ROOT/device/amazon/biscuit/device.mk"
grep -Fq 'ro.biscuit.release=$(BISCUIT_RELEASE)' "$REPO_ROOT/device/amazon/biscuit/device.mk"
grep -Fq "export BISCUIT_RELEASE='\$BISCUIT_RELEASE'" "$REPO_ROOT/scripts/build.sh"
eval "$(sed -n '/^release_version()/,/^}/p' "$REPO_ROOT/scripts/build.sh")"
REPO_ROOT="$TMPDIR"
printf '# Changelog\n\n## Unreleased\n\n### Fixed\n- x\n\n## 2026.10.3 - 2026-10-21\n' >"$TMPDIR/CHANGELOG.md"
[[ "$(release_version)" == 2026.10.3-dev ]]
printf '# Changelog\n\n## 2026.10.4 - 2026-10-24\n\n## 2026.10.3 - 2026-10-21\n' >"$TMPDIR/CHANGELOG.md"
[[ "$(release_version)" == 2026.10.4 ]]
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# The service side.
grep -Fq 'boolean installSystemUpdate();' "$SERVICE/service/src/com/amazon/biscuit/service/IBiscuitService.aidl"
grep -Fq 'android:permission="android.permission.REBOOT"' "$SERVICE/service/AndroidManifest.xml"
grep -Fq 'cmd /sbin/sh " + STEP_SCRIPT + "\nreboot\n' \
    "$SERVICE/service/src/com/amazon/biscuit/service/SystemUpdate.java"
bash -n "$SERVICE/biscuit_service"
grep -Fq 'adb shell biscuit_service update install' "$REPO_ROOT/docs/device-commands.md"

echo 'PASS system update script and contract'
