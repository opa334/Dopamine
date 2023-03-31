ipa: all
	@echo Building Fugu15_Developer.ipa
	python3 Server/buildIPA.py Fugu15/Fugu15.tipa Fugu15_Developer.ipa

all %:
	rm -rf ./BaseBin/libjailbreak/libjailbreak.dylib ./BaseBin/launchdhook/launchdhook.dylib ./BaseBin/kickstart/kickstart ./BaseBin/jbctl/jbctl ./BaseBin/jailbreakd/jailbreakd ./BaseBin/systemhook/systemhook.dylib ./Fugu15_Developer.ipa ./Fugu15/build/Build/Products/Debug-iphoneos/Fugu15.app/basebin.tar ./Fugu15/Fugu15/bootstrap/basebin.tar || true
	@./BaseBin/pack.sh
	@xattr -rc Tools >/dev/null 2>&1
	$(MAKE) -C Exploits/oobPCI $@
	$(MAKE) -C Fugu15 $@
	$(MAKE) -C FuguInstall $@
