#!/bin/sh

set -e

PREV_DIR=$(pwd)
PACK_DIR=$(dirname -- "$0")
cd "$PACK_DIR"

# libfilecom
cd "libfilecom"
make clean
cd -

# libjailbreak
cd "libjailbreak"
make clean
cd -

# jailbreakd
cd "jailbreakd"
make clean
cd -

# boomerang
cd "boomerang"
make clean
cd -

# jbinit
cd "jbinit"
make clean
cd -

# jbctl
cd "jbctl"
make clean
cd -

# launchdhook
cd "launchdhook"
make clean
cd -

# systemhook
cd "systemhook"
make clean
cd -

# watchdoghook
cd "watchdoghook"
make clean
cd -

# rootlesshooks
cd "rootlesshooks"
make clean
cd -

# forkfix
cd "forkfix"
make clean
cd -

cd "$PREV_DIR"