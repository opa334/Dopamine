TARGET = jbinit

CC = clang

CFLAGS = -framework Foundation -I../_shared -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0
LDFLAGS = -L../libjailbreak -ljailbreak

sign: $(TARGET)
	@ldid -Sentitlements.plist -Icom.apple.jbinit $<

$(TARGET): $(wildcard src/*.m)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	install_name_tool -change "/var/jb/basebin/libjailbreak.dylib" "@loader_path/libjailbreak.dylib" $@

clean:
	@rm -f $(TARGET)