TARGET = jbctl

CC = clang

CFLAGS = -framework Foundation -framework CoreServices -framework Security -I../.include -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc
LDFLAGS = -L../.build -ljailbreak -lchoma

sign: $(TARGET)
	@ldid -Sentitlements.plist $<

$(TARGET): $(wildcard src/*.m)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)