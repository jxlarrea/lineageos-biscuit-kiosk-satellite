LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_PACKAGE_NAME := BiscuitEmptyLauncher
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := $(call all-java-files-under, src)
LOCAL_SDK_VERSION := current
LOCAL_CERTIFICATE := platform
# ponytail: Biscuit has no screen; this HOME also keeps inherited UI apps out.
LOCAL_OVERRIDES_PACKAGES := \
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
# Kiosk Satellite Edition: services and apps a headless voice satellite never
# uses. The running ones cost 5 to 15 MB each on a 512 MB device.
LOCAL_OVERRIDES_PACKAGES += \
    BackupRestoreConfirmation \
    BookmarkProvider \
    CalendarProvider \
    CMAudioService \
    Contacts \
    CtsShimPrebuilt \
    CtsShimPrivPrebuilt \
    DocumentsUI \
    DownloadProviderUi \
    EasterEgg \
    HTMLViewer \
    MtpDocumentsProvider \
    OneTimeInitializer \
    perfprofd \
    PicoTts \
    PrintRecommendationService \
    Profiles \
    SharedStorageBackup \
    WallpaperBackup \
    WAPPushManager \
    WeatherManagerService \
    WeatherProvider
# No status bar, navigation bar, keyguard or volume dialog to draw. Android
# treats a missing keyguard as a device without one.
LOCAL_OVERRIDES_PACKAGES += \
    SystemUI
# Telephony. The device has no radio (ro.radio.noril), and the phone process
# and the providers it pulls in only cost RAM.
LOCAL_OVERRIDES_PACKAGES += \
    BlockedNumberProvider \
    ContactsProvider \
    MmsService \
    Telecom \
    TelephonyProvider \
    TeleService
# The Android System WebView. Nothing on a headless device draws a web page:
# Kiosk Satellite builds no UI there, and signing in to a captive Wi-Fi portal
# needs a screen. 80 MB of /system and a library preparation on every boot.
LOCAL_OVERRIDES_PACKAGES += \
    webview
include $(BUILD_PACKAGE)
