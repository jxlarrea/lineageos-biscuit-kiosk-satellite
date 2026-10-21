# Changelog

All notable changes to LineageOS for the Echo Dot (2nd Gen), Kiosk Satellite Edition are documented here. Images are published on the [releases page](https://github.com/jxlarrea/lineageos-biscuit-kiosk-satellite/releases).

## Unreleased

### Added
- **Alexa as a wake word.** The image now includes Amazon's own wake word engine and the Alexa model from Fire OS, so Kiosk Satellite can listen for "Alexa" the way the Dot did before it was unlocked. A plain "stop" also stops a ringing timer or a reply, where Amazon's model only heard "stop" right after "Alexa". Choose **Amazon** as the wake word engine in Kiosk Satellite, in a version that supports it.

### Fixed
- **Getting into TWRP on a Dot that does not boot.** The TWRP guide again says to hold the **+** button while plugging the Dot in, which starts TWRP on amonet v2. A new section covers a Dot that keeps restarting after an install, and the installation now stops when a TWRP install fails.
- **A Dot that keeps restarting after the second install.** The installation no longer installs the image into the second slot. A Dot that booted it from slot B kept restarting while slot A with the same image worked, so the image now goes into slot A only.
- **Joining a Wi-Fi network with spaces in its name.** The `wifi connect` command in the docs now wraps the whole command in double quotes. Without them, `adb shell` split a Wi-Fi name or password with spaces into separate words.
- **Build tests.** `make test` passes again. The tests now know all 37 framework patches and the wake word service, look for the countdown command in the device command guide and say to set `BISCUIT_WORKSPACE` when they need the CM14.1 checkout.

## 2026.10.2 - 2026-10-18

### Added
- **Volume buttons for a Music Assistant group.** Kiosk Satellite can now take over the Dot's volume buttons, so they change the volume of the Music Assistant group the Dot plays in, or of a player it follows, instead of the Dot's own. Set **Volume buttons control the player** to **While the player is playing** under Media Player in Kiosk Satellite. The buttons go back to the Dot's own volume when the Dot plays alone or Kiosk Satellite stops, and `biscuit_service volume up` and `down` always change the Dot's own volume. Needs a Kiosk Satellite version newer than 2026.10.29.

## 2026.10.1 - 2026-10-18

The first release, built on [hkfuertes' CM14.1 port](https://github.com/hkfuertes/amazon_device_biscuit).

### Added
- **Wake word detection over loud music.** The image reads all seven microphones and removes the speaker's sound from them while music plays, so the wake word works with music at 100% volume.
- **A louder microphone.** The microphone preamp goes from 20 dB to 36 dB.
- **Automatic Kiosk Satellite installation.** On first boot the latest Kiosk Satellite release is downloaded, installed, given every permission and made the device owner.
- **The Action button as a broadcast.** Newer Kiosk Satellite versions no longer need an accessibility service to receive the Action button.

### Changed
- **Less CPU at idle.** SurfaceFlinger no longer retries a framebuffer the Dot does not have, two log floods are gone, all four cores stay online and there is no boot animation.
- **More free memory and disk space.** SystemUI, the phone process, LiveDisplay, the Android System WebView and nearly 30 unused apps and services are left out. Swap on zram works and apps get the standard Dalvik heap settings for 512 MB devices.
- **Steadier Wi-Fi between kiosks.** Wi-Fi power saving is off, so wake word arbitration broadcasts between kiosks arrive.

### Fixed
- **Light ring strobing.** The light ring no longer strobes while Kiosk Satellite animates it, and it goes back to Kiosk Satellite's colors after the volume overlay.
- **Speaker crackle.** The speaker no longer crackles on the first playback after boot.
