TARGET = launchdhook.dylib
CC = clang

CFLAGS = -framework Foundation -framework CoreServices -framework Security -I../_shared -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc
LDFLAGS = -dynamiclib -rpath /var/jb/Library/Frameworks -rpath @loader_path/fallback -L../libjailbreak -L../_shared -ljailbreak -lellekit -lbsm -L../libfilecom -lfilecom

sign: $(TARGET)
	@ldid -S $^

$(TARGET): $(wildcard src/*.m ../systemhook/src/common.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	install_name_tool -change "/var/jb/basebin/libjailbreak.dylib" "@loader_path/libjailbreak.dylib" $@
	install_name_tool -change "/var/jb/basebin/libfilecom.dylib" "@loader_path/libfilecom.dylib" $@

clean:
	@rm -f $(TARGET)