#!/usr/bin/env bash

EXIT_SUCCESS=0
EXIT_UNKNOWN_OPTION=1
EXIT_TOO_FEW_ARGUMENTS=2
EXIT_UNSUPPORTED_OPTION=3
EXIT_SUDO_PERMISSION=4
EXIT_SHRINK_NO_ROOTDEV=5
EXIT_DEV_SHM_TOO_SMALL=6

error() {
    case "$1" in
        $EXIT_SUCCESS)
            ;;
        $EXIT_UNKNOWN_OPTION)
            echo "Unknown option: '$2'." >&2
            ;;
        $EXIT_TOO_FEW_ARGUMENTS)
            echo "Too few arguments." >&2
            ;;
        $EXIT_UNSUPPORTED_OPTION)
            echo "Option '$2' is not supported." >&2
            ;;
        $EXIT_SUDO_PERMISSION)
            echo "'$2' requires either passwordless sudo, or running in an interactive shell." >&2
            ;;
        $EXIT_SHRINK_NO_ROOTDEV)
            echo "Unable to access loop device '$2' for shrinking." >&2
            ;;
        $EXIT_DEV_SHM_TOO_SMALL)
            echo "Your /dev/shm is too small. Current '$2', require '$3'." >&2
            ;;
        *)
            echo "Unknown exit code." >&2
            ;;
    esac
    
    exit "$1"
}

find_root_part() {
    local ROOT_PART
    ROOT_PART="$(sgdisk -p "$1" | grep "rootfs" | tail -n 1 | tr -s ' ' | cut -d ' ' -f 2)"
    if [[ -z $ROOT_PART ]]
    then
        ROOT_PART="$(sgdisk -p "$1" | grep -e "8300" -e "EF00" | tail -n 1 | tr -s ' ' | cut -d ' ' -f 2)"
    fi
    echo $ROOT_PART
}

shrink() {
    local ROOT_PART="$(find_root_part "$1")"
    if [[ -z $ROOT_PART ]]
    then
        echo "Unable to locate root partition number." >&2
        return
    fi
    
    local SECTOR_SIZE="$(sgdisk -p "$1" | grep "Sector size (logical):" | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)"
    local START_SECTOR="$(sgdisk -i "$ROOT_PART" "$1" | grep "First sector:" | cut -d ' ' -f 3)"
    local LOOP_DEV="$(basename $(sudo kpartx -l "$1" | head -n 1 | cut -d ' ' -f 5))"
    local ROOT_DEV="/dev/mapper/${LOOP_DEV}p${ROOT_PART}"
    echo "Partition $ROOT_PART is root partition."

    sudo kpartx -a "$1"
    local i=0
    until [[ -e "$ROOT_DEV" ]]
    do
        if (( i++ < 5))
        then
            echo "Waiting for device to be ready: $i"
            sleep 1
        else
            sudo kpartx -d "$1"
            error $EXIT_SHRINK_NO_ROOTDEV "$ROOT_DEV"
        fi
    done

    local TOTAL_BLOCKS="$(sudo tune2fs -l "$ROOT_DEV" | grep '^Block count:' | tr -s ' ' | cut -d ' ' -f 3)"
    local TARGET_BLOCKS="$(sudo resize2fs -P "$ROOT_DEV" 2> /dev/null | cut -d ' ' -f 7)"
    local BLOCK_SIZE="$(sudo tune2fs -l "$ROOT_DEV" | grep '^Block size:' | tr -s ' ' | cut -d ' ' -f 3)"
    echo "$TARGET_BLOCKS of $TOTAL_BLOCKS blocks are in use."

    if (( $TARGET_BLOCKS < $TOTAL_BLOCKS ))
    then
        sudo e2fsck -pf "$ROOT_DEV" > /dev/null
        sudo resize2fs -M "$ROOT_DEV" > /dev/null 2>&1
        sync
        TARGET_BLOCKS="$(sudo tune2fs -l "$ROOT_DEV" | grep '^Block count:' | tr -s ' ' | cut -d ' ' -f 3)"
        echo "Root filesystem has been shrinked to $TARGET_BLOCKS blocks."
    fi

    local NEW_SIZE="$(( $START_SECTOR * $SECTOR_SIZE + $TARGET_BLOCKS * $BLOCK_SIZE ))"

    sudo kpartx -d "$1"

    cat << EOF | parted ---pretend-input-tty "$1" > /dev/null 2>&1
resizepart $ROOT_PART 
${NEW_SIZE}B
yes
EOF
    echo "Root partition has been shrinked to $NEW_SIZE."

    local TOTAL_SIZE="$(du -b "$1" | cut -f 1)"
    local END_SECTOR="$(sgdisk -i "$ROOT_PART" "$1" | grep "Last sector:" | cut -d ' ' -f 3)"
    # leave some space for the secondary GPT header
    local FINAL_SIZE="$(( ($END_SECTOR + 34) * $SECTOR_SIZE ))"
    truncate "--size=$FINAL_SIZE" "$1" > /dev/null
    if [[ $2 == "gpt" ]]
    then
        sgdisk -ge "$1" > /dev/null || true
        sgdisk -v "$1" > /dev/null
    fi
    echo "Image shrunked from $TOTAL_SIZE to $FINAL_SIZE."
}

usage() {
    cat >&2 << EOF
Radxa Image Builder
usage: $(basename "$0") [options] <board> [distro] [flavor]

Supported image generation options:
    -s, --shrink        Shrink root partition after image is generated
                        Require root permission and additional dependencies
    --no-compression    Do not compress the final image                        
    -d, --debug         Drop into a debug shell when build failed
    -r, --rootfs        Use already generated rootfs if available
    -k, --kernel [deb]  Use custom Linux kernel package
    -f, --firmware [deb]
                        Use custom firmware package

Alternative functionalities
    --json [catagory]   Print supported options in json format
                        Available catagories: $(get_supported_infos)
    -h, --help          Show this help message

Supported board:
$(printf_array "    %s\n" "$(get_supported_boards)")

Supported distros (default to the first one):
$(printf_array "    %s\n" "$(get_supported_distros)")

Supported flavors (default to the first one):
$(printf_array "    %s\n" "$(get_supported_flavors)")
EOF
    exit "$1"
}

printf_array() {
    local FORMAT="$1"
    shift
    local ARRAY=("$@")

    if [[ $FORMAT == "json" ]]
    then
        jq --compact-output --null-input '$ARGS.positional' --args -- "${ARRAY[@]}"
    else
        for i in ${ARRAY[@]}
        do
            printf "$FORMAT" "$i"
        done
    fi
}

get_supported_boards() {
    local BOARDS=()
    for f in $SCRIPT_DIR/configs/*.conf
    do
        BOARDS+=("$(basename "$f" .conf)")
    done
    echo "${BOARDS[@]}"
}

get_supported_distros() {
    local DISTROS=("debian")
    echo "${DISTROS[@]}"
}

get_supported_flavors() {
    local FLAVORS=()
    for f in $SCRIPT_DIR/common/flavors/*.yaml
    do
        FLAVORS+=("$(basename "$f" .yaml)")
    done
    echo "${FLAVORS[@]}"
}

get_supported_infos() {
    local INFOS=("boards" "distros" "flavors")
    echo "${INFOS[@]}"
}

in_array() {
    local ITEM="$1"
    shift
    local ARRAY=("$@")
    if [[ " ${ARRAY[*]} " =~ " $ITEM " ]]
    then
        true
    else
        false
    fi
}

json() {
    local ARRAY=($(get_supported_infos))
    if ! in_array "$1" "${ARRAY[@]}"
    then
        error $EXIT_UNKNOWN_OPTION "$1"
    fi

    printf_array "json" $(get_supported_$1)
    exit 0
}

debos() {
    local DEBOS_BACKEND
    if [[ -e /dev/kvm ]]
    then
        DEBOS_BACKEND="--device /dev/kvm "
    fi
    DEBOS_BACKEND+="--tmpfs /dev/shm:exec"
    
    local DOCKER_OPTIONS=
    if [[ -t 0 ]]
    then
        DOCKER_OPTIONS="$DOCKER_OPTIONS -it"
    fi

    if [[ $SCRIPT_DIR != $PWD ]]
    then
        DOCKER_OPTIONS="$DOCKER_OPTIONS --mount type=bind,source=$SCRIPT_DIR,destination=$SCRIPT_DIR"
    fi
    
    local DEV_SHM_CURRENT=$(df -h /dev/shm | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)
    local DEV_SHM_REQUIRE=5
    if (( $(df -B 1 /dev/shm | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4) < $DEV_SHM_REQUIRE * 1024 * 1024 ))
    then
        if ! sudo -n true 2>/dev/null && ! [[ -t 0 ]]
        then
            error $EXIT_SUDO_PERMISSION "Remounting /dev/shm"
        else
            if ! sudo mount -o remount,size=${DEV_SHM_REQUIRE}G /dev/shm
            then
                error $EXIT_DEV_SHM_TOO_SMALL $DEV_SHM_CURRENT ${DEV_SHM_REQUIRE}G
            fi
        fi
    fi

    docker run --rm $DEBOS_BACKEND --user $(id -u) \
        --security-opt label=disable \
        --workdir "$PWD" --mount "type=bind,source=$PWD,destination=$PWD" \
        $DOCKER_OPTIONS godebos/debos --cpus=$(nproc) --memory=$(( DEV_SHM_REQUIRE - 1 ))G $@
}

build() {
    local RBUILD_SHRINK=
    local RBUILD_NO_COMPRESSION=
    local DEBOS_OPTIONS=
    local DEBOS_ROOTFS=
    local RBUILD_KERNEL=
    local RBUILD_FIRMWARE=

    rm -rf "$SCRIPT_DIR/common/.packages"
    mkdir "$SCRIPT_DIR/common/.packages"

    if (( $# == 0 ))
    then
        usage 0
    fi

    while (( $# > 0 ))
    do
        case "$1" in
            -s | --shrink)
                if ! sudo -n true 2>/dev/null && ! [[ -t 0 ]]
                then
                    error $EXIT_SUDO_PERMISSION "--shrink"
                fi
                RBUILD_SHRINK="yes"
                shift
                ;;
            --no-compression)
                RBUILD_NO_COMPRESSION="yes"
                shift
                ;;
            -d | --debug)
                DEBOS_OPTIONS="-v --debug-shell --show-boot"
                shift
                ;;
            -r | --rootfs)
                DEBOS_ROOTFS="yes"
                shift
                ;;
            -k | --kernel)
                cp "$2" "$SCRIPT_DIR/common/.packages/$(basename "$2")"
                RBUILD_KERNEL="$(basename $2)"
                shift 2
                ;;
            -f | --firmware)
                cp "$2" "$SCRIPT_DIR/common/.packages/$(basename "$2")"
                RBUILD_FIRMWARE="$(basename $2)"
                shift 2
                ;;
            --json)
                json "$2"
                ;;
            -h | --help)
                usage 0
                ;;
            -*)
                error $EXIT_UNKNOWN_OPTION "$1"
                ;;
            *) break ;;
        esac
    done

    if (( $# < 1 ))
    then
        error $EXIT_TOO_FEW_ARGUMENTS
    fi

    local DEBOS_TUPLE="$@"
    local BOARDS=($(get_supported_boards))
    local DISTROS=($(get_supported_distros))
    local FLAVORS=($(get_supported_flavors))
    # Ubuntu is not officially supported but we will allow it for the time being
    DISTROS+=("ubuntu")

    local BOARD=
    local DISTRO=${DISTROS[0]}
    local FLAVOR=${FLAVORS[0]}

    while (( $# > 0 ))
    do
        if in_array "$1" "${BOARDS[@]}"
        then
            BOARD="$1"
        elif in_array "$1" "${DISTROS[@]}"
        then
            DISTRO="$1"
        elif in_array "$1" "${FLAVORS[@]}"
        then
            FLAVOR="$1"
        else
            error $EXIT_UNKNOWN_OPTION "$1"
        fi
        shift
    done
    
    if ! ( in_array "$BOARD" "${BOARDS[@]}" && \
           in_array "$DISTRO" "${DISTROS[@]}" && \
           in_array "$FLAVOR" "${FLAVORS[@]}" )
    then
        error $EXIT_UNSUPPORTED_OPTION "$DEBOS_TUPLE"
    fi

    source "$SCRIPT_DIR/configs/$BOARD.conf"
    source "$SCRIPT_DIR/common/hw-info.conf"
    local SOC_FAMILY="$(get_soc_family $SOC)"
    local PARTITION_TYPE="$(get_partition_type $SOC_FAMILY)"

    case $DISTRO in
        debian)
            local SUITE="bullseye"
            ;;
        ubuntu)
            local SUITE="focal"
            ;;
    esac

    local ARCH="arm64"
    local IMAGE="${BOARD}_${DISTRO}_${SUITE}_${FLAVOR}.img"
    local EFI_END=${EFI_END:-"32MiB"}
    
    # Release targeting image in case previous shrink failed
    if [[ "$RBUILD_SHRINK" == "yes" ]]
    then
        sudo kpartx -d "$IMAGE" || true
    fi

    docker pull godebos/debos:latest

    mkdir -p "$SCRIPT_DIR/.rootfs"
    if [[ "$DEBOS_ROOTFS" != "yes" ]] || [[ ! -e "$SCRIPT_DIR/.rootfs/${DISTRO}_${SUITE}_${FLAVOR}.tar" ]]
    then
        pushd "$SCRIPT_DIR"
        debos $DEBOS_OPTIONS "$SCRIPT_DIR/common/rootfs.yaml" \
            -t architecture:"$ARCH" \
            -t board:"$BOARD" -t distro:"$DISTRO" -t suite:"$SUITE" -t flavor:"$FLAVOR"
        popd
    else
        echo "Using ${DISTRO}_${SUITE}_${FLAVOR}.tar rootfs."
    fi

    if [[ "$BOARD" == "rootfs" ]]
    then
        return
    fi

    debos $DEBOS_OPTIONS "$SCRIPT_DIR/common/image.yaml" \
        -t architecture:"$ARCH" \
        -t board:"$BOARD" -t distro:"$DISTRO" -t suite:"$SUITE" -t flavor:"$FLAVOR" \
        -t soc:"$SOC" -t soc_family:"$SOC_FAMILY" \
        -t image:"$IMAGE" -t efi_end:"$EFI_END" -t partition_type:"$PARTITION_TYPE" \
        -t kernel:"$RBUILD_KERNEL" -t firmware:"$RBUILD_FIRMWARE"

    if [[ "$RBUILD_SHRINK" == "yes" ]]
    then
        if ! sudo -n true 2>/dev/null
        then
            $NOTIFY_SEND "rbuild is waiting for user input."
            echo "rbuild shrink needs root permission to perform partition operations."
            echo "The process is paused to prevent sudo timeout on asking for password."
            read -p "Please press enter to continue..." i
        fi
        shrink "$IMAGE" "$PARTITION_TYPE"
    fi

    sha512sum "$IMAGE" > "$IMAGE.sha512"
    chown $USER: "$IMAGE"
    
    if [[ "$RBUILD_NO_COMPRESSION" != "yes" ]]
    then
        xz -fT 0 "$IMAGE"
    fi
    
    $NOTIFY_SEND "rbuild is finished."
}

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

if which notify-send >/dev/null 2>&1
then
    NOTIFY_SEND=notify-send
else
    NOTIFY_SEND=echo
fi

SECONDS=0

build "$@"

TZ=UTC0 printf 'Total execution time: %(%H:%M:%S)T\n' $SECONDS