TARGET = kickstart

CC = clang

CFLAGS = -framework Foundation -I../_shared -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0

sign: $(TARGET)
	@ldid -Sentitlements.plist $<

$(TARGET): $(wildcard *.m)
	$(CC) $(CFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)