.PHONY: all clean build_clean

all: Dopamine.ipa

Dopamine.ipa: build/Build/Products/Debug-iphoneos/Dopamine.app
	@echo Ad-Hoc signing Dopamine
	xattr -rc build/Build/Products/Debug-iphoneos/Dopamine.app
	ldid -SDopamine/Dopamine.entitlements build/Build/Products/Debug-iphoneos/Dopamine.app/Dopamine
	ldid -s build/Build/Products/Debug-iphoneos/Dopamine.app
	rm -rf Payload Dopamine.ipa
	mkdir Payload
	cp -r build/Build/Products/Debug-iphoneos/Dopamine.app Payload/Dopamine.app
	@echo Embedding additional packages for auto-install
	mkdir -p Payload/Dopamine.app/Packages
	# FIX(build): the path above was "../../Packages/additional", but this
	# recipe runs with cwd = Application/, so ../../Packages pointed OUTSIDE
	# the repo and the test always failed — i.e. nothing from
	# Packages/additional/ was ever embedded via this branch (only the
	# Resources/ fallback below actually worked, which is why roothideapp was
	# present in shipped IPAs while e.g. the tweak-infrastructure debs were
	# not). One level up is the repo root.
	if [ -d "../Packages/additional" ] && [ -n "$$(ls -A ../Packages/additional 2>/dev/null)" ]; then \
		cp -r ../Packages/additional/* Payload/Dopamine.app/Packages/; \
	fi
	# Copy packages from Resources (for files that can't be tracked in Packages/additional)
	if [ -f "Resources/roothideapp_1.3.9_iphoneos-arm64e.deb" ]; then \
		cp Resources/roothideapp_1.3.9_iphoneos-arm64e.deb Payload/Dopamine.app/Packages/; \
	fi
	zip -Ar Dopamine.ipa Payload
	rm -rf Payload
	rm -rf Dopamine.tipa
	cp Dopamine.ipa Dopamine.tipa

ifeq ($(NIGHTLY), 1)
build/Build/Products/Debug-iphoneos/Dopamine.app: FORCE
	xcodebuild -scheme Dopamine -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO GCC_PREPROCESSOR_DEFINES='NIGHTLY=1 COMMIT_HASH="$(COMMIT_HASH)"'
else
build/Build/Products/Debug-iphoneos/Dopamine.app: FORCE
	xcodebuild -scheme Dopamine -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
endif

clean:
	rm -rf build Payload Dopamine.ipa Dopamine.tipa

build_clean:
	rm -rf Payload build

FORCE: ;
