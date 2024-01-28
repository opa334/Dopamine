all:
	@$(MAKE) -C BaseBin
	@$(MAKE) -C Application

clean:
	@$(MAKE) -C BaseBin clean
	@$(MAKE) -C Application clean

.PHONY: clean