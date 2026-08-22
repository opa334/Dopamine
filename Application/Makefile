.PHONY: all clean build_clean

APP = build/Build/Products/Debug-iphoneos/Dopamine.app

all: Dopamine.ipa Dopamine.tipa

ifeq ($(NIGHTLY), 1)
$(APP): FORCE
	xcodebuild -scheme Dopamine -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO GCC_PREPROCESSOR_DEFINITIONS='NIGHTLY=1 COMMIT_HASH=\"$(COMMIT_HASH)\"'
	touch $(APP)/Dopamine.roothide
	cp -a Dopamine/Resources/*.deb $(APP)/
else
$(APP): FORCE
	xcodebuild -scheme Dopamine -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
	touch $(APP)/Dopamine.roothide
	cp -a Dopamine/Resources/*.deb $(APP)/
endif

Dopamine.ipa: $(APP)
	@echo Ad-Hoc signing Dopamine IPA
	xattr -rc $(APP)
	ldid -SDopamine/Dopamine.entitlements $(APP)/Dopamine
	ldid -s $(APP)
	rm -rf Payload Dopamine.ipa
	mkdir Payload
	cp -r $(APP) Payload/Dopamine.app
	zip -Ar Dopamine.ipa Payload
	rm -rf Payload

Dopamine.tipa: $(APP)
	@echo Ad-Hoc signing Dopamine TIPA
	xattr -rc $(APP)
	ldid -SDopamine/Dopamine-TrollStore.entitlements $(APP)/Dopamine
	ldid -s $(APP)
	rm -rf Payload Dopamine.tipa
	mkdir Payload
	cp -r $(APP) Payload/Dopamine.app
	zip -Ar Dopamine.tipa Payload
	rm -rf Payload

clean:
	rm -rf build Payload Dopamine.ipa Dopamine.tipa

build_clean:
	rm -rf Payload build

FORCE: ;
