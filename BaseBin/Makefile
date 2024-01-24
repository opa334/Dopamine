#all: mktemp choma

#mktemp:
#	rm -rf .build-dir
#	mkdir .build-dir

#choma:
#	$(MAKE) -C ChOma TARGET=ios DISABLE_SIGNING=1 DYLIB_LDFLAGS="-install_name @loader_path/libchoma.dylib" $@

all: .build .include ChOma XPF opainject libjailbreak systemhook forkfix launchdhook boomerang jbctl BaseBin.tc BaseBin.tar

ChOma:
	@$(MAKE) -C ChOma TARGET=ios DISABLE_SIGNING=1 DISABLE_TESTS=1 DYLIB_LDFLAGS="-install_name @loader_path/libchoma.dylib"
	@cp ChOma/output/ios/lib/libchoma.dylib .build
	@cp -r ChOma/output/ios/include/choma .include

XPF:
	@$(MAKE) -C XPF libxpf.dylib CHOMA_DYLIB_PATH="../.build"
	@cp XPF/libxpf.dylib .build
	@mkdir -p .include/xpf
	@cp XPF/src/xpf.h .include/xpf

opainject:
	$(MAKE) -C opainject FINALPACKAGE=1
	@cp opainject/.theos/obj/opainject .build

libjailbreak:
	$(MAKE) -C libjailbreak
	@cp libjailbreak/libjailbreak.dylib .build
	@mkdir -p .include/libjailbreak
	@cp libjailbreak/src/*.h .include/libjailbreak

systemhook:
	$(MAKE) -C systemhook
	@cp systemhook/systemhook.dylib .build

forkfix:
	$(MAKE) -C forkfix
	@cp forkfix/forkfix.dylib .build

launchdhook:
	$(MAKE) -C launchdhook
	@cp launchdhook/launchdhook.dylib .build

boomerang:
	$(MAKE) -C boomerang
	@cp boomerang/boomerang .build

jbctl:
	$(MAKE) -C jbctl
	@cp jbctl/jbctl .build

.build:
	rm -rf .build
	mkdir -p .build
	cp -r _external/basebin/* .build

.include:
	rm -rf .include
	mkdir -p .include
	cp -r _external/include/* .include

BaseBin.tc:
	trustcache create BaseBin.tc .build

BaseBin.tar:
	@DYLD_FALLBACK_LIBRARY_PATH="." ./tar --transform "s/^.build/basebin/" -cvf "BaseBin.tar" ".build" --owner=0 --group=0

clean:
	@$(MAKE) -C ChOma $@
	@$(MAKE) -C XPF $@
	@$(MAKE) -C opainject $@
	@$(MAKE) -C libjailbreak $@
	@$(MAKE) -C systemhook $@
	@$(MAKE) -C forkfix $@
	@$(MAKE) -C launchdhook $@
	@$(MAKE) -C boomerang $@
	@$(MAKE) -C jbctl $@
	@rm -rf .build
	@rm -rf .include
	@rm -rf BaseBin.tar
	@rm -rf BaseBin.tc

.PHONY: clean .build .include ChOma XPF opainject libjailbreak systemhook forkfix launchdhook boomerang jbctl BaseBin.tc BaseBin.tar