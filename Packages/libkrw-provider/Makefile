TARGET = libkrw-plugin.dylib
CC = clang

CFLAGS = -I../../BaseBin/.include -Isrc -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc -O2
LDFLAGS = -dynamiclib -rpath /var/jb -L../../BaseBin/.build -ljailbreak

all: $(TARGET) sign

sign: $(TARGET)
	@ldid -S $^

$(TARGET): $(wildcard src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
	@rm -f libkrw-plugin.deb

package: $(TARGET)
	@mkdir -p .package/DEBIAN
	@mkdir -p .package/var/jb/usr/lib/libkrw
	@cp control .package/DEBIAN/control
	@cp libkrw-plugin.dylib .package/var/jb/usr/lib/libkrw/libkrw-plugin.dylib
	@dpkg-deb --root-owner-group -Zzstd -b .package ./libkrw-plugin.deb
	@rm -rf .package
