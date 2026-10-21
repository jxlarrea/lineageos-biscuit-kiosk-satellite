# Getting into TWRP

Install the image from TWRP 3.7.0_9-0, the recovery that comes with amonet v2.0.0. [Unlocking the Echo Dot](unlocking.md) installs both.

## Starting TWRP

If the Dot is running, connect it over USB and run:

```sh
adb reboot recovery
```

TWRP shows up in `adb devices -l` as `recovery` within about half a minute. Check with `adb devices -l` rather than `adb wait-for-recovery`, which can hang on the Dot.

If the Dot does not boot, unplug it, hold the **+** button and plug it back in. That starts TWRP, since amonet v2 has no fastboot mode. If TWRP does not show up either, see [If the Dot keeps restarting](#if-the-dot-keeps-restarting).

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

The Dot has two system slots, A and B, and boots from the active one. The [installation](../README.md#installing) installs the image into both. These commands show and switch the active slot from TWRP:

```sh
adb shell bcbtool get_active
adb shell bcbtool set_active b
```

After switching, reboot into TWRP and run `get_active` again before installing. The installer checks that TWRP points at the active slot and stops with `assert failed` if it does not.

## If the Dot keeps restarting

The image never writes TWRP, the bootloader or the partition table, so a Dot that keeps restarting after an install can almost always be recovered. Each restart shows up on your computer as a USB device that connects and then disconnects.

1. **Wait.** The first boot takes about a minute and a half, and the Dot connects and disconnects a few times along the way. Give it three minutes.
2. **Check the power.** The Dot runs on the micro USB cable. TWRP draws little, but Android starts Wi-Fi, audio and all four cores, and a weak computer port or unpowered hub may not keep up. Plug the Dot into its own power adapter. If it then stops restarting, use a stronger port or a powered hub for adb.
3. **Start TWRP with the + button.** Unplug the Dot, hold the **+** button and plug it back in. TWRP shows up in `adb devices -l` as `recovery` within about half a minute. Both slots hold the image after the [installation](../README.md#installing), so switching slots boots the other copy. Run `adb shell bcbtool get_active`, then `adb shell bcbtool set_active` with the other slot and `adb reboot`. If the other slot does not have the image yet, switch to it, reboot into TWRP and install from step 2 of the installation.
4. **Catch adb during a restart.** If `adb devices -l` lists the Dot for a moment during each cycle, Android is starting and then failing. Run `adb reboot recovery` while it is listed to get back to TWRP.
5. **Use the Preloader's download mode.** If TWRP never shows up, unplug the Dot, hold only the **mute** button and plug it back in. Your computer then sees a `PWNED MT8163 Preloader`. amonet v2 uses this mode to repair a Dot that no longer boots. Follow the Important Notes in the [amonet thread on XDA](https://xdaforums.com/t/unlock-root-twrp-unbrick-amazon-echo-dot-2nd-gen-2016-biscuit.4761416/) for the rest of the procedure. If the Dot shows no light at all, see the test point section of firebreak's [README](https://github.com/bboe/firebreak#run-it).

If you ask for help, include what both `twrp install` runs and `bcbtool get_active` printed, and whether adb ever shows the Dot during a restart.
