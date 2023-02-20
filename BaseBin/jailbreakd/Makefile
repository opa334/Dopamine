TARGET = jailbreakd

CC = clang

CFLAGS = -framework Foundation -framework CoreServices  -framework Security -I../_shared -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc -Wno-nullability-completeness-on-arrays

sign: $(TARGET)
	@ldid -Sentitlements.plist $<

$(TARGET): $(wildcard src/*.m src/*.S src/machoparse/*.c src/fileobserve/*.m)
	$(CC) $(CFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)