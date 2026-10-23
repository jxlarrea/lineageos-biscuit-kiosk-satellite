# Device commands

The image includes `biscuit_service`, which controls the Dot's Wi-Fi, Bluetooth, volume and light ring from `adb shell`. Kiosk Satellite does most of this on its own once it runs, so these are mainly for setup and troubleshooting.

```sh
adb shell biscuit_service wifi on
adb shell "biscuit_service wifi connect '<ssid>' '<password>'"
adb shell biscuit_service wifi off
adb shell biscuit_service bt on
adb shell biscuit_service bt off
adb shell biscuit_service bt pair
adb shell biscuit_service volume up
adb shell biscuit_service volume down
adb shell biscuit_service volume set '<0..max>'
adb shell biscuit_service mute on|off|toggle
adb shell biscuit_service mic mute|unmute|toggle
adb shell biscuit_service countdown set '<remaining-ms>' '<total-ms>'
adb shell biscuit_service countdown clear
```

## System updates

Starting with the first release after 2026.10.3, the Dot can update itself to a newer release. Kiosk Satellite shows the update in Home Assistant. These commands do the same from adb:

```sh
adb shell biscuit_service update status
adb shell biscuit_service update check
adb shell biscuit_service update install
```

`update status` prints the installed release, the newest one and what the update is doing. `update check` asks GitHub for a newer release right away. The Dot also checks a minute after every boot.

`update install` downloads the newest release to `/cache` and checks it against GitHub's checksum and the release signature. Then it reboots into TWRP, installs the release into slot A and starts Android again. Two minutes after Android boots from slot A, it does the same for slot B and makes slot A active again. Each slot takes the Dot offline for about a minute and a half. Kiosk Satellite and its settings stay.

If an install fails, `update status` says why. TWRP's side of each install is in `/cache/biscuit-ota/twrp.log`.

## Kiosk Satellite installer

On every boot the image makes sure Kiosk Satellite is installed and has its permissions. This turns that off if you are planning to run the Dot without Kiosk Satellite:

```sh
adb shell setprop persist.biscuit.ks_install 0
```
