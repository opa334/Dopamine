#!/bin/sh

set -e

# jailbreakd
cd "jailbreakd"
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
