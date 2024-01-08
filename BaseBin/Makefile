#all: mktemp choma

#mktemp:
#	rm -rf .build-dir
#	mkdir .build-dir

#choma:
#	$(MAKE) -C ChOma TARGET=ios DISABLE_SIGNING=1 DYLIB_LDFLAGS="-install_name @loader_path/libchoma.dylib" $@

all: .build .headers ChOma XPF

ChOma:
	@$(MAKE) -C ChOma TARGET=ios DISABLE_SIGNING=1 DISABLE_TESTS=1 DYLIB_LDFLAGS="-install_name @loader_path/libchoma.dylib"
	@cp ChOma/output/ios/lib/libchoma.dylib .build
	@mkdir -p .headers/choma
	@cp -r ChOma/output/ios/include/choma .headers/choma

XPF:
	@$(MAKE) -C XPF libxpf.dylib CHOMA_DYLIB_PATH="../.build"
	@cp XPF/libxpf.dylib .build
	@mkdir -p .headers/xpf
	@cp XPF/src/xpf.h .headers/xpf

.build:
	mkdir .build

.headers:
	mkdir .headers

basebin.tc:
	touch basebin.tc

basebin.tar:
	touch basebin.tar

clean:
	@$(MAKE) -C ChOma $@
	@$(MAKE) -C XPF $@
	@rm -rf .build
	@rm -rf .headers
	@rm -rf basebin.tar
	@rm -rf basebin.tc

.PHONY: clean ChOma XPF