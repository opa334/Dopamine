SWIFT_BUILD_ARGS=-c $(CONFIG)

SWIFT_BUILD_ARGS_X86_64=$(SWIFT_BUILD_ARGS) -Xswiftc -target -Xswiftc x86_64-apple-macos12.0
SWIFT_BUILD_ARGS_ARM64=$(SWIFT_BUILD_ARGS) -Xswiftc -target -Xswiftc arm64-apple-macos12.0

all: $(TARGET)

build_clean:
	rm -rf .build_x86_64 .build_arm64

clean: build_clean
	rm -f $(TARGET)

.PHONY: all build_clean clean

.build_x86_64/$(CONFIG)/$(TARGET): FORCE
	swift build --build-path .build_x86_64 $(SWIFT_BUILD_ARGS_X86_64)
    
.build_arm64/$(CONFIG)/$(TARGET): FORCE
	swift build --build-path .build_arm64  $(SWIFT_BUILD_ARGS_ARM64)

$(TARGET): .build_x86_64/$(CONFIG)/$(TARGET) .build_arm64/$(CONFIG)/$(TARGET)
	lipo -create .build_x86_64/$(CONFIG)/$(TARGET) .build_arm64/$(CONFIG)/$(TARGET) -output $(TARGET)

FORCE: ;
