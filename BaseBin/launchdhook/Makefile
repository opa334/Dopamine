TARGET = launchdhook.dylib
CC = clang

CFLAGS = -framework Foundation -framework CoreServices -framework Security -I../_shared -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc
LDFLAGS = -dynamiclib -L../libjailbreak -L../_shared -ljailbreak -lellekit -lbsm

sign: $(TARGET)
	@ldid -S $^

$(TARGET): $(wildcard src/*.m)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)