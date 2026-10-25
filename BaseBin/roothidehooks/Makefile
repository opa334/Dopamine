TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = lsd cfprefsd backboardd runningboardd SpringBoard
ifeq ($(PALEHIDE),1)
INSTALL_TARGET_PROCESSES += coreauthd securityd ctkd keybagd
endif
FINALPACKAGE = 1
THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = roothidehooks

roothidehooks_FILES = $(wildcard src/*.x) $(wildcard src/*.c) $(wildcard src/*.m)
roothidehooks_CFLAGS = -Werror -fobjc-arc -I../.include
roothidehooks_LDFLAGS = -L../.build -ljailbreak -lbsm -lroothider
roothidehooks_INSTALL_PATH = /basebin

ifneq ($(DEBUG),1)
roothidehooks_CFLAGS += -DNSLog\(...\)= -Wno-unused-variable
endif

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	rm -rf ./.theos
	rm -rf ./packages

after-roothidehooks-all::
	install_name_tool -delete_rpath @loader_path/.jbroot/Library/Frameworks $(THEOS_OBJ_DIR)/roothidehooks.dylib || true
	install_name_tool -add_rpath @loader_path/present -add_rpath @loader_path/fallback $(THEOS_OBJ_DIR)/roothidehooks.dylib
	install_name_tool -change @loader_path/.jbroot/usr/lib/libsubstrate.dylib @rpath/CydiaSubstrate.framework/CydiaSubstrate $(THEOS_OBJ_DIR)/roothidehooks.dylib
	ldid -S $(THEOS_OBJ_DIR)/roothidehooks.dylib
