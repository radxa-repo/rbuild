#!/bin/bash

set -e
shopt -s nullglob
mkdir -p /boot/dtbo
for i in /usr/lib/linux-image-*/{{ $soc_family }}/overlays/*.dtbo
do
    cp "$i" /boot/dtbo/$(basename "$i").disabled
done