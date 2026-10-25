TARGET = systemhook.dylib
CC = clang

CFLAGS = -I../.include -I./src -I../_external/modules/litehook/src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -install_name @loader_path/$(TARGET) -Wno-deprecated-declarations -D BUILD_STANDALONE=$(BUILD_STANDALONE) -Os -moutline
LDFLAGS = -dynamiclib

all: roothider_inline.o $(TARGET) sign

roothider_inline.o: src/roothider_inline.x
	@$(CC) -nostdlib -I../.include -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) \
	 -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -Wno-deprecated-declarations \
	 -fno-stack-protector -fno-stack-check -fno-builtin -D_FORTIFY_SOURCE=0 -O2 \
	 -MMD -MP -MF $(@:.o=.d) -MT $@ \
	 -x c -c -o $@ $<
	@UNDEF=$$(nm -u -j $@ 2>/dev/null | sed '/^[[:space:]]*$$/d; / (for architecture [^)]*):$$/d'); \
	if [ -n "$$UNDEF" ]; then \
		echo "FAIL: $@ has undefined symbols:"; \
		echo "$$UNDEF"; \
		rm -f $@; \
		exit 1; \
	fi
	@echo "PASS: $@ is self-contained"

sign: $(TARGET)
	@install_name_tool -id $(TARGET) $(TARGET)
	@ldid -Cadhoc -S $^

$(TARGET): $(wildcard src/*.[cSm] src/common/*.[cSm] ../libjailbreak/src/jbclient_*.c ../libjailbreak/src/inline_svc.[cS] ../libjailbreak/src/hookd.c ../_external/modules/litehook/src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

$(TARGET): ../libroothider/src/jailbreakd.c roothider_inline.o

clean:
	@rm -f $(TARGET)
	@rm -f roothider_inline.o roothider_inline.d

-include roothider_inline.d
