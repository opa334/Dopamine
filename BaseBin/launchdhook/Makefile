TARGET = launchdhook.dylib
CC = clang

CFLAGS = -framework Foundation -framework CoreServices -framework Security -I../.include -Isrc -I../_external/modules/litehook/src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -Wno-deprecated-declarations -D BUILD_STANDALONE=$(BUILD_STANDALONE) -fobjc-arc -O2
LDFLAGS = -dynamiclib -rpath @loader_path/fallback -L../.build -L../_external/lib -ljailbreak -lellekit -lbsm -lchoma -lMobileGestalt

sign: $(TARGET)
	@ldid -Cadhoc -S $^

$(TARGET): $(wildcard src/*.m src/*.c src/jbserver/*.c ../systemhook/src/common/*.[cSm] ../systemhook/src/roothider_common.c ../_external/modules/litehook/src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)
