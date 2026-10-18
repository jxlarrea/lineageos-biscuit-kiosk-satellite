# Kiosk Satellite Edition

A CM14.1 Biscuit build tuned for Kiosk Satellite running headless: a voice satellite, intercom and speaker for Home Assistant on a 512 MB Echo Dot. Built on the `kiosk-satellite` branch of this repository.

## Done

### Audio and the light ring

| Change | Where | Why |
| --- | --- | --- |
| Microphone preamp 40 to 72 (20 dB to 36 dB) | `scripts/extract-fireos6-blobs.sh` | Fire OS relies on Amazon's audio processor for the rest of the gain, which never starts on this build. Speech was about 20 dB too quiet for calls. |
| Speaker amplifier switched with the codec | `patches/full/031` | Ported from meiser79's LineageOS 18.1 tree: the amplifier comes on after the first write and goes off before standby, so the first playback after boot no longer crackles. |
| `FRAME` no longer blanks the ring first | `biscuit-ledd.cpp` | A client animating at 20 frames a second strobed. |
| The volume overlay restores the last client frame | `biscuit-ledd.cpp` | The ring used to go dark after the overlay until the client repainted. |
| Speaker removed from the microphone array | `patches/full/036`, `hardware/amazon/audio/mic_beam.c` | The codec delivers all seven microphones plus the speaker signal (channel 8, on the microphones' clock), but the Fire OS HAL hands Android microphone 0 alone. At 90% volume the speaker reached the microphones about 20 dB above a voice, much of it distortion no echo canceller can model, and the wake word failed from about 75% up. The wrapper now reads the array itself, learns per frequency how the speaker reaches each microphone from channel 8, and removes that pattern from microphone 0 while the speaker plays: 13 to 17 dB less music, about 1 dB less voice above 1.2 kHz. The wake word now works with music at 100%. In a quiet room the output is microphone 0 unchanged. `persist.biscuit.mic_beam 0` turns it off. |
| Speaker high-pass filter and limiter, off by default | `patches/full/035` | Fire OS shaped the output for the small driver in Amazon's audio processor, which never starts on this build. `persist.biscuit.spk_hpf_hz` sets a high-pass cutoff and `persist.biscuit.spk_limiter 1` turns on a peak limiter. In listening tests with the microphone array removing the speaker, the wake word did slightly worse over loud music with them on, and the high frequencies sounded harsher, so both ship off. Before the array, the limiter made the wake word fail over music at 75% and up. |
| TSL2540 light sensor fallback | `sensors_biscuit.c` | Backported from meiser79's CM14.1 fork for boards with a TSL2540 instead of a TSL2584. Untested here: this unit has a TSL2584. |

### Kiosk Satellite

| Change | Where | Why |
| --- | --- | --- |
| First-boot Kiosk Satellite installer | `rootdir/ks-install.sh` | Downloads the latest release's ABI split (the same file the in-app updater picks), installs it, starts it, and applies every grant and device owner. Grants are reapplied on every boot. `setprop persist.biscuit.ks_install 0` turns it off. |
| Action button broadcast from `PhoneWindowManager` | `patches/full/030` | Kiosk Satellite no longer needs an accessibility service or a wake lock to hear the button. `ro.biscuit.action_broadcast` advertises it. The key still reaches apps for older Kiosk Satellite versions. |

### Idle CPU and logging

| Change | Where | Why |
| --- | --- | --- |
| SurfaceFlinger no longer asks for a framebuffer buffer | `patches/full/032` | There is no framebuffer device, so every composition failed and was retried. SurfaceFlinger used about 5% of a core and logged about 110 lines a second. |
| Fake display at 1 fps instead of 60 | `patches/full/020` | Fewer compositions on a display nothing reads. |
| No boot animation | `device.mk` | It crashed dividing by zero on the 1x1 display. Boot completes in under a minute without it. |
| Kernel command line without `initcall_debug` and with `loglevel=4` | `patches/kernel/020` | Less kernel logging. |
| perfprofd stopped after boot | `init.device.rc` | The profiling daemon only collects for Google's internal builds. |
| The audio HAL's "asp Pipeline doesn't exist" error dropped in liblog | `patches/full/034` | The HAL calls Amazon's audio processor for every playback buffer, and the processor never starts on this build. It logged about 75 lines a second while anything played. |

### Memory

| Change | Where | Why |
| --- | --- | --- |
| zram with `lzo`, 256 MB | `patches/full/029` | The kernel lacks `zstd`, and 805 MB exceeded the RAM, so swap never started. |
| No SystemUI, wallpaper service off | `empty-launcher/Android.mk`, `overlay/` | No status bar, navigation bar, keyguard or volume dialog to draw. Android treats the missing keyguard as a device without one. |
| No LiveDisplay | `overlay/vendor/cmsdk` | It tunes a screen the device does not have, and it crashed the system at boot without SystemUI. |
| No WebView | `empty-launcher/Android.mk` | Kiosk Satellite builds no UI on a headless device and its plugins are native code, so nothing draws a web page. Signing in to a captive Wi-Fi portal needs a screen anyway. 80 MB of `/system`. |
| No telephony | `empty-launcher/Android.mk`, `overlay/vendor/cmsdk` | The phone process, Telecom and the telephony, contacts and blocked number providers. The device already had no radio (`ro.radio.noril`). Bluetooth can no longer offer the headset (HFP) profile, which needs a phone. |
| Debloat | `empty-launcher/Android.mk` | Calendar, contacts, email, gallery, browsers, camera, music, keyboard, file manager, recorder, AudioFX, updater, weather, wallpapers, TTS, print, backup and test apps. StatementService stays: the package manager requires it. |
| Dalvik heap preset for 512 MB | `device.mk` | Without it every app, system_server included, got ART's 16 MB default heap limit. |
| `ro.config.low_ram=true`, at most 8 cached processes | `device.mk` | Fewer cached processes on a 512 MB device. |

### Network

| Change | Where | Why |
| --- | --- | --- |
| Wi-Fi power save off | `patches/full/033` | With power save on, about one broadcast in five never arrived and the rest waited for the next DTIM beacon. Kiosks pick which one answers a wake word over broadcasts. `setprop persist.biscuit.wifi_powersave 1` turns it back on. |

## Measured on the Dot, idle with Kiosk Satellite connected

| Build | Used RAM | Free RAM | Idle CPU outside Kiosk Satellite |
| --- | --- | --- | --- |
| First debloat build | 322 MB | 173 MB | SurfaceFlinger 5%, logd 1% |
| SurfaceFlinger fix | 322 MB | 173 MB | under 1% each |
| Without SystemUI | 295 MB | 190 MB | under 1% each |
| Without telephony | 279 MB | 207 MB | under 1% each |
| Low RAM settings | 272 MB | 214 MB | under 1% each |

Kiosk Satellite itself used 1.7% of one core idle, measured per thread over a minute.

## Kept as upstream ships it

- Network adb on port 5555 with no authentication: a headless device is maintained over the network.

