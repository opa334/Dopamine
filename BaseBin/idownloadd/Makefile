XCODE_PROJECT = src/idownloadd.xcodeproj
XCODE_SCHEME = idownloadd

CONFIGURATION = Release

OUTPUT_NAME = idownloadd

build:
	xcodebuild -archivePath ./.build -project $(XCODE_PROJECT) -scheme $(XCODE_SCHEME) -configuration $(CONFIGURATION) -destination generic/platform=iOS archive
	@cp -f ./.build.xcarchive/Products/usr/local/bin/$(OUTPUT_NAME) .
	@rm -rf ./.build.xcarchive
	@ldid -Sentitlements.plist $(OUTPUT_NAME)

clean:
	xcodebuild -project $(XCODE_PROJECT) -scheme $(XCODE_SCHEME) -configuration $(CONFIGURATION) -destination generic/platform=iOS clean

default: build