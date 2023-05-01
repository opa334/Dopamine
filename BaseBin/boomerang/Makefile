TARGET = boomerang

CC = clang

CFLAGS = -framework Foundation -framework CoreServices -framework Security -I../_shared -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc -Wno-nullability-completeness-on-arrays
LDFLAGS = -L../libjailbreak -ljailbreak -L../libfilecom -lfilecom

sign: $(TARGET)
	@ldid -Sentitlements.plist $<

$(TARGET): $(wildcard src/*.m)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	install_name_tool -change "/var/jb/basebin/libjailbreak.dylib" "@loader_path/libjailbreak.dylib" $@
	install_name_tool -change "/var/jb/basebin/libfilecom.dylib" "@loader_path/libfilecom.dylib" $@

clean:
	@rm -f $(TARGET)