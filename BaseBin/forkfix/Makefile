TARGET = forkfix.dylib
CC = clang

CFLAGS = -I../_shared -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0 -O2
LDFLAGS = -dynamiclib ../systemhook/systemhook.dylib

sign: $(TARGET)
	@ldid -S $^

$(TARGET): $(wildcard src/*.c src/*.S)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	install_name_tool -change "systemhook.dylib" "/usr/lib/systemhook.dylib" $@

clean:
	@rm -f $(TARGET)