all:
	@$(MAKE) -C BaseBin
	@$(MAKE) -C Application

clean:
	@$(MAKE) -C BaseBin clean
	@$(MAKE) -C Application clean

update: all
	ssh $(DEVICE) "rm -rf /var/mobile/Documents/Dopamine.tipa"
	scp ./Application/Dopamine.tipa "$(DEVICE):/var/mobile/Documents/Dopamine.tipa"
	ssh $(DEVICE) "/var/jb/basebin/jbctl update tipa /var/mobile/Documents/Dopamine.tipa"

.PHONY: update clean