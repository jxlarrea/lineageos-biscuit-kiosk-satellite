# Building the CM14.1 Biscuit Images

> [!WARNING]
> **Amonet Biscuit v2.0.0 is required to install either generated OTA on a Biscuit.** The images target its TWRP 3.7.0_9-0 native A/B contract. v2 uses a Preloader exploit, removes GPT remapping and `lk-payload`, supports Fire OS 6 only, and intentionally removes stock non-hacked fastboot. Building does not require a connected device, but installation must not use stock recovery, stock fastboot, Amonet v1 instructions, or `boot_a_x` paths. See [Unlocking the Echo Dot](unlocking.md) and [Getting into TWRP](twrp.md) first.

This guide describes the two reproducible CM14.1 products in this repository:

| Product | Lunch target | Make target | What it is |
| --- | --- | --- | --- |
| Full | `cm_biscuit-userdebug` | `make full` | Full Android/CM14.1 with the Android framework and Biscuit hardware integration. |
| Minimal | `biscuit_minimal-userdebug` | `make minimal` | Framework-free Android-shaped userspace for root ADB, Wi-Fi provisioning, DHCP/DNS, raw hardware access, and system add-ons. |

The minimal image intentionally contains no APKs and no `/system/framework` entries. It is not a reduced full Android image.

## Prerequisites

- A Linux host with Git, Docker, Python 3, `repo`, `curl`, `sha256sum`, and enough disk space for the CM14.1 checkout, downloads, outputs, and ccache.
- The repository checkout at its top level.
- Network access on the first sync/build so tracked scripts can obtain the pinned source archives and Fire OS inputs.
- For installation only: a Biscuit updated to **Amonet Biscuit v2.0.0** and booted into TWRP 3.7.0_9-0. See [Unlocking the Echo Dot](unlocking.md).

The supported build images are created once when needed:

```sh
docker image inspect cm14.1-ubuntu20:latest >/dev/null 2>&1 || \
  docker build -t cm14.1-ubuntu20:latest \
    -f docker/cm14.1-ubuntu20.Dockerfile docker/

docker image inspect biscuit-kernel-builder:latest >/dev/null 2>&1 || \
  docker build -t biscuit-kernel-builder:latest \
    -f docker/biscuit-kernel-builder.Dockerfile docker/
```

## Workspace location

The checkout, downloads, extracted Fire OS images, build output and ccache live in `workspace/` inside the repository by default, and take tens of GB. To keep them elsewhere, such as a larger disk, set `BISCUIT_WORKSPACE` for every command:

```sh
export BISCUIT_WORKSPACE=/mnt/dev/amazon_device_biscuit/workspace
scripts/sync.sh
make full
```

The build container mounts that path too.

## Amazon's wake word models

Pryon and the en-US Alexa model come from the Fire OS OTA like the other blobs. The other wake words and locales come from Amazon's DAVS, which hands them out only to an Echo registered to an Amazon account, so the build cannot download them. They live in the private [amazon-davs-models](https://github.com/jxlarrea/amazon-davs-models) repository, one folder per set. Check it out next to this repository, or set `DAVS_MODELS` to where it is. The build checks every file against `vendor/amazon/mt8163-common/biscuit-davs-model-files.txt` before it installs them under `/system/etc/pryon`. `device/amazon/biscuit/pryon/locales.txt` names the sets each locale listens with.

To refresh them, fetch the sets again with that repository's `fetch.py` from a registered Dot running Fire OS, then rewrite the manifest:

```sh
scripts/make-davs-model-manifest.py
```

## One-time source synchronization

```sh
scripts/sync.sh
```

This creates or updates the ignored `workspace/cm14.1` checkout using the tracked manifests. Do not make manual changes there: `scripts/stage-tree.sh` reconstructs the active overlay, proprietary closure, patch state, and Fire OS kernel source from tracked files.

## Build the full image

```sh
make full
docker logs -f cm14.1-biscuit-build
```

`make full` selects:

```txt
LUNCH_TARGET=cm_biscuit-userdebug
PATCH_PROFILE=full
```

The build script stages the flat Biscuit overlay, applies every patch in `patches/full/` in filename order, extracts the full verified Fire OS vendor closure, stages the Fire OS 6 Biscuit kernel, applies every patch in `patches/kernel/` in filename order, and starts the detached `cm14.1-biscuit-build` container.

The full product includes the Android framework, framework Wi-Fi/Bluetooth/audio paths, BiscuitService, the native LED daemon, headless-display compatibility, proprietary audio/radio/Bluetooth blobs, and the full patch profile.

## Build the framework-free minimal image

```sh
make minimal
docker logs -f cm14.1-biscuit-build
```

`make minimal` selects:

```txt
LUNCH_TARGET=biscuit_minimal-userdebug
PATCH_PROFILE=minimal
CLEAN_BISCUIT_OUT=1
```

The clean product-output step is deliberate: an incremental switch from the full product could otherwise leave full-framework files in the minimal system image. The build stages only the framework-free rootfs and the radio/Wi-Fi vendor closure, applies `patches/minimal/` in filename order plus the common kernel patches, and starts the same detached build container.

The minimal product supplies root USB/TCP ADB, `wpa_connect`, `wpa_passphrase`, `wpa_supplicant`, DHCP, `netd` DNS proxying, CA certificates, shell/network/debug tools, raw audio tools, and the replaceable `ledcontroller` service slot. It deliberately excludes the Android framework, APKs, Java BiscuitService, and Bluetooth framework/audio stack.

## Switching products safely

Always use `make full` or `make minimal`; do not invoke a patch file manually. `scripts/stage-tree.sh` records the active profile and, when it changes, resets known generated upstream files, reverses the previous profile where necessary, and reapplies the selected profile fuzz-free.

Useful staging-only commands are:

```sh
make stage          # stage the full profile without building
make stage-minimal  # stage the minimal profile without building
make test           # static patch, product, kernel, Amonet 2, and OTA checks
```

## Artifacts and preflight

Both products write below:

```txt
workspace/cm14.1/out-docker/target/product/biscuit/
```

The full build normally produces a `cm_biscuit-ota-*.zip`; the minimal build normally produces a `biscuit_minimal-ota-*.zip`. Treat those names as build output, not a stable release API: inspect the directory after each successful build.

Before any installation, verify the generated updater. A safe Biscuit custom OTA:

- writes only `/dev/block/current-system` and `/dev/block/current-boot`;
- has no `dd`, manual BCB mutation, `boot_a_x`, or stale unsuffixed boot/system target;
- has no userdata/cache/recovery image or wipe command;
- uses the Amonet 2 current-slot assertion contract.

Install from TWRP only, into both slots and slot A first, as the [README](../README.md#installing) describes. The bootloader always loads `boot_a`, whatever amonet's BCB in `/misc` says: with slot B active and marked successful, a Dot ran slot A's kernel. The kernel drops the bootloader's `androidboot.slot_suffix` (`CONFIG_CMDLINE_FORCE`), so fs_mgr picks the slot from that BCB, which `bcbtool set_active` writes. A Dot booted with slot B active runs `boot_a` with `system_b`.

## Publishing a release

The full build stamps `ro.biscuit.release` with the newest heading in `CHANGELOG.md`. While that heading is `Unreleased`, it stamps the release before it with `-dev` after it, such as `2026.10.3-dev`. `BISCUIT_RELEASE` overrides it. So rename the `Unreleased` heading to the release before the build that gets published. A Dot only installs a release whose `system/build.prop` says the same version as its GitHub tag.

Then sign the zip and upload the `.sig` next to it:

```sh
scripts/sign-release.sh lineageos-biscuit-kiosk-satellite-<version>.zip
```

The script signs with the private key in `~/.config/biscuit-ota/release-key.pem` or `BISCUIT_OTA_KEY` and checks the signature against `device/amazon/biscuit/biscuit-service/ota/release-key.pem`, the public key the image ships. Dots only install a release that has a valid `.sig`. A release without one has to be installed by hand. Keep a backup of the private key. Without it, no new release installs on its own until the Dots get an image with a new public key by hand.

### Testing an update before publishing it

A Dot can take its releases list from somewhere other than GitHub, such as a web server on your computer. Copy the GitHub API's answer for the repository's releases into a `releases.json`, point the asset URLs at the signed zip and its `.sig` on that server and set the property:

```sh
adb shell setprop persist.biscuit.ota.releases http://<computer>:<port>/releases.json
```

The Dot still checks the signature and the version in the zip. `adb shell setprop persist.biscuit.ota.releases ''` goes back to GitHub.

## Patch application model

Patch names are numbered because their order is part of the build contract. `scripts/apply-patches.sh` applies every `*.patch` in the selected directory lexically, fuzz-free, and idempotently. Shared patches are intentionally duplicated between `patches/full/` and `patches/minimal/` because the selected profile must be independently reproducible.

### Kernel patches applied to both products

| Patch | What it does |
| --- | --- |
| `010-netfilter-xt-compat-percpu.patch` | Avoids zeroing per-CPU iptables entry pointers that the MTK 3.18 allocation path already initializes, preserving iptables/ip6tables table setup. |
| `020-force-ramdisk-root.patch` | Forces the known-good `root=/dev/ram rdinit=/init` kernel command line and ignores the unsafe Fire OS bootloader root/dm-verity command line that would otherwise panic before Android init. |
| `030-filter-bootloader-cmdline.patch` | Under forced root, copies only safe FDT boot arguments (`androidboot.serialno`, `androidboot.bootreason`, and `boot_reason`) so Android receives the real serial without reintroducing `root=`, `dm=`, or a stale slot suffix. |

### Full-product patches (`patches/full/`)

| Patch | What it does |
| --- | --- |
| `001-amonet-fstab.patch` | Converts the MT8163 runtime fstab to the Amonet 2 bootdevice paths and `slotselect` contract for system and boot. |
| `002-amonet2-bcb-slotselect.patch` | Adds the Amonet 2 `/misc+0x360` BCB fallback to `fs_mgr` when `ro.boot.slot_suffix` is absent. |
| `003-skip-unused-ota-images.patch` | Lets the product skip cache and userdata image generation, reducing build work and unused OTA payload metadata. |
| `004-amazon-log-shim.patch` | Exports Amazon's `lab126_log_write` compatibility symbol from `liblog` for proprietary MT8163 display components. |
| `005-audio-legacy-symbols.patch` | Exports the remaining legacy logging/smart-pointer compatibility symbols required by the original Fire OS Amazon audio HAL closure. |
| `006-headless-system-props.patch` | Sets Biscuit headless properties and prevents selection of the unavailable Mali gralloc path. |
| `007-headless-no-gpu-property.patch` | Sets `ro.config.no_gpu=true` so framework and display patches take the headless path. |
| `008-mt8163-wifi-interface-property.patch` | Declares `wifi.interface=wlan0`, preventing the framework from cycling the working MTK Wi-Fi interface. |
| `009-bluetooth-board-cflags.patch` | Provides Biscuit-specific Bluedroid board CFLAGS, including the no-input pairing capability. |
| `010-biscuit-bluetooth-noinput-pairing.patch` | Disables the numeric-comparison callback path when Biscuit advertises no local input capability. |
| `011-biscuit-bluetooth-noinput-prototype.patch` | Guards the corresponding callback prototype and definition so the no-input Bluetooth build remains warning-clean. |
| `012-biscuit-bluetooth-headless-speaker.patch` | Enables A2DP Sink and AVRCP Controller behavior, automatic SSP confirmation/classic PIN handling, and sink connection priority for a headless speaker. |
| `013-biscuit-disable-pan-profile.patch` | Disables Bluetooth PAN/NAP, which is not part of the Biscuit speaker role. |
| `014-insecure-adb-default-props.patch` | Supports an explicitly requested root, unauthenticated ADB configuration for headless userdebug bring-up. |
| `015-biscuit-hostname-mdns.patch` | Derives a stable Biscuit hostname from model/serial data, passes it to `mdnssd`, and fixes the mDNS hostname length boundary. |
| `016-biscuit-flac-decoder.patch` | Adds and registers `OMX.google.flac.decoder`, its software FLAC library, and the required ACodec compatibility behavior. |
| `017-software-egl-fallback.patch` | Falls back to source-built software GLES when a proprietary EGL driver is unavailable. |
| `018-hwui-egl-config-fallback.patch` | Makes HWUI try a basic ES2/window EGL configuration before treating missing vendor configuration as fatal. |
| `019-headless-hwui-disable.patch` | Disables GPU/HWUI-dependent package and rendering behavior when `ro.config.no_gpu=true`. |
| `020-headless-hwc1-fake-display.patch` | Gives SurfaceFlinger a fake 1x1 primary display/no-op HWC path so full Android can boot without a framebuffer device. |
| `021-biscuit-radio-launchers.patch` | Starts the Fire OS 32-bit `wmt_loader` and `wmt_launcher`, applies MTK device-node permissions, and initializes the Biscuit radio stack. |
| `022-biscuit-sta-only-wifi.patch` | Removes unneeded AP, P2P, WPS, Wi-Fi Display, interworking, and related supplicant/framework paths for Biscuit STA operation. |
| `023-biscuit-mic-mute.patch` | Adds Biscuit microphone-mute key/service/broadcast handling so framework mute requests and the Biscuit control surface share state. |
| `024-biscuit-disable-framework-p2p.patch` | Explicitly reports Wi-Fi Direct/P2P as unsupported on Biscuit even when generic framework feature discovery would enable it. |
| `025-amazon-audio-wrapper.patch` | Builds the MT8163 primary-audio wrapper and compatibility shims around the original Fire OS Amazon audio HAL. |
| `026-biscuit-audio-route-wrapper.patch` | Adds the proven TLV320 baseline speaker route and controls the external amplifier around output activity. |
| `027-biscuit-audio-route-forwarding.patch` | Correctly forwards full audio HAL/device/stream ABI calls to the real Fire OS objects while retaining only the route/amplifier interception. |
| `028-biscuit-audio-gpio-mic-mute.patch` | Lets audioserver access the Amazon GPIO87 mute path and preserves/report the real hardware microphone-mute state. |
| `029-biscuit-zram-lzo.patch` | Sizes zram at 256 MB with `lzo`. Swap never started upstream: the kernel lacks `zstd` and the 805 MB it asked for exceeded the RAM. |
| `030-biscuit-action-button-broadcast.patch` | Broadcasts every Action button press and release from `PhoneWindowManager`, also while the device sleeps, so Kiosk Satellite needs no accessibility service. `ro.biscuit.action_broadcast` advertises it. The key still reaches apps for older Kiosk Satellite versions. |
| `031-biscuit-speaker-amp-after-codec.patch` | Turns the speaker amplifier on after the first write and off before standby, ported from meiser79's LineageOS 18.1 tree, so the first playback after boot no longer crackles. |
| `032-headless-framebuffer-surface-usage.patch` | Stops SurfaceFlinger from asking for a framebuffer buffer. With no framebuffer device every composition failed and was retried, at about 5% of a core and 110 log lines a second. |
| `033-biscuit-wifi-power-save-off.patch` | Keeps Wi-Fi power save off unless `persist.biscuit.wifi_powersave` is 1. With it on, about one broadcast in five never arrived. |
| `034-biscuit-drop-asp-pipeline-log.patch` | Drops the audio HAL's "asp Pipeline doesn't exist" error in `liblog`, logged about 75 times a second during playback because Amazon's audio processor never starts. |
| `035-biscuit-speaker-highpass-limiter.patch` | Adds the speaker high-pass filter (`persist.biscuit.spk_hpf_hz`) and peak limiter (`persist.biscuit.spk_limiter`), both off. With them on the wake word did slightly worse over loud music. |
| `036-biscuit-mic-array-speaker-null.patch` | Reads all seven microphones plus the speaker reference on channel 8, learns per frequency how the speaker reaches each microphone and removes it from microphone 0 while the speaker plays (`hardware/amazon/audio/mic_beam.c`). That is 13 to 17 dB less music and about 1 dB less voice above 1.2 kHz. `persist.biscuit.mic_beam 0` turns it off. |
| `037-biscuit-volume-button-claim.patch` | Marks volume button presses from the hardware so BiscuitService can hand them to the app that claimed them through `claimVolumeButtons`, as `VOLUME_BUTTON` broadcasts. The claim ends with the app's token. `ro.biscuit.volume_claim` advertises it. |
| `038-biscuit-adbd-tcp-reconnect.patch` | Gives each Wi-Fi ADB connection its own transport and probes idle ones with TCP keepalives, so a connection the host dropped without closing no longer blocks every later `adb connect`. |

### Other image changes

These live in the build scripts and in the device tree under `device/amazon/biscuit/` rather than in patches.

| Where | What it does |
| --- | --- |
| `scripts/extract-fireos6-blobs.sh` | Raises the microphone preamp from 40 to 72 (20 dB to 36 dB). Fire OS left the rest of the gain to Amazon's audio processor, which never starts on this build. |
| `rootdir/ks-install.sh` | Installs the latest Kiosk Satellite release's ABI split on first boot with every grant and device owner. The grants are applied again on every boot. `persist.biscuit.ks_install 0` turns it off. |
| `biscuit-service/biscuit-ledd.cpp` | The light ring daemon. `FRAME` no longer blanks the ring first, which strobed at 20 frames a second. The volume overlay restores the last client frame. |
| `biscuit-service/biscuit-pryond.cpp`, `pryon/locales.txt` | Amazon's wake word engine as a service on the `biscuit-pryon` socket. Pryon's libraries and the en-US Alexa model come from the Fire OS 6.5.7.4 OTA, 29 more model sets from Amazon's DAVS through amazon-davs-models. The build lets STOP count without "Alexa" first, accepted from 0.18. It uses about 15 MB and 28% of one core while listening. `ro.biscuit.pryon` advertises it. |
| `biscuit-service/service/` | BiscuitService: the Wi-Fi, Bluetooth, volume and microphone commands of `biscuit_service`, the light ring binder, the volume button claim and system updates (`SystemUpdate.java`, `ota/`). `ro.biscuit.ota` advertises updates and `ro.biscuit.release` carries the release. |
| `sensors/sensors_biscuit.c` | Falls back to a TSL2540 light sensor on boards without a TSL2584, backported from meiser79's CM14.1 fork. Untested, since this Dot has a TSL2584. |
| `rootdir/init.device.rc` | Keeps all four cores online, since MediaTek's hotplug daemon parked and unparked them every second or two and Kiosk Satellite counted parked time as busy. Stops perfprofd after boot. |
| `device.mk` | No boot animation, which crashed dividing by zero on the 1x1 display. The Dalvik heap settings for 512 MB devices, `ro.config.low_ram` and at most 8 cached processes. |
| `empty-launcher/Android.mk`, `overlay/` | Leaves out SystemUI, the wallpaper service, LiveDisplay, WebView, telephony and the unused apps. StatementService stays because the package manager requires it. |

### Minimal-product patches (`patches/minimal/`)

| Patch | What it does |
| --- | --- |
| `001-amonet2-bcb-slotselect.patch` | Adds the same Amonet 2 BCB slot fallback needed by the framework-free init/fstab path. |
| `002-skip-unused-ota-images.patch` | Avoids cache/userdata image generation for the minimal product. |
| `003-insecure-adb-default-props.patch` | Provides the explicit root, unauthenticated ADB properties used by the minimal headless system. |
| `004-sta-only-wpa-supplicant.patch` | Builds a small STA-only supplicant by disabling WPS, AP, P2P, Wi-Fi Display, HS20, interworking, and their unsupported control paths. |
| `005-wpa-passphrase.patch` | Exposes CM14's existing `wpa_passphrase.c` as the reproducibly built `/system/bin/wpa_passphrase` utility. |
| `006-sepolicy-exfat-ntfs-types.patch` | Defines the exFAT and NTFS file types otherwise supplied by CM common sepolicy, which minimal deliberately does not inherit. |
| `007-framework-free-systemimage-trim.patch` | Filters framework/default/debug/recovery leftovers from the minimal system image while retaining its explicit runtime manifest. |
| `008-adbd-tcp-reconnect.patch` | Gives each Wi-Fi ADB connection its own transport and probes idle ones with TCP keepalives, so a connection the host dropped without closing no longer blocks every later `adb connect`. |

## Static validation

Run before treating a build as ready for preflight:

```sh
make test
git diff --check
```

The test suite checks ordered, fuzz-free patch application; both product contracts; minimal-product exclusions; Amonet 2 slot handling; OTA paths; kernel command-line handling; and LED behavior. It does not replace inspecting the actual generated OTA before a device installation.
