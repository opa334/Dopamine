
all %:
	@./BaseBin/pack.sh
	@xattr -rc Tools >/dev/null 2>&1
	$(MAKE) -C Exploits/oobPCI $@
	$(MAKE) -C Dopamine $@

clean:
	@./BaseBin/clean.sh

update: all
	@./jbupdate.sh
