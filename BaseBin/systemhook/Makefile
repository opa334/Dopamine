TARGET = systemhook.dylib
CC = clang

CFLAGS = -framework CoreFoundation -I../_shared -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0
LDFLAGS = -dynamiclib

sign: $(TARGET)
	@ldid -S $^

$(TARGET): $(wildcard src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)