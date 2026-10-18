# Kiosk Satellite Edition

A CM14.1 Biscuit build tuned for Kiosk Satellite running headless: a voice satellite, intercom and speaker for Home Assistant on a 512 MB Echo Dot. Built on the `kiosk-satellite` branch of this repository.

## Done

| Change | Where | Why |
| --- | --- | --- |
| Microphone preamp 40 to 72 (20 dB to 36 dB) | `scripts/extract-fireos6-blobs.sh` | Fire OS relies on Amazon's audio processor for the rest of the gain, which never starts on this build. Speech was about 20 dB too quiet for calls. |
| `FRAME` no longer blanks the ring first | `biscuit-ledd.cpp` | A client animating at 20 frames a second strobed. |
| The volume overlay restores the last client frame | `biscuit-ledd.cpp` | The ring used to go dark after the overlay until the client repainted. |

## Planned for the first build

| Change | Why |
| --- | --- |
| zram with `lzo`, about 256 MB | The kernel lacks `zstd`, and 805 MB exceeds the RAM, so swap never starts. |
| Wi-Fi power save off | Broadcast claims between kiosks arrived 190 to 500 ms late or not at all, and network adb dropped. |
| Fake display at 1 fps instead of 60 | SurfaceFlinger used about 6% of a core drawing a 1x1 display. |
| Network adb on port 5555 by default | A headless device is maintained over the network. |
| Action button broadcast from `PhoneWindowManager` | Kiosk Satellite no longer needs an accessibility service or a wake lock to hear the button. A property advertises it. The key still reaches apps for older Kiosk Satellite versions. |
| First-boot Kiosk Satellite installer | Downloads the latest release's ABI split (the same file the in-app updater picks), installs it, starts it, and applies every grant and device owner. Grants are reapplied on every boot. A property turns it off. |
| Speaker amplifier switched with the codec | Ported from meiser79's LineageOS 18.1 tree: the amplifier comes on after the first write and goes off before standby, so the first playback after boot no longer crackles. |
| TSL2540 light sensor fallback | Backported from meiser79's CM14.1 fork for boards with a TSL2540 instead of a TSL2584. Cannot be tested on a TSL2584 board. |
| Silence the audio HAL's "asp Pipeline doesn't exist" spam | It logs for every playback buffer, costing logd CPU and rotating the log buffer within minutes. |
| Kernel command line without `initcall_debug` and with a lower `loglevel` | Less kernel logging. |
| Remove unneeded MediaTek debug daemons | After listing what runs on the build. |
| Wi-Fi background scanning off | Fewer wakeups on a device that never roams. |
| Debloat: Contacts, Calendar, Email, Gallery, browser, camera, messaging, music, keyboard, file manager, recorder, AudioFX, updater, weather | RAM, boot work and storage. |
| Ahead-of-time compiled system apps | Their compiled code lives in `/system`, not `/data`. |

## After measuring the first build, one at a time

| Change | Why |
| --- | --- |
| Skip SystemUI on a headless build, keyguard disabled through its overlay | Likely the largest RAM saving. |
| Telephony off (`ro.radio.noril`, voice capable off) | The phone process and its providers. |
| `ro.config.low_ram=true`, LMK and Dalvik heap tuned for 512 MB | Fewer cached processes. |
| Speaker distortion above 55% media volume | Find where the output clips and set the mixer so 100% stays clean. |

## Not planned

- Amazon's audio processor (ASP): Kiosk Satellite's WebRTC echo cancellation and noise suppression already cover it.
- Kiosk Satellite preinstalled in the image: it updates too often. The first-boot installer replaces it.
- SwiftShader, su, Magisk and an open-source HWC: not needed headless.
- Removing the WebView provider: captive Wi-Fi portals need it, unless `/system` runs short.

## Baseline on CM14.1 before these changes

Idle: Kiosk Satellite about 15% of one core, SurfaceFlinger about 6%. About 0.2 GB of RAM free, 715 MB free on `/data`.
