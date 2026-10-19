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

## Kiosk Satellite installer

On every boot the image makes sure Kiosk Satellite is installed and has its permissions. This turns that off if you are planning to run the Dot without Kiosk Satellite:

```sh
adb shell setprop persist.biscuit.ks_install 0
```
