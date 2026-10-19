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

Install from TWRP only, into slot A, as the [README](../README.md#installing) describes. Booting the image from slot B has not worked on a user's Dot. The kernel drops the bootloader's `androidboot.slot_suffix` (`CONFIG_CMDLINE_FORCE`), so fs_mgr picks the slot from amonet's BCB in `/misc` instead.

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

## Static validation

Run before treating a build as ready for preflight:

```sh
make test
git diff --check
```

The test suite checks ordered, fuzz-free patch application; both product contracts; minimal-product exclusions; Amonet 2 slot handling; OTA paths; kernel command-line handling; and LED behavior. It does not replace inspecting the actual generated OTA before a device installation.
