#!/bin/bash
# shellcheck disable=SC2034  # Unused variables left for readability

set -e # -e: exit on error

##################################################################################################################
# printf Colors and Formats

# General Formatting
FORMAT_RESET=$'\e[0m'
FORMAT_BRIGHT=$'\e[1m'
FORMAT_DIM=$'\e[2m'
FORMAT_ITALICS=$'\e[3m'
FORMAT_UNDERSCORE=$'\e[4m'
FORMAT_BLINK=$'\e[5m'
FORMAT_REVERSE=$'\e[7m'
FORMAT_HIDDEN=$'\e[8m'

# Foreground Colors
TEXT_BLACK=$'\e[30m'
TEXT_RED=$'\e[31m'    # Warning
TEXT_GREEN=$'\e[32m'  # Command Completed
TEXT_YELLOW=$'\e[33m' # Recommended Commands / Extras
TEXT_BLUE=$'\e[34m'
TEXT_MAGENTA=$'\e[35m'
TEXT_CYAN=$'\e[36m' # Info Needs
TEXT_WHITE=$'\e[37m'

# Background Colors
BACKGROUND_BLACK=$'\e[40m'
BACKGROUND_RED=$'\e[41m'
BACKGROUND_GREEN=$'\e[42m'
BACKGROUND_YELLOW=$'\e[43m'
BACKGROUND_BLUE=$'\e[44m'
BACKGROUND_MAGENTA=$'\e[45m'
BACKGROUND_CYAN=$'\e[46m'
BACKGROUND_WHITE=$'\e[47m'

# Example Usage
# printf ' %sThis is a warning%s\n' "$TEXT_RED" "$FORMAT_RESET"
# printf ' %s%sInfo:%s Details here\n' "$FORMAT_UNDERSCORE" "$TEXT_CYAN" "$FORMAT_RESET"

##################################################################################################################

# --- Prevent running inside a Lima VM ---
if [ -f /run/lima-boot-done ] || [ -n "$LIMA_INSTANCE" ]; then
    printf "%s [ERROR] This script must be run on the host, not inside a Lima VM. Exiting.%s\n" "$TEXT_RED" "$FORMAT_RESET"
    exit 1
fi

while [ -n "$1" ]; do
    case "$1" in
    -v | --version)
        shift
        Version_Number="$1"
        ;;
    -s | --sid)
        shift
        debian_sid="true"
        ;;
    -k | --kill)
        printf " %s Killing build-arch VM...%s\n" "$TEXT_GREEN" "$FORMAT_RESET"
        limactl delete --force build-arch
        ;;
    *)
        printf " %s Unknown option %s%s\n" "$TEXT_RED" "$1" "$FORMAT_RESET"
        exit 1
        ;;
    esac
    shift
done

VM_NAME="build-arch"
BUILD_SUFFIX="${Version_Number:-0}"
IMAGE_NAME="Arch-Linux-aarch64-cloudimg-$(date '+%Y%m%d').${BUILD_SUFFIX}.img"
QCOW2_IMG_FILE="${IMAGE_NAME%.img}.qcow2.xz"
VMDK_IMG_FILE="${IMAGE_NAME%.img}.vmdk.xz"

[[ -f /tmp/lima/output/"$IMAGE_NAME" ]] && rm -f /tmp/lima/output/"$IMAGE_NAME"
[[ -f /tmp/lima/output/"$QCOW2_IMG_FILE" ]] && rm -f /tmp/lima/output/"$QCOW2_IMG_FILE"
[[ -f /tmp/lima/output/"$VMDK_IMG_FILE" ]] && rm -f /tmp/lima/output/"$VMDK_IMG_FILE"

# echo "Version Number: $Version_Number"
# exit 0

# check if build VM exists and running
if ! limactl list | grep -E "(^|[[:space:]])$VM_NAME([[:space:]]|$)" | grep -q Running; then
    printf " %s Starting $VM_NAME VM...%s\n" "$TEXT_GREEN" "$FORMAT_RESET"
    if [ "$debian_sid" == "true" ]; then
        limactl start --yes --containerd none --cpus 12 --memory 16 --disk 10 --name "$VM_NAME" template://experimental/debian-sid
    else
        limactl start --yes --containerd none --cpus 12 --memory 16 --disk 10 --name "$VM_NAME" template://ubuntu
    fi
else
    printf "%s %s VM is already running%s\n" "$TEXT_GREEN" "$VM_NAME" "$FORMAT_RESET"
fi

printf "%s Starting create-image.sh in %s VM%s\n" "$TEXT_GREEN" "$VM_NAME" "$FORMAT_RESET"
limactl shell "$VM_NAME" BUILD_SUFFIX="$Version_Number" ./create-image.sh

printf "%s Creating archlinux.yaml for lima-vm%s\n" "$TEXT_GREEN" "$FORMAT_RESET"
./create-archlinux-template.sh
