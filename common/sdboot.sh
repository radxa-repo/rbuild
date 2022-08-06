#!/bin/bash

KERNEL=$(find /boot/vmlinuz-*)
KERNEL=${KERNEL#"/boot/vmlinuz-"}
MACHINE_ID=$(cat /etc/machine-id)

source /etc/defaule/extlinux

echo "$(cat /etc/kernel/cmdline) $APPEND" > /etc/kernel/cmdline

mkdir /boot/efi/$(cat /etc/machine-id)

bootctl install

kernel-install add ${KERNEL} /boot/vmlinuz-${KERNEL}