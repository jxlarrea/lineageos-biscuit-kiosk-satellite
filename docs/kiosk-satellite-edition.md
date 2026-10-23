# Kiosk Satellite Edition

This image turns the Echo Dot (2nd Gen) into a voice satellite, intercom and speaker for Home Assistant, run by [Kiosk Satellite](https://github.com/jxlarrea/kiosk-satellite) with no screen. This page covers what it does differently from a standard LineageOS 14.1 build, the settings you can change over adb and what it leaves out.

## Kiosk Satellite

The Dot installs Kiosk Satellite on its first boot, as soon as it has a network connection. It gives it every permission it needs and makes it the device owner, so Kiosk Satellite updates itself without asking. The permissions are applied again on every boot.

If you want to run the Dot without Kiosk Satellite, turn the installer off:

```sh
adb shell setprop persist.biscuit.ks_install 0
```

## Voice

- **Wake words over loud music.** The Dot has seven microphones. The image uses all of them to remove the speaker's own sound from what Kiosk Satellite hears, so the wake word works with music at full volume. In a quiet room nothing changes.
- **A louder microphone.** The microphone gain is 16 dB higher than on Fire OS's drivers alone, so voices and intercom calls come through at a normal level.
- **Amazon's wake words.** The image includes the wake word engine the Dot shipped with, with models for Alexa, Echo, Computer, Amazon and Ziggy in 17 languages. Choose **Amazon** as the wake word engine in Kiosk Satellite. It runs on the Dot and sends nothing to Amazon. A plain "stop" also stops a ringing timer or a reply.

If you want to hear only the main microphone, for example to compare, turn the speaker removal off and restart the Dot:

```sh
adb shell setprop persist.biscuit.mic_beam 0
```

Kiosk Satellite hears microphone 0. If the Dot barely hears the wake word, one of its microphones may be weak. Stop Kiosk Satellite, since it holds the microphones while it listens, and print the level of each one over 4 seconds:

```sh
adb shell am force-stop me.jxl.kiosk_satellite
adb shell biscuit_mic_test 4
```

Channels 0 to 6 are the microphones and should read within a few dB of each other. Channels 7 and 8 are the speaker and read 0 when nothing plays. If microphone 0 reads far below the rest, pick another microphone and restart the Dot. The speaker removal keeps working with any of them:

```sh
adb shell setprop persist.biscuit.mic_beam_out 6
```

## Buttons and the light ring

- **The Action button** goes straight to Kiosk Satellite, even while the Dot sleeps.
- **The volume buttons** can change the volume of the Music Assistant group the Dot plays in or of a player it follows. Turn this on with **Volume buttons control the player** under Media Player in Kiosk Satellite. `adb shell biscuit_service volume up` and `down` always change the Dot's own volume.
- **The light ring** shows Kiosk Satellite's animations without flickering and goes back to them after the volume overlay.

## Speaker

The speaker no longer crackles on the first sound after a reboot.

The image has a high-pass filter and a limiter for the speaker, both off. Over loud music the wake word did slightly worse with them on and high notes sounded harsher. To try them, set a cutoff in Hz or turn on the limiter and restart the Dot:

```sh
adb shell setprop persist.biscuit.spk_hpf_hz 150
adb shell setprop persist.biscuit.spk_limiter 1
```

## Over the Air (OTA) System updates

The Dot finds, downloads and installs new releases of this image itself. Kiosk Satellite shows them in its remote admin and as a **Firmware** update in Home Assistant. See [System updates](device-commands.md#system-updates).

## Network

- **Wi-Fi power saving is off.** With it on, some messages between kiosks got lost or delayed. Kiosks use those messages to decide which one answers a wake word. The Dot is always plugged in, so it costs little. To turn it back on, run this and restart the Dot:

  ```sh
  adb shell setprop persist.biscuit.wifi_powersave 1
  ```

- **adb works over Wi-Fi** on port 5555 without a password, so a Dot without a screen can always be reached. Anyone on your network can control the Dot this way, so keep it on a network you trust.

## What the image leaves out

A speaker with no screen does not need most of Android. Leaving it out frees memory and storage for Kiosk Satellite:

- **Everything that draws on a screen:** the status bar, lock screen, wallpapers, boot animation and screen color tuning.
- **The web browser engine (WebView).** You cannot sign in to a Wi-Fi network that needs a login page.
- **Phone features.** The Dot cannot act as a Bluetooth headset for calls. It still works as a Bluetooth speaker.
- **Apps a speaker does not use:** calendar, contacts, email, gallery, browsers, camera, music, keyboard, file manager, recorder, the LineageOS updater, weather, text to speech, printing and backup.

## Memory and CPU

With Kiosk Satellite connected and idle, about 270 MB of the Dot's memory is in use. 256 MB of compressed swap gives Android room for more. Android's own services stay under 1% of a core each. All four cores stay online, so the CPU readings in Kiosk Satellite are accurate. Amazon's wake word engine adds about 15 MB and a quarter of one core while it listens.
