# Unlocking the Echo Dot

The image installs from TWRP, which needs an unlocked bootloader. Use [firebreak](https://github.com/bboe/firebreak) to unlock the Echo Dot (2nd generation) over USB with amonet v2.0.0, the version this image needs. It installs TWRP 3.7.0_9-0 in the same run.

> [!IMPORTANT]
> Do not set up the Dot in the Alexa app before you unlock it. If it gets on Wi-Fi, it can update itself to a Fire OS build firebreak does not support.

## What you need

- The Echo Dot (2nd generation), its power adapter and a micro USB cable that carries data.
- A computer with `adb` and `fastboot` from Android's platform-tools, and [uv](https://docs.astral.sh/uv/), which runs firebreak.

## Run firebreak

Pick your system and run its commands. They install the tools and start firebreak with the amonet v2.0.0 target. Without that target name, firebreak installs amonet v1.1.0, which this image does not support.

**Linux** (Debian and Ubuntu). Run firebreak without `sudo`:

```sh
sudo apt install adb fastboot curl
curl -LsSf https://astral.sh/uv/install.sh | sh
uvx firebreak@latest amonet-biscuit-v2.0.0
```

**macOS** (with [Homebrew](https://brew.sh)):

```sh
brew install --cask android-platform-tools uv
uvx firebreak@latest amonet-biscuit-v2.0.0
```

**Windows** (in PowerShell, opening a new terminal after the installs):

```powershell
winget install Google.PlatformTools
winget install astral-sh.uv
uvx --managed-python firebreak@latest amonet-biscuit-v2.0.0
```

firebreak tells you what to do with the Dot as it goes. It first asks for the fastboot gesture: unplug the USB cable, press and hold the Action button (the one with a dot), plug the cable back in and let go when the light ring turns green. If the ring stays solid blue, the USB connection is probably bad, so unplug it and try again or use another port.

The run takes several minutes. Do not unplug the Dot while it works. If it stops, run the same command again and it picks up where it left off. It ends with the Dot on amonet v2.0.0 with TWRP 3.7.0_9-0, running a rooted Fire OS 6. On the way, firebreak opens your browser to download `boot-root.zip` from the amonet XDA thread for that last step.

On Windows, some steps need MediaTek's VCOM driver. If the Dot shows no light at all, its test point has to be shorted. firebreak's [README](https://github.com/bboe/firebreak#run-it) covers both, and how to ask for help if a run fails.

## Next

The Dot is ready for the image. [Getting into TWRP](twrp.md) covers starting TWRP and checking its version, and the [README](../README.md#installing) covers the installation.
