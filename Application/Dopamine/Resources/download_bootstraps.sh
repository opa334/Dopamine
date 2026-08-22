#!/bin/sh
set -e

# RootHide vendor bootstraps (relative layout, extract into .jbroot-*).
# Do NOT fetch stock Procursus from apt.procurs.us — that tar creates /var/jb.

if [ -f bootstrap_1800.tar.zst ] && [ -f bootstrap_1900.tar.zst ]; then
  echo "Using existing RootHide vendor bootstraps"
  ls -l bootstrap_1800.tar.zst bootstrap_1900.tar.zst
  exit 0
fi

echo "ERROR: bootstrap_1800.tar.zst / bootstrap_1900.tar.zst missing."
echo "Copy them from Dopamine2-roothide Application/Dopamine/Resources/"
exit 1
