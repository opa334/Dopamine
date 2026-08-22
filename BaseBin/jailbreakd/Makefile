TARGET = jailbreakd

CC = clang

CFLAGS = -Werror -Wno-availability -framework Foundation -I../.include -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path)  -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc -Wno-nullability-completeness-on-arrays -O3
LDFLAGS = -L../.build -ljailbreak -lbsm

sign: $(TARGET)
	@ldid -Sentitlements.plist $<

$(TARGET): $(wildcard src/*.m src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
