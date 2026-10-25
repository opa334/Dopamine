export NIGHTLY ?= 0

export BUILD_STANDALONE ?= 0

ifeq ($(NIGHTLY), 1)
export COMMIT_HASH = $(shell git rev-parse HEAD)
endif

ifeq ($(BUILD_STANDALONE), 1)
export BUILD_STANDALONE = 1
endif

all:
	@$(MAKE) -C BaseBin
	@$(MAKE) -C Packages
	@$(MAKE) -C Application
# 	@$(MAKE) -C Standalone

clean:
	@$(MAKE) -C BaseBin clean
	@$(MAKE) -C Packages clean
	@$(MAKE) -C Application clean
# 	@$(MAKE) -C Standalone clean

update: all
	ssh $(DEVICE) "rm -rf /var/mobile/Documents/Dopamine.tipa"
	scp -C ./Application/Dopamine.tipa "$(DEVICE):/var/mobile/Documents/Dopamine.tipa"
	ssh $(DEVICE) "/basebin/jbctl update tipa \$$(jbroot)/var/mobile/Documents/Dopamine.tipa"

update-basebin: all
	ssh $(DEVICE) "rm -rf /var/mobile/Documents/basebin.tar"
	scp -C ./BaseBin/basebin.tar "$(DEVICE):/var/mobile/Documents/basebin.tar"
	ssh $(DEVICE) "/basebin/jbctl update basebin \$$(jbroot)/var/mobile/Documents/basebin.tar"

.PHONY: update clean