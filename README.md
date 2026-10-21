# LineageOS 14.1 Kiosk Satellite Edition for the Echo Dot (2nd Gen)

A LineageOS 14.1 (Android 7.1.2) image for the 2nd generation Echo Dot (`biscuit`), tuned to run [Kiosk Satellite](https://github.com/jxlarrea/kiosk-satellite) as a voice satellite, intercom and speaker for Home Assistant. It is built on [hkfuertes' CM14.1 port](https://github.com/hkfuertes/amazon_device_biscuit) and made for this one job, so it leaves out the launcher, the screen apps and telephony.

## What it improves over the upstream port

- **Wake word detection over loud music.** The Dot has seven microphones but Android only detects one. The image reads all seven and removes the speaker's sound from them while music plays: 13 to 17 dB less music, with your voice nearly untouched. The wake word works with music at 100% volume, where it used to fail from about 75%.
- **Amazon's wake word engine** The image includes Amazon's own wake word engine with its models for Alexa, Echo, Computer, Amazon and Ziggy in 17 locales, so Kiosk Satellite can listen the way an Echo does. A plain "stop" stops a ringing timer or a reply. It runs on the Dot, with nothing sent to Amazon. microWakeWord, openWakeword and vsWakeWord are also available in Kiosk Satellite.
- **A louder microphone.** The microphone preamp goes from 20 dB to 36 dB. Speech used to come in about 20 dB too quiet, and intercom calls from the Dot were barely audible.
- **Less CPU at idle.** SurfaceFlinger used about 5% of a core retrying a framebuffer the Dot does not have, logging about 110 lines a second as it did. It now stays under 1%. The audio driver's "asp Pipeline doesn't exist" error, logged about 75 times a second during playback, is gone too. The display runs at 1 fps instead of 60, and there is no boot animation.
- **More free memory.** SystemUI (29 MB), the phone process and its providers (26 MB), LiveDisplay and nearly 30 unused apps and services are left out. Swap on zram (256 MB) now works: upstream configured more swap than the Dot has RAM, with a compression method its kernel lacks, so it never started. Apps get the standard Dalvik heap settings for 512 MB devices instead of a 16 MB limit. With Kiosk Satellite running, around 300 MB of the Dot's 480 MB stays free.
- **More disk space.** The Android System WebView is left out too, since nothing on the Dot draws a web page. The system partition holds 337 MB instead of 456 MB, and about 990 MB of the data partition is free after setup.
- **Steadier Wi-Fi between kiosks.** Wi-Fi power saving is off. With it on, about one broadcast in five never arrived, and wake word arbitration between kiosks runs on those broadcasts.
- **A steady light ring and a clean speaker.** The light ring no longer strobes while Kiosk Satellite animates it, and it goes back to Kiosk Satellite's colors after the volume overlay. The speaker no longer crackles on the first playback after boot.
- **Automatic Kiosk Satellite installation.** On first boot the latest Kiosk Satellite release is downloaded, installed, given every permission and made the device owner, so its updates install without a confirmation. No adb grants needed.
- **The Action button as a broadcast.** The Action button reaches apps as a broadcast, so newer Kiosk Satellite versions do not need an accessibility service to receive it.
- **Volume buttons for a Music Assistant group.** Kiosk Satellite can take over the volume buttons, so they change the volume of the Music Assistant group the Dot plays in, or of a player it follows, instead of the Dot's own. Set **Volume buttons control the player** to **While the player is playing** under Media Player. The buttons go back to the Dot's own volume when the Dot plays alone or Kiosk Satellite stops.

See [Kiosk Satellite Edition](docs/kiosk-satellite-edition.md) for every change and how it was measured.

## Before you start

- **An unlocked Dot with TWRP.** The image needs amonet v2.0.0 and its TWRP 3.7.0_9-0. Follow [Unlocking the Echo Dot](docs/unlocking.md), then [Getting into TWRP](docs/twrp.md).
- **adb** on your computer and a micro USB cable that carries data.
- **Your Wi-Fi name and password.**

## Installing

1. Download the `.zip` file from the [latest release](https://github.com/jxlarrea/lineageos-biscuit-kiosk-satellite/releases/latest).
2. Start TWRP:

   ```sh
   adb reboot recovery
   ```

   Run `adb devices -l` until it lists the Dot as `recovery`, which takes about half a minute. Then check the TWRP version:

   ```sh
   adb shell getprop ro.twrp.version
   ```

   It must print `3.7.0_9-0`. If it prints anything else, stop here and see [Getting into TWRP](docs/twrp.md#checking-the-version).

   Then check the active slot:

   ```sh
   adb shell bcbtool get_active
   ```

   It must print `a`, because the Dot always starts slot A's kernel and the first copy of the image has to bring it. If it prints `b`, run `adb shell bcbtool set_active a` and `adb reboot recovery`, then check again.

3. Erase the Dot and install the image. Replace `<image>.zip` with the file you downloaded:

   ```sh
   adb shell twrp wipe cache
   adb shell twrp wipe data
   adb push <image>.zip /sdcard/update.zip
   adb shell twrp install /sdcard/update.zip
   ```

   If the install prints an error or `assert failed`, stop here and do not reboot. TWRP is still running, so nothing is lost yet. Otherwise reboot:

   ```sh
   adb reboot
   ```

4. Check that it boots. The first boot takes about a minute and a half. On the way, the Dot connects and disconnects from your computer a few times, so leave it plugged in for at least three minutes before deciding something is wrong. It has booted once this prints `1`:

   ```sh
   adb shell getprop sys.boot_completed
   ```

   If it keeps restarting, stop here and see [If the Dot keeps restarting](docs/twrp.md#if-the-dot-keeps-restarting).

5. Install the image into the Dot's other slot too, so both slots hold a copy that boots. Start TWRP:

   ```sh
   adb reboot recovery
   ```

   Run `adb devices -l` until it lists the Dot as `recovery`. `bcbtool get_active` prints `a` or `b`. Switch to the other slot:

   ```sh
   adb shell bcbtool get_active
   adb shell bcbtool set_active b
   adb reboot recovery
   ```

   If `get_active` printed `b`, use `set_active a` instead. Run `adb devices -l` until it lists the Dot as `recovery` again. Check that the switch took, then install. Leave out `twrp wipe data` this time, so Kiosk Satellite and its settings stay:

   ```sh
   adb shell bcbtool get_active
   adb shell twrp install /sdcard/update.zip
   ```

   `get_active` must print the slot you switched to. If it does not or the install prints an error or `assert failed`, do not reboot. Run `adb shell bcbtool set_active` with the slot you started from to go back to the copy that boots, then reboot. Otherwise finish:

   ```sh
   adb shell rm /sdcard/update.zip
   adb reboot
   ```

6. Check that this slot boots too, the same way as in step 4. If it keeps restarting, unplug the Dot, hold the **+** button and plug it back in to start TWRP. Then run `adb shell bcbtool set_active` with the slot you started from and `adb reboot`. That boots the copy that worked.

To update the image later, follow the same steps but skip `twrp wipe data`, which keeps Kiosk Satellite and its settings.

## After installing

1. **Join Wi-Fi.** The second command shows the Dot's IP address:

   ```sh
   adb shell "biscuit_service wifi connect '<ssid>' '<password>'"
   adb shell ip -4 addr show wlan0
   ```

   Keep the double quotes around the whole command. Without them, `adb shell` splits a Wi-Fi name or password with spaces into separate words before it reaches the Dot.

2. **Bluetooth** is off. If you want Kiosk Satellite's Bluetooth proxy or the Dot's Bluetooth speaker mode, turn it on:

   ```sh
   adb shell biscuit_service bt on
   ```

   It stays on across reboots. For the first five minutes after this command, the Dot can also be paired as a Bluetooth speaker.

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
