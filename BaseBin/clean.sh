#!/bin/sh

set -e

PREV_DIR=$(pwd)
PACK_DIR=$(dirname -- "$0")
cd "$PACK_DIR"

# jailbreakd
cd "jailbreakd"
make clean
cd -

# kickstart
cd "kickstart"
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
