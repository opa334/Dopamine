#all: mktemp choma

#mktemp:
#	rm -rf .build-dir
#	mkdir .build-dir

#choma:
#	$(MAKE) -C ChOma TARGET=ios DISABLE_SIGNING=1 DYLIB_LDFLAGS="-install_name @loader_path/libchoma.dylib" $@

all: basebin.tar

subprojects: ChOma XPF MachOMerger opainject libjailbreak systemhook forkfix launchdhook hookd boomerang jbctl idownloadd watchdoghook roothidehooks jailbreakd bootstrapper dopamine

ChOma: .build .include
	@$(MAKE) -C ChOma TARGET=ios DISABLE_SIGNING=1 DISABLE_TESTS=1 DYLIB_LDFLAGS="-install_name @loader_path/libchoma.dylib"
	@ldid -Cadhoc -s ChOma/output/ios/lib/libchoma.dylib
	@cp ChOma/output/ios/lib/libchoma.dylib .build
	@cp -r ChOma/output/ios/include/choma .include

XPF: .build .include ChOma
	@$(MAKE) -C XPF output/ios/libxpf.dylib CHOMA_PATH=../ChOma CHOMA_DYLIB_PATH="../.build"
	@ldid -Cadhoc -s XPF/output/ios/libxpf.dylib
	@cp XPF/output/ios/libxpf.dylib .build/libxpf.dylib
	@mkdir -p .include/xpf
	@cp XPF/src/xpf.h .include/xpf

MachOMerger: .build .include
	@$(MAKE) -C MachOMerger
	@cp MachOMerger/MachOMerger .build

opainject: .build .include
	$(MAKE) -C opainject FINALPACKAGE=1
	@ldid -Cadhoc -s opainject/.theos/obj/opainject
	@cp opainject/.theos/obj/opainject .build

libjailbreak: .build .include ChOma
	$(MAKE) -C libjailbreak
	@cp libjailbreak/libjailbreak.dylib .build
	@mkdir -p .include/libjailbreak
	@cp libjailbreak/src/*.h .include/libjailbreak
	@mkdir -p .include/libjailbreak/roothider
	@cp libjailbreak/src/roothider/*.h .include/libjailbreak/roothider

systemhook: .build .include libjailbreak
	$(MAKE) -C systemhook
	@cp systemhook/systemhook.dylib .build

forkfix: .build .include libjailbreak systemhook
	$(MAKE) -C forkfix
	@cp forkfix/forkfix.dylib .build

launchdhook: .build .include libjailbreak
	$(MAKE) -C launchdhook
	@cp launchdhook/launchdhook.dylib .build

hookd: .build .include libjailbreak
	$(MAKE) -C hookd
	@cp hookd/hookd .build

boomerang: .build .include libjailbreak
	$(MAKE) -C boomerang
	@cp boomerang/boomerang .build

jbctl: .build .include libjailbreak
	$(MAKE) -C jbctl
	@cp jbctl/jbctl .build

idownloadd: .build .include libjailbreak
	$(MAKE) -C idownloadd
	@cp idownloadd/idownloadd .build

watchdoghook: .build .include libjailbreak
	$(MAKE) -C watchdoghook
	@cp watchdoghook/watchdoghook.dylib .build

roothidehooks: .build .include libjailbreak
	$(MAKE) -C roothidehooks
	@cp roothidehooks/.theos/obj/roothidehooks.dylib .build

bootstrapper: .build .include libjailbreak
	$(MAKE) -C bootstrapper
	@cp bootstrapper/bootstrapper .build

jailbreakd: .build .include libjailbreak
	$(MAKE) -C jailbreakd
	@cp jailbreakd/jailbreakd .build

dopamine: .build .include libjailbreak XPF ChOma
	$(MAKE) -C dopamine
	@cp dopamine/dopamine .build

.build:
	rm -rf .build
	mkdir -p .build
	cp -r _external/basebin/* .build
	cp _external/basebin/.version .build

.include:
	rm -rf .include
	mkdir -p .include
	cp -r _external/include/* .include
# If the SDK already ships XPC (it does so in iOS 17.4+), remove the local copy of it
ifneq (,$(wildcard $(shell xcrun --sdk iphoneos --show-sdk-path)/usr/include/xpc.modulemap))
	rm -rf .include/xpc
endif

basebin.tc: subprojects
	trustcache create .build/basebin.tc .build
	cp .build/basebin.tc basebin.tc

# dyldhook dylibs do not need to be added to the basebin trustcache
dyldhook: basebin.tc
	$(MAKE) -C dyldhook
	@cp dyldhook/*.dylib .build

basebin.tar: basebin.tc dyldhook
	@find ./.build -name ".DS_Store" -delete
	@DYLD_FALLBACK_LIBRARY_PATH="." ./tar --transform "s/^.build/basebin/" -cvf "basebin.tar" ".build" --owner=0 --group=0

clean:
	@$(MAKE) -C ChOma $@
	@$(MAKE) -C XPF $@
	@$(MAKE) -C MachOMerger $@
	@$(MAKE) -C opainject $@
	@$(MAKE) -C libjailbreak $@
	@$(MAKE) -C systemhook $@
	@$(MAKE) -C forkfix $@
	@$(MAKE) -C launchdhook $@
	@$(MAKE) -C boomerang $@
	@$(MAKE) -C jbctl $@
	@$(MAKE) -C idownloadd $@
	@$(MAKE) -C watchdoghook $@
	@$(MAKE) -C roothidehooks $@
	@$(MAKE) -C jailbreakd $@
	@$(MAKE) -C bootstrapper $@
	@$(MAKE) -C dyldhook $@
	@$(MAKE) -C dopamine $@
	@$(MAKE) -C hookd $@
	@rm -rf .build
	@rm -rf .include
	@rm -rf basebin.tar
	@rm -rf basebin.tc

.PHONY: clean .build .include ChOma XPF MachOMerger opainject libjailbreak systemhook forkfix launchdhook hookd boomerang jbctl idownloadd watchdoghook roothidehooks jailbreakd bootstrapper basebin.tc dyldhook basebin.tar dopamine