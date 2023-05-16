TARGET = watchdoghook.dylib
CC = clang

CFLAGS = -framework Foundation -framework CoreServices -framework Security -I../_shared -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc
LDFLAGS = -dynamiclib -rpath /var/jb/Library/Frameworks -rpath @loader_path/fallback -L../_shared -lellekit -framework IOKit

sign: $(TARGET)
	@ldid -S $^

$(TARGET): $(wildcard src/*.m)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)