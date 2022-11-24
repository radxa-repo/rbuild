#!/bin/bash

set -euo pipefail
shopt -s nullglob
mkdir -p /boot/dtbo
for i in /usr/lib/linux-image-*/$1/overlays/*.dtbo
do
    cp "$i" /boot/dtbo/$(basename "$i").disabled
done