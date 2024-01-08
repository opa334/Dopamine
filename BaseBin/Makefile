#all: mktemp choma

#mktemp:
#	rm -rf .build-dir
#	mkdir .build-dir

#choma:
#	$(MAKE) -C ChOma TARGET=ios DISABLE_SIGNING=1 DYLIB_LDFLAGS="-install_name @loader_path/libchoma.dylib" $@

all: .build .include ChOma XPF opainject

ChOma:
	@$(MAKE) -C ChOma TARGET=ios DISABLE_SIGNING=1 DISABLE_TESTS=1 DYLIB_LDFLAGS="-install_name @loader_path/libchoma.dylib"
	@cp ChOma/output/ios/lib/libchoma.dylib .build
	@mkdir -p .include/choma
	@cp -r ChOma/output/ios/include/choma .include/choma

XPF:
	@$(MAKE) -C XPF libxpf.dylib CHOMA_DYLIB_PATH="../.build"
	@cp XPF/libxpf.dylib .build
	@mkdir -p .include/xpf
	@cp XPF/src/xpf.h .include/xpf

opainject:
	$(MAKE) -C opainject FINALPACKAGE=1
	@cp opainject/.theos/obj/opainject .build

.build:
	mkdir .build

.include:
	mkdir .include

basebin.tc:
	touch basebin.tc

basebin.tar:
	touch basebin.tar

clean:
	@$(MAKE) -C ChOma $@
	@$(MAKE) -C XPF $@
	@$(MAKE) -C opainject $@
	@rm -rf .build
	@rm -rf .include
	@rm -rf basebin.tar
	@rm -rf basebin.tc

.PHONY: clean ChOma XPF opainject