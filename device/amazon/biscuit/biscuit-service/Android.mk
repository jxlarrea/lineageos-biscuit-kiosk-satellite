LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := biscuit-ledd
LOCAL_SRC_FILES := biscuit-ledd.cpp
LOCAL_CPPFLAGS := -std=gnu++11 -Wall -Werror
LOCAL_MODULE_TAGS := optional
include $(BUILD_EXECUTABLE)

include $(CLEAR_VARS)
LOCAL_MODULE := biscuit-ledctl
LOCAL_SRC_FILES := biscuit-ledctl.cpp
LOCAL_CPPFLAGS := -std=gnu++11 -Wall -Werror
LOCAL_MODULE_TAGS := optional
include $(BUILD_EXECUTABLE)

include $(CLEAR_VARS)
LOCAL_MODULE := biscuit-pryond
LOCAL_SRC_FILES := biscuit-pryond.cpp
LOCAL_CPPFLAGS := -std=gnu++11 -Wall -Werror
LOCAL_SHARED_LIBRARIES := libdl
LOCAL_MODULE_TAGS := optional
include $(BUILD_EXECUTABLE)

include $(CLEAR_VARS)
LOCAL_MODULE := i2c-poke
LOCAL_SRC_FILES := i2c-poke.cpp
LOCAL_CPPFLAGS := -std=gnu++11 -Wall -Werror
LOCAL_MODULE_TAGS := optional
include $(BUILD_EXECUTABLE)

include $(CLEAR_VARS)
LOCAL_MODULE := biscuit_service
LOCAL_SRC_FILES := biscuit_service
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_PATH := $(TARGET_OUT_EXECUTABLES)
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_PACKAGE_NAME := BiscuitService
LOCAL_MODULE_TAGS := optional
LOCAL_CERTIFICATE := platform
LOCAL_PRIVILEGED_MODULE := true
LOCAL_PROGUARD_ENABLED := disabled
LOCAL_MANIFEST_FILE := service/AndroidManifest.xml
LOCAL_SRC_FILES := $(call all-java-files-under, service/src) $(call all-Iaidl-files-under, service/src)
include $(BUILD_PACKAGE)
