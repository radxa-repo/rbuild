#!/usr/bin/env bash

EXIT_SUCCESS=0
EXIT_UNKNOWN_OPTION=1
EXIT_TOO_FEW_ARGUMENTS=2
EXIT_UNSUPPORTED_OPTION=3
EXIT_SUDO_PERMISSION=4
EXIT_SHRINK_NO_ROOTDEV=5
EXIT_DEV_SHM_TOO_SMALL=6
EXIT_RBUILD_AS_ROOT=7

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
        $EXIT_RBUILD_AS_ROOT)
            cat << EOF >&2
You are running $(basename "$0") with root permission, which is not recommended for normal development.
If you need root permission to run docker, please add your account to docker group, reboot, and try again.
EOF
            ;;
        *)
            echo "Unknown error code $1." >&2
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

shrink-image() {
    local ROOT_PART="$(find_root_part "$1")"
    if [[ -z $ROOT_PART ]]
    then
        echo "Unable to locate root partition number." >&2
        return
    fi
    
    local PARTITION_TYPE="$(blkid -o value -s PTTYPE $1)"
    local SECTOR_SIZE="$(sgdisk -p "$1" | grep "Sector size (logical):" | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)"
    local START_SECTOR="$(sgdisk -i "$ROOT_PART" "$1" | grep "First sector:" | cut -d ' ' -f 3)"
    echo "Partition $ROOT_PART is root partition."

    local LOOP_DEV="$(basename $(sudo kpartx -l "$1" | head -n 1 | awk '{ print $5 }'))"
    if [[ -b /dev/${LOOP_DEV} ]]
    then
        echo "Image is already mounted at /dev/${LOOP_DEV}. Trying to clean up..."
        sudo losetup -l
        cat /sys/block/${LOOP_DEV}/loop/backing_file
        sudo kpartx -d "$1"
    fi
    sudo kpartx -a "$1"
    LOOP_DEV="$(basename $(sudo kpartx -l "$1" | head -n 1 | awk '{ print $5 }'))"
    trap "sudo kpartx -d '$1'" SIGINT SIGQUIT SIGTSTP EXIT
    local ROOT_DEV="/dev/mapper/${LOOP_DEV}p${ROOT_PART}"

    if [[ ! -e "$ROOT_DEV" ]]
    then
        error $EXIT_SHRINK_NO_ROOTDEV "$ROOT_DEV"
    fi

    local TOTAL_BLOCKS="$(sudo tune2fs -l "$ROOT_DEV" | grep '^Block count:' | tr -s ' ' | cut -d ' ' -f 3)"
    sudo e2fsck -yf "$ROOT_DEV"
    local TARGET_BLOCKS="$(sudo resize2fs -P "$ROOT_DEV" 2> /dev/null | cut -d ' ' -f 7)"
    local BLOCK_SIZE="$(sudo tune2fs -l "$ROOT_DEV" | grep '^Block size:' | tr -s ' ' | cut -d ' ' -f 3)"
    echo "$TARGET_BLOCKS of $TOTAL_BLOCKS blocks are in use."

    if (( $TARGET_BLOCKS < $TOTAL_BLOCKS ))
    then
        sudo e2fsck -yf "$ROOT_DEV"
        sudo resize2fs -M "$ROOT_DEV"
        sync
        TARGET_BLOCKS="$(sudo tune2fs -l "$ROOT_DEV" | grep '^Block count:' | tr -s ' ' | cut -d ' ' -f 3)"
        echo "Root filesystem has been shrinked to $TARGET_BLOCKS blocks."
    fi

    local NEW_SIZE="$(( $START_SECTOR * $SECTOR_SIZE + $TARGET_BLOCKS * $BLOCK_SIZE ))"

    sudo kpartx -d "$1"
    trap - SIGINT SIGQUIT SIGTSTP EXIT

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
    if [[ $PARTITION_TYPE == "gpt" ]]
    then
        sgdisk -ge "$1" > /dev/null || true
        sgdisk -v "$1" > /dev/null
    fi
    echo "Image shrunked from $TOTAL_SIZE to $FINAL_SIZE."
}

usage() {
    cat >&2 << EOF
Radxa Image Builder
usage: $(basename "$0") [options] <product> [suite] [flavor]

Supported image generation options:
    -s, --shrink            Shrink root partition after image is generated
                            Require root permission and additional dependencies
    --compress              Compress the final image with xz
    -n, --native-build      Use locally installed debos instead of container
                            This is a workaround for building Ubuntu image on Ubuntu host
                            Require running rbuild with sudo
    -d, --debug             Drop into a debug shell when build failed
    -r, --rootfs            Do not use saved rootfs and regenerate it
    -k, --kernel <deb>      Use custom Linux kernel package
                            This option also requires the matching kernel header package
                            under the same folder
    -f, --firmware <deb>    Use custom firmware package
    -c, --custom <profile>  Try matching locally built bsp packages with the same profile
                            Implies --kernel and --firmware if available packages are found
                            If --debug is specified before this option, rbuild will also
                            search debug version of the package first
    -v[but_this_package], --no-vendor-package[=but_this_package] 
                            When no optional argument is provided:
                                    vendor packages will not be installed
                            When optional argument is provided:
                                    install specified vendor package instead
    -o, --overlay <profile> Specify an optional overlay that should be enabled in the image
    -t[custom_string], --timestamp[=custom_string]
                            Add build timestamp to the filename, or a custom string
    -T, --test-repo         Use Radxa Test Repositories
    -b, --backend [backend] Manually specify container backend. supported values are:
                            docker, podman
    --no-container-update   Do not update the container image
    -h, --help              Show this help message

Alternative commands
    json <catagory>         Print supported options in json format
                            Available catagories: $(get_supported_infos)
    shrink-image <image>    Shrink generated image
    write-image <image> </dev/block>
                            Write image to block device, support --shrink flag

Supported products:
$(printf_array "    %s\n" "$(get_supported_boards)")

Supported suites (default to the first one):
$(printf_array "    %s\n" "$(get_supported_suites)")

Supported flavors (default to the first one):
$(printf_array "    %s\n" "$(get_supported_flavors)")
EOF
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
    while (( $# > 0 )) && [[ "$1" == "--" ]]
    do
        shift
    done

    local BOARDS=()
    for f in $SCRIPT_DIR/configs/*.conf
    do
        BOARDS+=("$(basename "$f" .conf)")
    done
    echo "${BOARDS[@]}"
}

get_supported_suites() {
    while (( $# > 0 )) && [[ "$1" == "--" ]]
    do
        shift
    done

    local SUITES=("bullseye" "jammy")
    echo "${SUITES[@]}"
}

get_supported_flavors() {
    while (( $# > 0 )) && [[ "$1" == "--" ]]
    do
        shift
    done

    local FLAVORS=()
    for f in $SCRIPT_DIR/common/flavors/*.yaml
    do
        FLAVORS+=("$(basename "$f" .yaml)")
    done
    echo "${FLAVORS[@]}"
}

get_supported_infos() {
    while (( $# > 0 )) && [[ "$1" == "--" ]]
    do
        shift
    done

    local INFOS=("boards" "suites" "flavors")
    echo "${INFOS[@]}"
}

in_array() {
    local item="$1"
    shift
    [[ " $* " =~ " $item " ]]
}

json() {
    RBUILD_SHOW_EXECUTION_TIME="false"

    local ARRAY=($(get_supported_infos))
    if ! in_array "$@" "${ARRAY[@]}"
    then
        error $EXIT_UNKNOWN_OPTION "$1"
    fi

    local output
    output=( $(get_supported_$@) )
    if (( $? != 0 ))
    then
        return 1
    fi
    printf_array "json" "${output[@]}"
}

write-image() {
    if (( $# < 2 ))
    then
        error $EXIT_TOO_FEW_ARGUMENTS
    fi

    local IMAGE="$1"
    local BLOCKDEV="$2"

    if ! [[ -f $IMAGE ]]
    then
        echo "$IMAGE does not exist."
        return 1
    elif ! [[ -b $BLOCKDEV ]]
    then
        echo "$BLOCKDEV is not a block device."
        return 1
    fi

    if file $IMAGE | grep -q "XZ compressed"
    then
        echo "Writting xz image..."
        xzcat $IMAGE | sudo dd of=$BLOCKDEV bs=16M conv=fsync status=progress
    elif file $IMAGE | grep -q "gzip compressed data"
    then
        echo "Writting gz image..."
        zcat $IMAGE | sudo dd of=$BLOCKDEV bs=16M conv=fsync status=progress
    elif file $IMAGE | grep -q "Zip archive"
    then
        echo "Writting zip image..."
        unzip -p $IMAGE | sudo dd of=$BLOCKDEV bs=16M conv=fsync status=progress
    elif file $IMAGE | grep -q "7-zip archive data"
    then
        echo "Writting 7-zip image..."
        7z e -so $IMAGE | sudo dd of=$BLOCKDEV bs=16M conv=fsync status=progress
    else
        if $RBUILD_SHRINK
        then
            shrink-image "$IMAGE"
        fi
        echo "Writting raw image..."
        sudo dd if=$IMAGE of=$BLOCKDEV bs=16M conv=fsync status=progress
    fi
    sync
}

debos() {
    local CONTAINER_OPTIONS=(
        "--rm"
        "--tmpfs" "/dev/shm:exec"
        "--security-opt" "label=disable"
        "--cap-add=SYS_PTRACE"
        "--workdir" "$PWD"
        "--mount" "type=bind,source=$PWD,destination=$PWD"
    )

    if [[ -t 0 ]]
    then
        CONTAINER_OPTIONS+=( "-it" )
    fi

    if [[ -e /dev/kvm ]]
    then
        CONTAINER_OPTIONS+=( "--device" "/dev/kvm" )
    fi

    if [[ $SCRIPT_DIR != $PWD ]]
    then
        CONTAINER_OPTIONS+=( "--mount" "type=bind,source=$SCRIPT_DIR,destination=$SCRIPT_DIR" )
        if $NATIVE_BUILD
        then
            ln -s "$(realpath "--relative-to=$PWD" "$SCRIPT_DIR/.rootfs")" .rootfs
        else
            CONTAINER_OPTIONS+=( "--mount" "type=bind,source=$SCRIPT_DIR/.rootfs,destination=$PWD/.rootfs" )
        fi
    fi
    
    local DEV_SHM_CURRENT=$(df -h /dev/shm | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)
    local DEV_SHM_REQUIRE=6
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

    local DEBOS_OPTIONS="--cpus=$(nproc) --memory=$(( DEV_SHM_REQUIRE - 1 ))G"

    if $NATIVE_BUILD
    then
        env debos --disable-fakemachine $DEBOS_OPTIONS "$@"
    else
        if [[ "$(basename "$CONTAINER_BACKEND")" == "podman" ]]
        then
            CONTAINER_OPTIONS+=( "--user" "root" )
            $CONTAINER_BACKEND run \
                "${CONTAINER_OPTIONS[@]}" --entrypoint /bin/bash docker.io/godebos/debos \
                -c 'echo "Acquire::http::Pipeline-Depth \"0\";" > /etc/apt/apt.conf.d/99nopipelining && '"/usr/local/bin/debos $DEBOS_OPTIONS $(printf "'%s' " "$@")"
        else
            CONTAINER_OPTIONS+=( "--user" "$(id -u)" )
            $CONTAINER_BACKEND run \
                "${CONTAINER_OPTIONS[@]}" docker.io/godebos/debos \
                $DEBOS_OPTIONS "$@"
        fi
    fi
}

main() {
    local SCRIPT_DIR="$(dirname "$(realpath "$0")")"

    rm -rf "$SCRIPT_DIR/common/.packages"
    mkdir -p "$SCRIPT_DIR/common/.packages"

    local ARGV=("$@")
    if ! local TEMP="$(getopt -o "sndrk:f:v::hc:o:t::Tb:" -l "shrink,compress,native-build,debug,root-override,rootfs,kernel:,firmware:,no-vendor-package::,help,custom:,overlay:,timestamp::,test-repo,backend:,no-container-update" -n "$0" -- "$@")"
    then
        usage
        return 1
    fi
    eval set -- "$TEMP"

    local RBUILD_SHRINK="false"
    local RBUILD_COMPRESSION="false"
    local DEBOS_OPTIONS=
    local DEBOS_ROOTFS="false"
    local RBUILD_DEBUG="false"
    local RBUILD_KERNEL=
    local RBUILD_KERNEL_DBG=
    local RBUILD_HEADER=
    local RBUILD_FIRMWARE=
    local RBUILD_OVERLAY=
    local RBUILD_TIMESTAMP=
    local INSTALL_VENDOR_PACKAGE="true"
    local RBUILD_AS_ROOT="false"
    local NATIVE_BUILD="false"
    local REPO_PREFIX=
    local CONTAINER_BACKEND="docker"
    local NO_CONTAINER_UPDATE="false"

    if [[ -f "$SCRIPT_DIR/.rbuild-config" ]]
    then
        source "$SCRIPT_DIR/.rbuild-config"
    fi

    copy_kernel() {
        echo "Using custom kernel '$1' ..."
        RBUILD_KERNEL="$(basename $1)"
        cp "$1" "$SCRIPT_DIR/common/.packages/$RBUILD_KERNEL"
        RBUILD_HEADER="linux-headers-${RBUILD_KERNEL#linux-image-}"
        cp "$(dirname $1)/$RBUILD_HEADER" "$SCRIPT_DIR/common/.packages/$RBUILD_HEADER"
    }
    copy_kernel_dbg() {
        echo "Using custom debug kernel '$1' ..."
        RBUILD_KERNEL_DBG="$(basename $1)"
        cp "$1" "$SCRIPT_DIR/common/.packages/$RBUILD_KERNEL_DBG"
    }
    copy_firmware() {
        echo "Using custom firmware '$1' ..."
        cp "$1" "$SCRIPT_DIR/common/.packages/$(basename "$1")"
        RBUILD_FIRMWARE="$(basename $1)"
    }
    while true
    do
        TEMP="$1"
        shift
        case "$TEMP" in
            -s|--shrink)
                if ! sudo -n true 2>/dev/null && ! [[ -t 0 ]]
                then
                    error $EXIT_SUDO_PERMISSION "--shrink"
                fi
                RBUILD_SHRINK="true"
                ;;
            --compress)
                RBUILD_COMPRESSION="true"
                ;;
            -d|--debug)
                DEBOS_OPTIONS="-v --debug-shell --show-boot"
                RBUILD_DEBUG="true"
                ;;
            -r|--rootfs)
                DEBOS_ROOTFS="true"
                ;;
            -v|--no-vendor-package)
                INSTALL_VENDOR_PACKAGE="${1:-false}"
                shift
                ;;
            -k|--kernel)
                copy_kernel "$1"
                shift
                ;;
            -f|--firmware)
                copy_firmware "$1"
                shift
                ;;
            -c|--custom)
                local pkgs=(u-boot-$1_*.deb ../bsp/u-boot-$1_*.deb) pkg_found="false"
                if (( ${#pkgs[@]} > 0 ))
                then
                    pkg_found="true"
                    copy_firmware "${pkgs[0]}"
                fi
                pkgs=(linux-image-*-$1_*.deb ../bsp/linux-image-*-$1_*.deb)
                if (( ${#pkgs[@]} > 0 ))
                then
                    pkg_found="true"
                    copy_kernel "${pkgs[0]}"
                fi
                if $RBUILD_DEBUG
                then
                    pkgs=(linux-image-*-$1-dbg_*.deb ../bsp/linux-image-*-$1-dbg_*.deb)
                    if (( ${#pkgs[@]} > 0 ))
                    then
                        pkg_found="true"
                        copy_kernel_dbg "${pkgs[0]}"
                    fi
                fi
                if ! $pkg_found
                then
                    error $EXIT_UNKNOWN_OPTION "$1"
                fi
                shift
                ;;
            -n|--native-build)
                NATIVE_BUILD="true"
                RBUILD_AS_ROOT="true"
                ;;
            -t|--timestamp)
                RBUILD_TIMESTAMP="_${1:-${RBUILD_STARTING_TIME}_${PARTITION_TYPE}}"
                shift
                ;;
            -T|--test-repo)
                REPO_PREFIX="-test"
                ;;
            -o|--overlay)
                RBUILD_OVERLAY="$1"
                shift
                ;;
            -b|--backend)
                CONTAINER_BACKEND="$1"
                shift
                ;;
            --no-container-update)
                NO_CONTAINER_UPDATE="true"
                ;;
            -h|--help)
                usage
                return
                ;;
            --)
                break
                ;;
            *)
                error $EXIT_UNKNOWN_OPTION "$TEMP"
                ;;
        esac
    done

    if (( EUID == 0 )) && ! "$RBUILD_AS_ROOT"
    then
        error $EXIT_RBUILD_AS_ROOT
    fi

    if (( $# == 0))
    then
        usage
        return
    fi

    TEMP="$1"
    case "$TEMP" in
        shrink-image|write-image|json)
            shift
            "$TEMP" "$@"
            return
            ;;
    esac

    local DEBOS_TUPLE="$@"
    local BOARDS=($(get_supported_boards))
    local SUITES=($(get_supported_suites))
    local FLAVORS=($(get_supported_flavors))

    # Add hidden & non-officially supported options
    # Some of them will be broken!
    for i in "$SCRIPT_DIR"/configs/.*.conf
    do
        i="$(basename "$i")"
        BOARDS+=("${i%.conf}")
    done
    SUITES+=("focal" "buster" "bookworm")
    for i in "$SCRIPT_DIR"/common/flavors/.*.yaml
    do
        i="$(basename "$i")"
        FLAVORS+=("${i%.yaml}")
    done

    local BOARD=
    local SUITE=${SUITES[0]}
    local FLAVOR=${FLAVORS[0]}

    while (( $# > 0 ))
    do
        if in_array "$1" "${BOARDS[@]}"
        then
            BOARD="$1"
        elif in_array "$1" "${SUITES[@]}"
        then
            SUITE="$1"
        elif in_array "$1" "${FLAVORS[@]}"
        then
            FLAVOR="$1"
        else
            error $EXIT_UNKNOWN_OPTION "$1"
        fi
        shift
    done
    
    if ! ( in_array "$BOARD" "${BOARDS[@]}" && \
           in_array "$SUITE" "${SUITES[@]}" && \
           in_array "$FLAVOR" "${FLAVORS[@]}" )
    then
        error $EXIT_UNSUPPORTED_OPTION "$DEBOS_TUPLE"
    fi

    source "$SCRIPT_DIR/configs/$BOARD.conf"
    source "$SCRIPT_DIR/common/hw-info.conf"
    local SOC_FAMILY="$(get_soc_family $SOC)"
    local PARTITION_TYPE="$(get_partition_type $SOC_FAMILY)"

    if [[ -z "$RBUILD_OVERLAY" ]]
    then
        RBUILD_OVERLAY="${BOARD_OVERLAY:-}"
    fi

    case $SUITE in
        bullseye|buster|bookworm)
            local DISTRO="debian"
            ;;
        jammy|focal)
            local DISTRO="ubuntu"
            ;;
        *)
            error $EXIT_UNKNOWN_OPTION "$SUITE"
            ;;
    esac

    local ARCH="arm64"
    local IMAGE="${BOARD}_${DISTRO}_${SUITE}${REPO_PREFIX}_${FLAVOR}${RBUILD_TIMESTAMP}.img"
    local EFI_END=${EFI_END:-"332MiB"}
    
    # Release targeting image in case previous shrink failed
    if $RBUILD_SHRINK && [[ -e /dev/mapper/loop* ]]
    then
        sudo kpartx -d "$IMAGE"
    fi

    # Check /dev/kvm permission
    if [[ -c /dev/kvm && "$(stat -c "%A" /dev/kvm)" != "crw-rw-rw-" ]]
    then
        echo "KVM detected but the permission is not optimal."
        echo 'You might need to run `sudo chmod 0666 /dev/kvm` to have rbuild working.'
    fi

    if ! $NATIVE_BUILD
    then
        if [[ "$(basename "$CONTAINER_BACKEND")" == "docker" ]] && "$CONTAINER_BACKEND" -v | grep -q podman
        then
            echo "'$CONTAINER_BACKEND' backend is selected, but the functionality is actually provided by 'podman' backend. Updating accordingly..."
            CONTAINER_BACKEND="$(command -v podman)"
        fi

        if ! $NO_CONTAINER_UPDATE
        then
            $CONTAINER_BACKEND pull docker.io/godebos/debos:latest
        fi
    fi

    mkdir -p "$SCRIPT_DIR/.rootfs"

    if $DEBOS_ROOTFS || [[ ! -e "$SCRIPT_DIR/.rootfs/${DISTRO}_${SUITE}${REPO_PREFIX}_${FLAVOR}.tar" ]]
    then
        if $DEBOS_ROOTFS || [[ ! -e "$SCRIPT_DIR/.rootfs/${DISTRO}_${SUITE}${REPO_PREFIX}_base.tar" ]]
        then
            pushd "$SCRIPT_DIR"
            debos $DEBOS_OPTIONS "$SCRIPT_DIR/common/intermediate.yaml" \
                -t architecture:"$ARCH" \
                -t distro:"$DISTRO" -t suite:"$SUITE" -t repo_prefix:"$REPO_PREFIX"
            popd
        else
            echo "Using ${DISTRO}_${SUITE}${REPO_PREFIX}_base.tar intermediate rootfs."
        fi

        pushd "$SCRIPT_DIR"
        debos $DEBOS_OPTIONS "$SCRIPT_DIR/common/rootfs.yaml" \
            -t architecture:"$ARCH" \
            -t distro:"$DISTRO" -t suite:"$SUITE" -t flavor:"$FLAVOR" -t repo_prefix:"$REPO_PREFIX"
        popd
    else
        echo "Using ${DISTRO}_${SUITE}${REPO_PREFIX}_${FLAVOR}.tar rootfs."
    fi

    if [[ "$BOARD" == "rootfs" ]]
    then
        return
    fi

    debos $DEBOS_OPTIONS "$SCRIPT_DIR/common/image.yaml" \
        -t architecture:"$ARCH" \
        -t board:"$BOARD" -t distro:"$DISTRO" -t suite:"$SUITE" -t flavor:"$FLAVOR" \
        -t soc:"$SOC" -t soc_family:"$SOC_FAMILY" -t repo_prefix:"$REPO_PREFIX" \
        -t image:"$IMAGE" -t efi_end:"$EFI_END" -t partition_type:"$PARTITION_TYPE" \
        -t kernel:"$RBUILD_KERNEL" -t kernel_dbg:"$RBUILD_KERNEL_DBG" -t header:"$RBUILD_HEADER" -t firmware:"$RBUILD_FIRMWARE" \
        -t install_vendor_package:"$INSTALL_VENDOR_PACKAGE" -t overlay:"$RBUILD_OVERLAY" \
        -t dkms:"${BOARD_DKMS:-}" \
        -t rbuild_rev:"$(git rev-parse HEAD)$(git diff --quiet || echo '-dirty')" -t rbuild_cmd:"./rbuild ${ARGV[*]}"

    if $RBUILD_SHRINK
    then
        if ! sudo -n true 2>/dev/null
        then
            $NOTIFY_SEND "rbuild is waiting for user input."
            echo "rbuild shrink needs root permission to perform partition operations."
            echo "The process is paused to prevent sudo timeout on asking for password."
            read -p "Please press enter to continue..." i
        fi
        shrink-image "$IMAGE"
    fi

    sha512sum "$IMAGE" > "$IMAGE.sha512"
    chown $USER: "$IMAGE"
    
    if $RBUILD_COMPRESSION
    then
        xz -fT 0 "$IMAGE"
    fi
}

set -euo pipefail
shopt -s nullglob

LC_ALL="C"
LANG="C"
LANGUAGE="C"
PATH="/usr/sbin:$PATH"

if command -v notify-send &>/dev/null && dbus-send --session \
    --dest=org.freedesktop.Notifications --print-reply \
    /org/freedesktop/Notifications org.freedesktop.DBus.Peer.Ping &>/dev/null
then
    NOTIFY_SEND=notify-send
else
    NOTIFY_SEND=echo
fi

SECONDS=0
RBUILD_SHOW_EXECUTION_TIME="true"
RBUILD_STARTING_TIME="$(date --iso-8601=m | tr -d :)"

main "$@"

if $RBUILD_SHOW_EXECUTION_TIME
then
    $NOTIFY_SEND "rbuild is finished."
    echo "Execution started at $RBUILD_STARTING_TIME"
    TZ=UTC0 printf 'Total execution time: %(%H:%M:%S)T\n' $SECONDS
fi
