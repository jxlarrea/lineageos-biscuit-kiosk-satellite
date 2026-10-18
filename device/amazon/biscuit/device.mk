LOCAL_PATH := $(call my-dir)

# Use the CM14.1 MT8163 common tree; keep Biscuit additions native/minimal.
$(call inherit-product, device/amazon/mt8163-common/mt8163-common.mk)

# Headless HOME plus explicit removal of inherited screen apps.
# ponytail: LOCAL_OVERRIDES_PACKAGES is not enough for this CM14 product inheritance chain.
BISCUIT_NO_SCREEN_PACKAGES := \
    AudioFX \
    BasicDreams \
    Browser \
    Browser2 \
    Calculator \
    Calendar \
    Camera2 \
    CMFileManager \
    CMWallpapers \
    CMUpdater \
    CyanogenSetupWizard \
    DeskClock \
    Development \
    Eleven \
    Email \
    ExactCalculator \
    Exchange2 \
    Gallery2 \
    Jelly \
    Launcher2 \
    Launcher3 \
    LineageSetupWizard \
    LiveWallpapersPicker \
    LockClock \
    PhotoTable \
    PrintSpooler \
    SetupWizard \
    Terminal \
    ThemeChooser \
    Trebuchet \
    Updater \
    WallpaperCropper \
    WallpaperPicker
PRODUCT_PACKAGES := $(filter-out $(BISCUIT_NO_SCREEN_PACKAGES),$(PRODUCT_PACKAGES))
PRODUCT_PACKAGES += \
    BiscuitEmptyLauncher

# FireOS 6 ships this software driver on its headless Biscuit product; build ours from source.
PRODUCT_PACKAGES += \
    audio.primary.mt8163 \
    audio_effects.conf \
    libGLES_android \
    libstagefright_soft_flacdec \
    libtinyalsa \
    libtinyalsa_shim \
    libtinycompress \
    sensors.mt8163 \
    biscuit_audiotrack_test \
    biscuit_audiorecord_test \
    biscuit_asp_beam_probe \
    biscuit_mic_test \
    tinymix \
    tinyplay \
    tinycap \
    tinypcminfo

# Replace inherited generic effects config with Biscuit's AOSP/WebRTC AGC config.
PRODUCT_COPY_FILES_OVERRIDES += \
    system/etc/audio_effects.conf

# Native LED ring controller plus framework bridge for shell volume/mute/Wi-Fi/BT commands.
PRODUCT_PACKAGES += \
    biscuit-ledd \
    biscuit-ledctl \
    i2c-poke \
    biscuit_service \
    BiscuitService

PRODUCT_COPY_FILES += \
    device/amazon/biscuit/rootdir/init.device.rc:root/init.device.rc \
    device/amazon/biscuit/audio/audio_init.sh:$(TARGET_COPY_OUT_SYSTEM)/etc/audio_init.sh \
    device/amazon/biscuit/wpa_supplicant_overlay.conf:$(TARGET_COPY_OUT_SYSTEM)/etc/wifi/wpa_supplicant_overlay.conf \
    device/amazon/biscuit/biscuit-service/animations/volume.animation:$(TARGET_COPY_OUT_SYSTEM)/etc/biscuit-ledd/volume.animation \
    device/amazon/biscuit/biscuit-service/animations/solid_blue.animation:$(TARGET_COPY_OUT_SYSTEM)/etc/biscuit-ledd/solid_blue.animation \
    device/amazon/biscuit/biscuit-service/animations/solid_green.animation:$(TARGET_COPY_OUT_SYSTEM)/etc/biscuit-ledd/solid_green.animation \
    device/amazon/biscuit/biscuit-service/animations/solid_cyan.animation:$(TARGET_COPY_OUT_SYSTEM)/etc/biscuit-ledd/solid_cyan.animation \
    device/amazon/biscuit/biscuit-service/animations/alexa_thinking.animation:$(TARGET_COPY_OUT_SYSTEM)/etc/biscuit-ledd/alexa_thinking.animation \
    device/amazon/biscuit/biscuit-service/animations/boot-complete-green.animation:$(TARGET_COPY_OUT_SYSTEM)/etc/biscuit-ledd/boot-complete-green.animation

PRODUCT_CHARACTERISTICS := nosdcard,headless

# Kiosk Satellite Edition.
PRODUCT_PACKAGES += \
    curl

PRODUCT_COPY_FILES += \
    device/amazon/biscuit/rootdir/ks-install.sh:$(TARGET_COPY_OUT_SYSTEM)/etc/ks-install.sh

PRODUCT_PROPERTY_OVERRIDES += \
    ro.biscuit.action_broadcast=1
