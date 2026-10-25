package: $(TARGET)
	@mkdir -p .package/DEBIAN
	@mkdir -p .package/usr/bin
	@mkdir -p .package/usr/lib
	@cp control .package/DEBIAN/control
	@ln -s ../../basebin/jbctl .package/usr/bin/jbctl
	@ln -s ../../basebin/opainject .package/usr/bin/opainject
	@ln -s ../../basebin/libjailbreak.dylib .package/usr/lib/libjailbreak.dylib
	@dpkg-deb --root-owner-group -Zzstd -b .package ./basebin-link.deb
	@rm -rf .package

clean:
	@rm -rf basebin-link.deb