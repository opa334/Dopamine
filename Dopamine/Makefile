.PHONY: all clean build_clean

all: Dopamine.tipa

Dopamine.tipa: build/Build/Products/Debug-iphoneos/Dopamine.app
	@echo Ad-Hoc signing Dopamine
	xattr -rc build/Build/Products/Debug-iphoneos/Dopamine.app
	codesign -s - --entitlements Dopamine/Dopamine.entitlements build/Build/Products/Debug-iphoneos/Dopamine.app
	@echo Fake-signing Dopamine
	ldid -K../Exploits/fastPath/arm.pfx -Upassword -s build/Build/Products/Debug-iphoneos/Dopamine.app
	@echo Creating ipa
	rm -rf Payload Dopamine.tipa
	mkdir Payload
	cp -r build/Build/Products/Debug-iphoneos/Dopamine.app Payload/Dopamine.app
	zip -Ar Dopamine.tipa Payload
	rm -rf Payload

build/Build/Products/Debug-iphoneos/Dopamine.app: FORCE
	xcodebuild -scheme Dopamine -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

clean:
	rm -rf build Payload Dopamine.tipa

build_clean:
	rm -rf Payload build

FORCE: ;
