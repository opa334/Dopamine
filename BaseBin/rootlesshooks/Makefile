TARGET := iphone:clang:16.2:15.0
INSTALL_TARGET_PROCESSES = lsd cfprefsd
FINALPACKAGE = 1
THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = rootlesshooks

rootlesshooks_FILES = main.x installd.x cfprefsd.x
rootlesshooks_CFLAGS = -fobjc-arc
rootlesshooks_LDFLAGS = -rpath @loader_path/fallback

include $(THEOS_MAKE_PATH)/tweak.mk
