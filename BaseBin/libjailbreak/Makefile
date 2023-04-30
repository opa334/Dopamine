TARGET = libjailbreak.dylib

CC = clang

CFLAGS = -framework Foundation -framework CoreServices -framework Security -framework IOKit -I../_shared -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc -Wno-nullability-completeness-on-arrays -dynamiclib -install_name /var/jb/basebin/$(TARGET)
LDFLAGS = -lbsm -L../libfilecom -lfilecom

sign: $(TARGET)
	@ldid -S $<

$(TARGET): $(wildcard src/*.m src/*.c src/*.S)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	install_name_tool -change "/var/jb/basebin/libfilecom.dylib" "@loader_path/libfilecom.dylib" $@

clean:
	@rm -f $(TARGET)