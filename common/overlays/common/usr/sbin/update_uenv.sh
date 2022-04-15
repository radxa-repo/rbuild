#!/bin/bash
set -e

FILE_UENV=/boot/uEnv.txt

remove_variables()
{
    VAR=("initrdsize" "kernelversion" "initrdimg" "kernelimg")
    for var in ${VAR[@]};
    do
        sed -i "/${var}/d" ${FILE_UENV}
    done
}

get_kernel_latest_version()
{
    export KERNEL_VERSION=$(linux-version list | linux-version sort --reverse | awk 'NR==1 {print}')
}

get_initrd_image_size()
{
    TMP=$(stat /boot/initrd.img-${KERNEL_VERSION} | grep "Size" | cut -d ":" -f2 | cut -d " " -f2)
    export INITRDSIZE=$(echo "$(printf "%x" $TMP)")
}

update_uenv() {
    echo "installing initrd size: 0x$INITRDSIZE"
    echo "installing kernel version: $KERNEL_VERSION"
    echo "initrdsize=0x${INITRDSIZE}" >> ${FILE_UENV}
    echo "kernelversion=${KERNEL_VERSION}" >> ${FILE_UENV}
    echo "initrdimg=initrd.img-${KERNEL_VERSION}" >> ${FILE_UENV}
    echo "kernelimg=vmlinuz-${KERNEL_VERSION}" >> ${FILE_UENV}
}

if [ -f "${FILE_UENV}" ]; then
    echo "Find ${FILE_UENV} and will update it."
    remove_variables
    get_kernel_latest_version
    get_initrd_image_size
    update_uenv
fi
