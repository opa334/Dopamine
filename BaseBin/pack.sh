#!/bin/sh

set -e

PREV_DIR=$(pwd)
PACK_DIR=$(dirname -- "$0")
cd "$PACK_DIR"

TARGET="../Fugu15/Fugu15/bootstrap/basebin.tar"

if [ -d "$TARGET" ]; then
	rm -rf "$TARGET"
fi

if [ -d "basebin.tar" ]; then
	rm -rf "basebin.tar"
fi

if [ -d ".tmp/basebin" ]; then
	rm -rf ".tmp/basebin"
fi
mkdir -p ".tmp/basebin"

# libjailbreak
cd "libjailbreak"
make clean
make
cd -
cp "./libjailbreak/libjailbreak.dylib" ".tmp/basebin/libjailbreak.dylib"

# copy headers
rm -rf "./_shared/libjailbreak"
mkdir -p "./_shared/libjailbreak"
cp ./libjailbreak/src/*.h ./_shared/libjailbreak

# jailbreakd

cd "jailbreakd"
make clean
make
cd -
cp "./jailbreakd/jailbreakd" ".tmp/basebin/jailbreakd"
cp "./jailbreakd/daemon.plist" ".tmp/basebin/jailbreakd.plist"

# kickstart

cd "kickstart"
make clean
make
cd -
cp "./kickstart/kickstart" ".tmp/basebin/kickstart"

# jbctl

cd "jbctl"
make clean
make
cd -
cp "./jbctl/jbctl" ".tmp/basebin/jbctl"

# launchdhook
cd "launchdhook"
make clean
make
cd -
cp "./launchdhook/launchdhook.dylib" ".tmp/basebin/launchdhook.dylib"

# systemhook
cd "systemhook"
make clean
make
cd -
cp "./systemhook/systemhook.dylib" ".tmp/basebin/systemhook.dylib"


# external
cp -r ./_external/* .tmp/basebin/

# Create TrustCache, for basebinaries
rm -rf "./basebin.tc"
trustcache create "./basebin.tc" "./.tmp/basebin"

# Tar /tmp to basebin.tar
cd ".tmp"
# only works with procursus tar for whatever reason
DYLD_FALLBACK_LIBRARY_PATH=".." ../tar -cvf "../$TARGET" "./basebin" --owner=0 --group=0 
cd -

rm -rf ".tmp"

cd "$PREV_DIR"