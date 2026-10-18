# Kiosk Satellite Edition for the Echo Dot (2nd Gen)

A LineageOS 14.1 (Android 7.1.2) image for the 2nd generation Echo Dot (`biscuit`), tuned to run [Kiosk Satellite](https://github.com/jxlarrea/kiosk-satellite) as a voice satellite, intercom and speaker for Home Assistant. It is built on [hkfuertes' CM14.1 port](https://github.com/hkfuertes/amazon_device_biscuit) and made for this one job, so it leaves out the launcher, the screen apps and telephony.

## What it improves over the upstream port

- **Wake word detection over loud music.** The Dot has seven microphones but Android only detects one. The image reads all seven and removes the speaker's sound from them while music plays: 13 to 17 dB less music, with your voice nearly untouched. The wake word works with music at 100% volume, where it used to fail from about 75%.
- **A louder microphone.** The microphone preamp goes from 20 dB to 36 dB. Speech used to come in about 20 dB too quiet, and intercom calls from the Dot were barely audible.
- **Less CPU at idle.** SurfaceFlinger used about 5% of a core retrying a framebuffer the Dot does not have, logging about 110 lines a second as it did. It now stays under 1%. The audio driver's "asp Pipeline doesn't exist" error, logged about 75 times a second during playback, is gone too. The display runs at 1 fps instead of 60, and there is no boot animation.
- **More free memory.** SystemUI (29 MB), the phone process and its providers (26 MB), LiveDisplay and nearly 30 unused apps and services are left out. Swap on zram (256 MB) now works: upstream configured more swap than the Dot has RAM, with a compression method its kernel lacks, so it never started. Apps get the standard Dalvik heap settings for 512 MB devices instead of a 16 MB limit. With Kiosk Satellite running, about 225 MB of the Dot's 480 MB stays free.
- **More disk space.** The system partition holds 421 MB instead of 456 MB, and about 990 MB of the data partition is free after setup.
- **Steadier Wi-Fi between kiosks.** Wi-Fi power saving is off. With it on, about one broadcast in five never arrived, and wake word arbitration between kiosks runs on those broadcasts.
- **A steady light ring and a clean speaker.** The light ring no longer strobes while Kiosk Satellite animates it, and it goes back to Kiosk Satellite's colors after the volume overlay. The speaker no longer crackles on the first playback after boot.
- **Automatic Kiosk Satellite installation.** On first boot the latest Kiosk Satellite release is downloaded, installed, given every permission and made the device owner, so its updates install without a confirmation. No adb grants needed.
- **The Action button as a broadcast.** The Action button reaches apps as a broadcast, so newer Kiosk Satellite versions do not need an accessibility service to receive it.

See [Kiosk Satellite Edition](docs/kiosk-satellite-edition.md) for every change and how it was measured.

## Before you start

- **An unlocked Dot with TWRP.** The image needs amonet v2.0.0 and its TWRP 3.7.0_9-0. Follow [Unlocking the Echo Dot](docs/unlocking.md), then [Getting into TWRP](docs/twrp.md).
- **adb** on your computer and a micro USB cable that carries data.
- **Your Wi-Fi name and password.**

## Installing

1. Download the `.zip` file from the [latest release](https://github.com/jxlarrea/amazon_device_biscuit/releases/latest).
2. Start TWRP:

   ```sh
   adb reboot recovery
   adb wait-for-recovery
   ```

3. Erase the Dot and install the image. Replace `<image>.zip` with the file you downloaded:

   ```sh
   adb shell twrp wipe cache
   adb shell twrp wipe data
   adb push <image>.zip /sdcard/update.zip
   adb shell twrp install /sdcard/update.zip
   ```

4. Install it into the Dot's second slot too, so it always has a working copy to fall back to. `bcbtool get_active` prints `a` or `b`. Switch to the other one:

   ```sh
   adb shell bcbtool get_active
   adb shell bcbtool set_active b
   adb reboot recovery
   adb wait-for-recovery
   adb shell twrp install /sdcard/update.zip
   adb shell rm /sdcard/update.zip
   adb reboot
   ```

   If `get_active` printed `b`, use `set_active a` instead.

The first boot takes about a minute and a half. To update the image later, follow the same steps but skip `twrp wipe data`, which keeps Kiosk Satellite and its settings.

## After installing

1. **Join Wi-Fi.** The second command shows the Dot's IP address:

   ```sh
   adb shell biscuit_service wifi connect '<ssid>' '<password>'
   adb shell ip -4 addr show wlan0
   ```

2. **Bluetooth** is on, for the Dot's Bluetooth speaker mode and Kiosk Satellite's Bluetooth proxy. If you are not using either, turn it off to save 15 to 20 MB of RAM:

   ```sh
   adb shell biscuit_service bt off
   ```

3. **Wait for Kiosk Satellite.** Once the Dot is on Wi-Fi, Kiosk Satellite is downloaded and installed automatically. Follow the progress with:

   ```sh
   adb logcat -s ks-install
   ```

   It prints `downloading`, `installed Kiosk Satellite` and `Kiosk Satellite is the device owner`, then `rebooting once so Android starts the button service`. This takes a couple of minutes, and the Dot restarts once at the end.

4. **Set up Kiosk Satellite.** Open `http://<dot ip>:2324` in a browser. In the setup wizard, set an admin password, your Home Assistant connection and the wake word. Then add the Dot in Home Assistant under **Settings > Devices & services**, where it shows up as discovered. The [Echo Dot guide](https://github.com/jxlarrea/kiosk-satellite/blob/main/docs/echo-dot.md) covers the buttons, the light ring and the other Kiosk Satellite features on the Dot.

[Device commands](docs/device-commands.md) lists what else you can control from `adb shell`.

## Building

See [Building the CM14.1 images](docs/building-cm14.1-images.md). Builds run in Docker. The large source checkout goes in `workspace/`, or wherever `BISCUIT_WORKSPACE` points.

## Thanks

- [hkfuertes](https://github.com/hkfuertes), for the [CM14.1 port](https://github.com/hkfuertes/amazon_device_biscuit) this image is built on: the device tree, the kernel, the audio driver wrapper, the light ring service and the build system.
- [meiser79](https://github.com/meiser79), for the speaker amplifier sequencing that ends the first-playback crackle and the TSL2540 light sensor fallback, both from their LineageOS ports.
- xyz, k4y0z and Rortiz2 for amonet and its Echo Dot port, and [bboe](https://github.com/bboe) for [firebreak](https://github.com/bboe/firebreak).
