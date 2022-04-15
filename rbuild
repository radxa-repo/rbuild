#!/usr/bin/env bash

EXIT_SUCCESS=0
EXIT_UNKNOWN_OPTION=1
EXIT_TOO_FEW_ARGUMENTS=2
EXIT_UNSUPPORTED_OPTION=3
EXIT_SHRINK_PERMISSION=4
EXIT_SHRINK_NO_ROOTDEV=5

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
        $EXIT_SHRINK_PERMISSION)
            echo "--shrink requires either passwordless sudo, or running in an interactive shell." >&2
            ;;
        $EXIT_SHRINK_NO_ROOTDEV)
            echo "Unable to access loop device '$2' for shrinking." >&2
            ;;
        *)
            echo "Unknown exit code." >&2
            ;;
    esac
    
    exit "$1"
}

shrink() {
    local ROOT_PART="$(sgdisk -p "$1" | grep 8300 | tail -n 1 | tr -s ' ' | cut -d ' ' -f 2)"
    local LOOP_DEV="$(basename $(sudo kpartx -l "$1" | head -n 1 | cut -d ' ' -f 5))"
    local ROOT_DEV="/dev/mapper/${LOOP_DEV}p${ROOT_PART}"

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
    local TARGET_BLOCKS="$(sudo resize2fs -P "$ROOT_DEV" | cut -d ' ' -f 7)"
    local BLOCK_SIZE="$(sudo tune2fs -l "$ROOT_DEV" | grep '^Block size:' | tr -s ' ' | cut -d ' ' -f 3)"
    local SHRINK_SIZE="$(( (TOTAL_BLOCKS - TARGET_BLOCKS) * BLOCK_SIZE ))"
    sudo e2fsck -pf "$ROOT_DEV"
    sudo resize2fs -M "$ROOT_DEV"

    sudo kpartx -d "$1"

    cat << EOF | parted ---pretend-input-tty "$1"
resizepart $ROOT_PART 
-${SHRINK_SIZE}B
yes
EOF

    local TOTAL_SIZE="$(du -b "$1" | cut -f 1)"
    # leave some space for the secondary GPT header
    truncate --size=$(( TOTAL_SIZE - SHRINK_SIZE + 34 * 512 )) "$1"
    sgdisk -e "$1" || true
    sgdisk -v "$1"
}

usage() {
    cat >&2 << EOF
Radxa Image Builder
usage: $(basename "$0") [options] <board> <distro> [flavor]

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

Supported distros:
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
        BOARDS+=($(basename "$f" .conf))
    done
    echo "${BOARDS[@]}"
}

get_supported_distros() {
    local DISTROS=("debian" "ubuntu")
    echo "${DISTROS[@]}"
}

get_supported_flavors() {
    local FLAVORS=("cli" "desktop")
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
    if [[ -e /dev/kvm ]]
    then
        local DEBOS_BACKEND="--device /dev/kvm"
    else
        local DEBOS_BACKEND="--tmpfs /dev/shm:rw,nosuid,nodev,exec,size=4g"
    fi
    
    local DOCKER_OPTIONS=
    if [[ -t 0 ]]
    then
        DOCKER_OPTIONS="$DOCKER_OPTIONS -it"
    fi

    if [[ $SCRIPT_DIR != $PWD ]]
    then
        DOCKER_OPTIONS="$DOCKER_OPTIONS --mount type=bind,source=$SCRIPT_DIR,destination=$SCRIPT_DIR"
    fi
    
    docker run --rm $DEBOS_BACKEND --user $(id -u) \
        --security-opt label=disable \
        --workdir "$PWD" --mount "type=bind,source=$PWD,destination=$PWD" \
        $DOCKER_OPTIONS godebos/debos $@
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
                RBUILD_SHRINK="yes"
                shift
                ;;
            --no-compression)
                RBUILD_NO_COMPRESSION="yes"
                shift
                ;;
            -d | --debug)
                DEBOS_OPTIONS="-v --debug-shell"
                shift
                ;;
            -r | --rootfs)
                DEBOS_ROOTFS="yes"
                shift
                ;;
            -k | --kernel)
                ln "$2" "$SCRIPT_DIR/common/.packages/$(basename "$2")"
                RBUILD_KERNEL="$2"
                shift 2
                ;;
            -f | --firmware)
                ln "$2" "$SCRIPT_DIR/common/.packages/$(basename "$2")"
                RBUILD_FIRMWARE="$2"
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

    if (( $# < 2))
    then
        error $EXIT_TOO_FEW_ARGUMENTS
    fi

    if [[ "$RBUILD_SHRINK" == "yes" ]] && ! sudo -n true 2>/dev/null && ! [[ -t 0 ]]
    then
        error $EXIT_SHRINK_PERMISSION
    fi

    local BOARD="$1"
    local DISTRO="$2"
    shift 2
    if (( $# > 0 ))
    then
        local FLAVOR="$1"
        shift
    else
        local FLAVOR=( $(get_supported_flavors) )
        FLAVOR=${FLAVOR[0]}
    fi

    local BOARDS=($(get_supported_boards))
    local DISTROS=($(get_supported_distros))
    local FLAVORS=($(get_supported_flavors))
    if ! ( in_array "$BOARD" "${BOARDS[@]}" && \
           in_array "$DISTRO" "${DISTROS[@]}" && \
           in_array "$FLAVOR" "${FLAVORS[@]}" )
    then
        error $EXIT_UNSUPPORTED_OPTION "$BOARD $DISTRO $FLAVOR"
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
    local BOOT_END="332MiB"
    
    docker pull godebos/debos:latest

    mkdir -p "$SCRIPT_DIR/.rootfs"
    if [[ $DEBOS_ROOTFS != "yes" ]] || [[ ! -e "$SCRIPT_DIR/.rootfs/${DISTRO}_${SUITE}_${FLAVOR}.tar.xz" ]]
    then
        debos $DEBOS_OPTIONS "$SCRIPT_DIR/common/rootfs.yaml" \
            -t architecture:"$ARCH" \
            -t board:"$BOARD" -t distro:"$DISTRO" -t suite:"$SUITE" -t flavor:"$FLAVOR"
    else
        echo "Using ${DISTRO}_${SUITE}_${FLAVOR}.tar.xz rootfs."
    fi

    debos $DEBOS_OPTIONS "$SCRIPT_DIR/common/image.yaml" \
        -t architecture:"$ARCH" \
        -t board:"$BOARD" -t distro:"$DISTRO" -t suite:"$SUITE" -t flavor:"$FLAVOR" \
        -t soc:"$SOC" -t soc_family:"$SOC_FAMILY" \
        -t image:"$IMAGE" -t boot_end:"$BOOT_END" -t partition_type:"$PARTITION_TYPE" \
        -t kernel:"$RBUILD_KERNEL" -t firmware:"$RBUILD_FIRMWARE"

    if [[ "$RBUILD_SHRINK" == "yes" ]]
    then
        if ! sudo -n true 2>/dev/null
        then
            $NOTIFY_SEND "rbuild is waiting for user input."
            echo "rbuild shrink needs root permission to perform partition operations."
            echo "The process is paused to prevent sudo timeout on asking for password."
            read -p "Please press enter to continue: " i
        fi
        shrink "$IMAGE"
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

build "$@"
