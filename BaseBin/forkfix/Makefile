TARGET = forkfix.dylib
CC = clang

CFLAGS = -I../.include -I./src -I../_external/modules/litehook/src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -Wno-deprecated-declarations -miphoneos-version-min=15.0 -D BUILD_STANDALONE=$(BUILD_STANDALONE) -O2
LDFLAGS = -dynamiclib

sign: $(TARGET)
	@ldid -Cadhoc -S $^

$(TARGET): $(wildcard src/*.c src/*.S ../libjailbreak/src/jbclient_*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
