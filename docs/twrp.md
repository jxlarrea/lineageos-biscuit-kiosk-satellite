# Getting into TWRP

Install the image from TWRP 3.7.0_9-0, the recovery that comes with amonet v2.0.0. [Unlocking the Echo Dot](unlocking.md) installs both.

## Starting TWRP

If the Dot is running, connect it over USB and run:

```sh
adb reboot recovery
```

If the Dot does not boot, unplug it, hold the **+** button and plug it back in. TWRP shows up in `adb devices` as `recovery` within about half a minute.

TWRP has no screen on the Dot. Everything runs over `adb shell`, and the `twrp` command does what its buttons would on a phone, such as `twrp install` and `twrp wipe`.

## Checking the version

```sh
adb shell getprop ro.twrp.version
```

It should print `3.7.0_9-0`. If it prints an older version, the Dot is on amonet v1, which this image does not support.

## Updating from amonet v1 to v2

Use firebreak to update from amonet v1 to amonet v2:

```sh
uvx firebreak@latest amonet-biscuit-v2.0.0
```

The update rewrites the Dot's bootloader, so never unplug the Dot while it runs.

## The two slots

The Dot has two system slots, A and B, and boots from the active one. The installation in the [README](../README.md#installing) installs the image into both, so the Dot always has a working copy to fall back to. These commands show and switch the active slot from TWRP:

```sh
adb shell bcbtool get_active
adb shell bcbtool set_active b
```
