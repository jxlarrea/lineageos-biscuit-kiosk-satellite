#!/sbin/sh
# Kiosk Satellite Edition: install a system update from inside TWRP.
#
# BiscuitService copies this to /cache/biscuit-ota with the release zip and
# its update-binary, names the slot to install into in /cache/biscuit-ota/slot
# and reboots into recovery with an openrecoveryscript that runs this and then
# reboots. TWRP's own install command stops the script when an install fails
# and leaves the Dot waiting in TWRP, so this runs the zip's updater itself
# and always exits 0. The result goes to /cache/biscuit-ota/result for
# BiscuitService to read once Android is back. Android deletes everything in
# /cache/recovery but the last_* files at boot, so nothing goes there.
#
# The bootloader always starts boot_a, whatever slot is active. Slot A gets
# the update first and stays active. Slot B gets it once slot A has booted,
# and slot A is made active again afterwards.

# The overrides are for tests/test-system-update.sh.
DIR=${BISCUIT_OTA_DIR:-/cache/biscuit-ota}
BCB=${BISCUIT_OTA_BCB:-/sbin/amzn_bcbtool}
BY_NAME=${BISCUIT_OTA_BY_NAME:-/dev/block/platform/bootdevice/by-name}
LINKS=${BISCUIT_OTA_LINKS:-/dev/block}
TMP=${BISCUIT_OTA_TMP:-/tmp}
UPDATER=$TMP/biscuit-ota-updater

exec >>"$DIR/twrp.log" 2>&1
echo "=== $(date) slot $(cat "$DIR/slot" 2>/dev/null)"
"$BCB" dump

finish() {
    echo "result: $*"
    echo "$*" >"$DIR/result"
    rm -f "$DIR/slot"
    sync
    exit 0
}

# Make slot $1 active and point the current-slot links, which the zip's
# updater checks against the active slot, at it. TWRP only sets them when it
# starts.
use_slot() {
    "$BCB" set_active "$1" || return 1
    ln -sf "$(readlink -f "$BY_NAME/system_$1")" "$LINKS/current-system" &&
        ln -sf "$(readlink -f "$BY_NAME/boot_$1")" "$LINKS/current-boot"
}

slot=$(cat "$DIR/slot" 2>/dev/null)
case "$slot" in
    a|b) ;;
    *) finish "failed $slot no slot to install into" ;;
esac

[ -f "$DIR/update.zip" ] || finish "failed $slot update.zip is missing"
cp "$DIR/update-binary" "$UPDATER" && chmod 0755 "$UPDATER" ||
    finish "failed $slot update-binary is missing"

use_slot "$slot" || {
    use_slot a
    finish "failed $slot could not switch to slot $slot"
}

# The updater writes its progress commands to the file descriptor named in
# its second argument. 1 sends them to $OUT, which goes into the log after.
OUT=$TMP/biscuit-ota-updater.out
"$UPDATER" 3 1 "$DIR/update.zip" >"$OUT" 2>&1
rc=$?
cat "$OUT"
rm -f "$UPDATER"

if [ "$slot" = b ]; then
    use_slot a
    [ $rc -eq 0 ] && finish "ok b"
    finish "failed b updater exited with $rc"
fi

[ $rc -eq 0 ] && finish "ok a"

# A failure before the updater writes system_a, such as its slot check,
# leaves slot A as it was. The updater writes system before boot, so a
# failure after that leaves boot_a as it was and slot B, if an earlier
# install put the image there, holds a system that matches that kernel.
if grep -q "Patching system image" "$OUT" && [ "$("$BCB" get b success)" = 1 ]; then
    use_slot b
    finish "failed a updater exited with $rc, slot B is active"
fi
finish "failed a updater exited with $rc"
