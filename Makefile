ipa: all
	@echo Building Fugu15_Developer.ipa
	python3 Server/buildIPA.py Fugu15/Fugu15.ipa Fugu15_Developer.ipa

all %:
	@xattr -rc Tools >/dev/null 2>&1
	$(MAKE) -C Exploits/oobPCI $@
	$(MAKE) -C Fugu15 $@
	$(MAKE) -C FuguInstall $@
