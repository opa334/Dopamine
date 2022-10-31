SDK=iphoneos
SDK_PATH=$(shell xcrun --sdk $(SDK) --show-sdk-path)

TARGET=arm64-apple-ios14.0
CONFIG=release
TEAMID ?= APPLECOMPUTER

SWIFTC_ARGS=-sdk "$(SDK_PATH)" -target $(TARGET) -O -framework IOKit -framework CoreServices -D__DARWIN_OPAQUE_ARM_THREAD_STATE64
SWIFT_BUILD_ARGS=-c $(CONFIG) -Xcc "-DIOS_BUILD" -Xcc -target -Xcc $(TARGET) -Xcc -Wno-incompatible-sysroot $(addprefix -Xswiftc ,$(SWIFTC_ARGS))

all: FuguInstall

.PHONY: all build_clean clean

FuguInstall: .build/$(CONFIG)/FuguInstall FORCE
	@cp .build/$(CONFIG)/FuguInstall FuguInstall_tmp
	@echo Changing FuguInstall CPU subtype
	printf '\x01' | dd of=FuguInstall_tmp bs=1 seek=8 conv=notrunc 2>/dev/null
	@echo Ad-Hoc signing FuguInstall
	codesign -s - --entitlements FuguInstall.entitlements FuguInstall_tmp
	@echo "Fake-signing FuguInstall (team id: $(TEAMID))"
	../Tools/fastPathSign/fastPathSign FuguInstall_tmp $(TEAMID)
	@mv FuguInstall_tmp FuguInstall

.build/$(CONFIG)/%: Sources/% FORCE
	@echo Building FuguInstall
	swift build $(SWIFT_BUILD_ARGS)
	
build_clean:
	rm -rf .build
	rm -f FuguInstall_tmp
	
clean: build_clean
	rm -f FuguInstall

FORCE: ;
