TARGET = forkfix.dylib
CC = clang

CFLAGS = -I../_shared -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0
LDFLAGS = -dynamiclib -rpath /var/jb/Library/Frameworks -rpath /var/jb/basebin/fallback -L../_shared -lellekit

sign: $(TARGET)
	@ldid -S $^

$(TARGET): $(wildcard src/*.c src/*.S)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)