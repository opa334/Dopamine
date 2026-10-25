TARGET = libroothider

CC = clang

CFLAGS = -I../.include -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc -install_name @loader_path/$(TARGET).dylib

LDFLAGS = -dynamiclib -rpath @loader_path/present -rpath @loader_path/fallback -lc++ -lbsm -L../.build -L../_external/lib -weak-lellekit -lchoma -lxpf -ljailbreak -framework IOKit -framework IOSurface

SOURCES := $(wildcard src/*.c src/*.cpp src/*.m src/*.S)

sign: $(TARGET).dylib
	@ldid -Cadhoc -S $<

$(TARGET).dylib: $(SOURCES)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

$(TARGET)-stub.dylib: $(SOURCES)
	$(CC) $(CFLAGS) $(SOURCES) $(filter-out -ljailbreak,$(LDFLAGS)) -Wl,-undefined,dynamic_lookup -o $(TARGET)-stub.dylib

clean:
	@rm -f $(TARGET).dylib
	@rm -f $(TARGET)-stub.dylib