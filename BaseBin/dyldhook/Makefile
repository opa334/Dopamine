CC = clang

CFLAGS = -I../.include -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=15.0 -Wno-deprecated-declarations -fno-stack-check -D_FORTIFY_SOURCE=0 -O2
LDFLAGS = -shared -Xlinker -add_split_seg_info
FILES = $(wildcard src/*.c src/*.S ../libjailbreak/src/jbclient_mach.c)
FILES_IOS15 = $(wildcard src/generated/ios15/*.c)
FILES_IOS16 = $(wildcard src/generated/ios16/*.c)

all: dyldhook_merge.arm64e.dylib dyldhook_merge.arm64e.iOS15.dylib dyldhook_merge.arm64.dylib dyldhook_merge.arm64.iOS15.dylib

dyldhook_merge.arm64e.dylib: $(FILES) $(FILES_IOS16)
	$(CC) -arch arm64e $(CFLAGS) -DIOS=16 $(LDFLAGS) -o $@ $^
	@ldid -S $@

dyldhook_merge.arm64e.iOS15.dylib: $(FILES) $(FILES_IOS15)
	$(CC) -arch arm64e $(CFLAGS) -DIOS=15 $(LDFLAGS) -o $@ $^
	@ldid -S $@

dyldhook_merge.arm64.dylib: $(FILES) $(FILES_IOS16)
	$(CC) -arch arm64 $(CFLAGS) -DIOS=16 $(LDFLAGS) -o $@ $^
	@ldid -S $@

dyldhook_merge.arm64.iOS15.dylib: $(FILES) $(FILES_IOS15)
	$(CC) -arch arm64 $(CFLAGS) -DIOS=15 $(LDFLAGS) -o $@ $^
	@ldid -S $@

clean:
	@rm -f dyldhook_merge.arm64e.dylib
	@rm -f dyldhook_merge.arm64e.iOS15.dylib
	@rm -f dyldhook_merge.arm64.dylib
	@rm -f dyldhook_merge.arm64.iOS15.dylib
