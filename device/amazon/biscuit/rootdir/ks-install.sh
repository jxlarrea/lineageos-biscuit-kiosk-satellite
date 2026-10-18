#!/system/bin/sh
# Kiosk Satellite Edition: install Kiosk Satellite on first boot and keep its
# grants in place on every boot. Runs as root once Android has booted.
#
# Without a screen nothing can accept a permission prompt, so everything the
# kiosk needs is granted here: the microphone, location for the Bluetooth
# proxy, storage for the File Manager, the battery exemption, the button
# service for versions that predate the Action button broadcast, and device
# owner, which lets Kiosk Satellite update itself without a confirmation.
#
# setprop persist.biscuit.ks_install 0 turns this off.

PKG=me.jxl.kiosk_satellite
RELEASES=https://api.github.com/repos/jxlarrea/kiosk-satellite/releases/latest
CERTS=/system/etc/security/cacerts
APK=/data/local/tmp/kiosk-satellite.apk

log() { /system/bin/log -t ks-install "$*"; }
fetch() { curl -sSL --fail --capath "$CERTS" --connect-timeout 20 "$@"; }

[ "$(getprop persist.biscuit.ks_install)" = "0" ] && exit 0

first_install=0
if ! pm path "$PKG" >/dev/null 2>&1; then
    # Wait for the network: Wi-Fi may still be joining, or not set up yet.
    tries=0
    until fetch -o /dev/null --max-time 20 https://api.github.com; do
        tries=$((tries + 1))
        if [ "$tries" -ge 360 ]; then
            log "no network after an hour, giving up until the next boot"
            exit 1
        fi
        sleep 10
    done

    # The split for this device's ABI, the same file the in-app updater picks,
    # so later updates install over it. The universal APK otherwise.
    release=$(fetch "$RELEASES") || { log "could not read the latest release"; exit 1; }
    abi=$(getprop ro.product.cpu.abi)
    urls=$(echo "$release" | grep -o '"browser_download_url": *"[^"]*\.apk"' | sed 's/.*"\(https[^"]*\)"/\1/')
    url=$(echo "$urls" | grep "\.$abi\.apk$" | head -n 1)
    [ -n "$url" ] || url=$(echo "$urls" | grep -E 'kiosk-satellite-v?[0-9.]+\.apk$' | head -n 1)
    [ -n "$url" ] || { log "no APK in the latest release"; exit 1; }

    log "downloading $url"
    fetch -o "$APK" "$url" || { log "download failed"; rm -f "$APK"; exit 1; }
    if ! pm install -r "$APK" >/dev/null; then
        log "install failed"
        rm -f "$APK"
        exit 1
    fi
    rm -f "$APK"
    log "installed Kiosk Satellite"
    first_install=1
    # Started once, as Android requires before it delivers the boot broadcast.
    am start -n "$PKG/.ProvisionActivity" >/dev/null 2>&1
    sleep 10
fi

for permission in RECORD_AUDIO ACCESS_COARSE_LOCATION ACCESS_FINE_LOCATION \
        READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE; do
    pm grant "$PKG" "android.permission.$permission" 2>/dev/null
done
dumpsys deviceidle whitelist "+$PKG" >/dev/null

# Versions before the Action button broadcast hear the button through an
# accessibility service. Switched on again on every boot, since a force-stop
# switches it off.
service="$PKG/.HeadlessKeyService"
current=$(settings get secure enabled_accessibility_services)
case "$current" in
    *"$service"*) ;;
    ""|null) settings put secure enabled_accessibility_services "$service" ;;
    *) settings put secure enabled_accessibility_services "$current:$service" ;;
esac
settings put secure accessibility_enabled 1

# Device owner needs a device with no accounts, which a headless one has.
if ! dumpsys device_policy | grep -A3 "Device Owner" | grep -q "package="; then
    dpm set-device-owner "$PKG/.KioskAdminReceiver" >/dev/null 2>&1 &&
        log "Kiosk Satellite is the device owner"
fi

# Android 7 only starts an accessibility service whose component was enabled
# after boot once it boots again. Versions that use the broadcast never
# enable it, so this reboot only happens for older ones, once.
if [ "$first_install" = 1 ] &&
        pm dump "$PKG" | grep -A3 "enabledComponents" | grep -q "HeadlessKeyService" &&
        ! dumpsys accessibility | grep -q "HeadlessKeyService"; then
    log "rebooting once so Android starts the button service"
    sleep 5
    reboot
fi
