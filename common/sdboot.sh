#!/bin/bash

KERNEL=$(find /boot/vmlinuz-*)
KERNEL=${KERNEL#"/boot/vmlinuz-"}
MACHINE_ID=$(cat /etc/machine-id)

echo "$(cat /etc/kernel/cmdline) earlyprintk console=tty0 console=ttyAML0,115200n8 console=ttyS2,1500000n8 console=ttyFIQ0,1500000n8" > /etc/kernel/cmdline

mkdir /boot/efi/$(cat /etc/machine-id)

bootctl install

kernel-install add ${KERNEL} /boot/vmlinuz-${KERNEL}