# Changelog

All notable changes to LineageOS for the Echo Dot (2nd Gen), Kiosk Satellite Edition are documented here. Images are published on the [releases page](https://github.com/jxlarrea/lineageos-biscuit-kiosk-satellite/releases).

## 2026.10.4 - 2026-10-23

### Added
- **System updates.** The Dot can now update itself. It checks GitHub for a newer release, downloads it and checks its signature, then installs it from TWRP into slot A and, once slot A boots, into slot B. Each slot takes the Dot offline for about a minute and a half. Kiosk Satellite and its settings stay. `biscuit_service update status`, `check` and `install` drive it from adb. Kiosk Satellite can offer it as an update in Home Assistant with a version newer than 2026.10.37. This release itself has to be installed by hand. To test a release before publishing it, `persist.biscuit.ota.releases` points the Dot at another releases list.

### Changed
- **Clearer docs.** The Kiosk Satellite Edition page now covers what the image does for you, the settings you can change and what it leaves out. The README has a new Updating section. The build guide lists every patch and the changes outside them.

### Fixed
- **Wi-Fi ADB stopped answering after a while.** adbd gave every Wi-Fi connection the same name and ignored any new connection while an old one with that name was still open. If the computer went away without closing its connection, for example when its adb server restarted, `adb connect` said it was connected but the Dot showed as offline until it restarted. Each connection now gets its own name. adbd also closes connections that stop answering for about 90 seconds.

## 2026.10.3 - 2026-10-21

### Added
- **Amazon's wake words.** The image now includes Amazon's own wake word engine with its models for Alexa, Echo, Computer, Amazon and Ziggy in 17 locales, from English and Spanish to Japanese and Arabic. Kiosk Satellite can listen the way an Echo does: choose **Amazon** as the wake word engine and the language of its models. Needs a Kiosk Satellite version newer than 2026.10.33. A plain "stop" also stops a ringing timer or a reply, where Amazon's models only heard "stop" right after the wake word.

### Changed
- **Installing into both slots, slot A first.** The Dot's bootloader always starts slot A's kernel, whichever slot is active. A Dot with the image only in slot B started another kernel and kept restarting. The installation now installs into slot A first, checks that it boots, then installs into slot B and checks that too.

### Fixed
- **Getting into TWRP on a Dot that does not boot.** The TWRP guide again says to hold the **+** button while plugging the Dot in, which starts TWRP on amonet v2. A new section covers a Dot that keeps restarting after an install, and the installation now stops when a TWRP install fails.
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
