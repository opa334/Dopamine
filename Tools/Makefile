TARGETS=fastPathSign BuildVFS Exe2Driver installHaxx
TARGETS_CLEAN=$(addsuffix _clean, $(TARGETS))
TARGETS_BUILD_CLEAN=$(addsuffix _build_clean, $(TARGETS))

all: $(TARGETS)
clean: $(TARGETS_CLEAN)
build_clean: $(TARGETS_BUILD_CLEAN)

.PHONY: all clean build_clean

$(TARGETS): FORCE
	@echo make -C $@
	@$(MAKE) -C $@

$(TARGETS_CLEAN): FORCE
	@echo make -C $(@:_clean=) clean
	@$(MAKE) -C $(@:_clean=) clean

$(TARGETS_BUILD_CLEAN): FORCE
	@echo make -C $(@:_build_clean=) build_clean
	@$(MAKE) -C $(@:_build_clean=) build_clean

FORCE: ;
