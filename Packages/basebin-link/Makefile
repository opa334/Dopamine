package: $(TARGET)
	@mkdir -p .package/DEBIAN
	@mkdir -p .package/var/jb/usr/bin
	@mkdir -p .package/var/jb/usr/lib
	@cp control .package/DEBIAN/control
	@ln -s ../../basebin/jbctl .package/var/jb/usr/bin/jbctl
	@ln -s ../../basebin/opainject .package/var/jb/usr/bin/opainject
	@ln -s ../../basebin/libjailbreak.dylib .package/var/jb/usr/lib/libjailbreak.dylib
	@dpkg-deb --root-owner-group -Zzstd -b .package ./basebin-link.deb
	@rm -rf .package

clean:
	@rm -rf basebin-link.deb