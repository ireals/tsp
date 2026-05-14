LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := teesimplus
LOCAL_SRC_FILES := main.cpp hook.cpp equalizer.cpp
LOCAL_LDLIBS := -llog -ldl
LOCAL_CPPFLAGS := -std=c++17 -Wall -Wextra -O2 -fvisibility=hidden
LOCAL_C_INCLUDES := $(LOCAL_PATH)/include
include $(BUILD_SHARED_LIBRARY)
