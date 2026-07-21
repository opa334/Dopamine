CC = clang

CFLAGS = -I../.include -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=15.0 -Wno-deprecated-declarations -fno-stack-check -D_FORTIFY_SOURCE=0 -O2
LDFLAGS = -shared -Xlinker -add_split_seg_info
FILES = $(wildcard src/*.c src/*.S ../libjailbreak/src/jbclient_mach.c)
FILES_IOS15 = $(wildcard src/generated/ios15/*.c)
FILES_IOS16-17 = $(wildcard src/generated/ios16-17/*.c)
FILES_IOS18+ = $(wildcard src/generated/ios18+/*.c)

all: dyldhook_merge.arm64e.iOS15.dylib dyldhook_merge.arm64.iOS15.dylib dyldhook_merge.arm64e.iOS16-17.dylib dyldhook_merge.arm64.iOS16-17.dylib dyldhook_merge.arm64e.iOS18+.dylib dyldhook_merge.arm64.iOS18+.dylib

define CHECK_SELF_CONTAINED
	@UNDEF=$$(nm -u $(1) 2>/dev/null); \
	if [ -n "$$UNDEF" ]; then \
		echo "FAIL: $(1) has external symbols:"; \
		echo "$$UNDEF"; \
		exit 1; \
	fi
	@echo "PASS: $(1) is self-contained"
endef

dyldhook_merge.arm64e.iOS18+.dylib: $(FILES) $(FILES_IOS18+)
	$(CC) -arch arm64e $(CFLAGS) -DIOS=18 $(LDFLAGS) -o $@ $^
	@ldid -Cadhoc -S $@
	$(call CHECK_SELF_CONTAINED,$@)

dyldhook_merge.arm64.iOS18+.dylib: $(FILES) $(FILES_IOS18+)
	$(CC) -arch arm64 $(CFLAGS) -DIOS=18 $(LDFLAGS) -o $@ $^
	@ldid -Cadhoc -S $@
	$(call CHECK_SELF_CONTAINED,$@)

dyldhook_merge.arm64e.iOS16-17.dylib: $(FILES) $(FILES_IOS16-17)
	$(CC) -arch arm64e $(CFLAGS) -DIOS=16 $(LDFLAGS) -o $@ $^
	@ldid -Cadhoc -S $@
	$(call CHECK_SELF_CONTAINED,$@)

dyldhook_merge.arm64.iOS16-17.dylib: $(FILES) $(FILES_IOS16-17)
	$(CC) -arch arm64 $(CFLAGS) -DIOS=16 $(LDFLAGS) -o $@ $^
	@ldid -Cadhoc -S $@
	$(call CHECK_SELF_CONTAINED,$@)

dyldhook_merge.arm64e.iOS15.dylib: $(FILES) $(FILES_IOS15)
	$(CC) -arch arm64e $(CFLAGS) -DIOS=15 $(LDFLAGS) -o $@ $^
	@ldid -Cadhoc -S $@
	$(call CHECK_SELF_CONTAINED,$@)

dyldhook_merge.arm64.iOS15.dylib: $(FILES) $(FILES_IOS15)
	$(CC) -arch arm64 $(CFLAGS) -DIOS=15 $(LDFLAGS) -o $@ $^
	@ldid -Cadhoc -S $@
	$(call CHECK_SELF_CONTAINED,$@)

clean:
	@rm -f dyldhook_merge.arm64e.iOS18+.dylib
	@rm -f dyldhook_merge.arm64.iOS18+.dylib
	@rm -f dyldhook_merge.arm64e.iOS16-17.dylib
	@rm -f dyldhook_merge.arm64.iOS16-17.dylib
	@rm -f dyldhook_merge.arm64e.iOS15.dylib
	@rm -f dyldhook_merge.arm64.iOS15.dylib