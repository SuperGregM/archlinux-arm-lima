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

VM_NAME="build-arch"

# --- Prevent running inside a Lima VM ---
if [ -f /run/lima-boot-done ] || [ -n "$LIMA_INSTANCE" ]; then
    printf "%s [ERROR] This script must be run on the host, not inside a Lima VM. Exiting.%s\n" "$TEXT_RED" "$FORMAT_RESET"
    exit 1
fi

# --- Check if limactl is installed ---
if ! command -v limactl >/dev/null 2>&1; then
    printf "%s [ERROR] limactl is not installed or not in PATH. Exiting.%s\n" "$TEXT_RED" "$FORMAT_RESET"
    exit 1
fi

while [ -n "$1" ]; do
    case "$1" in
    -v | --version)
        shift
        Version_Number="$1"
        ;;
    -c | --compress)
        shift
        COMPRESS="$1"
        ;;
    -s | --sid)
        USE_DEBIAN_SID="true"
        VM_NAME="build-arch-sid"
        ;;
    -k | --kill)
        DELETE_EXISTING_VM="true"
        ;;
    *)
        printf " %s Unknown option %s%s\n" "$TEXT_RED" "$1" "$FORMAT_RESET"
        printf " %s Usage: %s\n build.sh [-v <version>] [-c <compress>] [-s] [-k]" "$TEXT_YELLOW" "$FORMAT_RESET"
        printf "\n Options:\n"
        printf "   -%sv%s  --%sversion%s <#>    Set a custom version suffix for the image filename (default: 0)\n" "$TEXT_YELLOW" "$FORMAT_RESET" "$TEXT_YELLOW" "$FORMAT_RESET"
        printf "   -%sc%s  --%scompress%s <0|1> Enable or disable compression (default: 1 Enabled)\n" "$TEXT_YELLOW" "$FORMAT_RESET" "$TEXT_YELLOW" "$FORMAT_RESET"
        printf "   -%ss%s  --%ssid%s            Use Debian Sid template instead of Ubuntu\n" "$TEXT_YELLOW" "$FORMAT_RESET" "$TEXT_YELLOW" "$FORMAT_RESET"
        printf "   -%sk%s  --%skill%s           Force delete the existing \"build-arch\" Lima VM\n" "$TEXT_YELLOW" "$FORMAT_RESET" "$TEXT_YELLOW" "$FORMAT_RESET"
        exit 1
        ;;
    esac
    shift
done

BUILD_SUFFIX="${Version_Number:-0}"
IMAGE_NAME="Arch-Linux-aarch64-cloudimg-$(date '+%Y%m%d').${BUILD_SUFFIX}.img"
IMAGE_FILE="$IMAGE_NAME.xz"
QCOW2_IMG_FILE="${IMAGE_NAME%.img}.qcow2.xz"
VMDK_IMG_FILE="${IMAGE_NAME%.img}.vmdk.xz"
WORKDIR=/tmp/lima/output

mkdir -p "$WORKDIR"

[[ -f "$WORKDIR/$IMAGE_NAME" ]] && rm -f "$WORKDIR/$IMAGE_NAME"
[[ -f "$WORKDIR/$IMAGE_FILE" ]] && rm -f "$WORKDIR/$IMAGE_FILE"
[[ -f "$WORKDIR/$QCOW2_IMG_FILE" ]] && rm -f "$WORKDIR/$QCOW2_IMG_FILE"
[[ -f "$WORKDIR/$VMDK_IMG_FILE" ]] && rm -f "$WORKDIR/$VMDK_IMG_FILE"

if [ "$DELETE_EXISTING_VM" = "true" ]; then
    if limactl list "$VM_NAME" 2>/dev/null; then
        printf " %s Killing $VM_NAME VM...%s\n" "$TEXT_GREEN" "$FORMAT_RESET"
        limactl delete --force "$VM_NAME"
    fi
fi

# check if build VM exists and running
Build_VM=$(limactl list 2>/dev/null)
VM_STATE=$(echo "$Build_VM" | awk -v vm="$VM_NAME" '$1 == vm {print $2}')
if [ -z "$VM_STATE" ]; then
    printf " %s Creating $VM_NAME VM...%s\n" "$TEXT_GREEN" "$FORMAT_RESET"
    if [ "$USE_DEBIAN_SID" == "true" ]; then
        limactl start --yes --containerd none --cpus 12 --memory 16 --disk 10 --name "$VM_NAME" template:experimental/debian-sid --mount "$WORKDIR":w
    else
        limactl start --yes --containerd none --cpus 12 --memory 16 --disk 10 --name "$VM_NAME" template:ubuntu --mount "$WORKDIR":w
    fi
elif [ "$VM_STATE" = "Running" ]; then
    printf "%s %s VM is already running%s\n" "$TEXT_GREEN" "$VM_NAME" "$FORMAT_RESET"
elif [ "$VM_STATE" = "Stopped" ]; then
    printf "%s Starting stopped $VM_NAME VM...%s\n" "$TEXT_GREEN" "$FORMAT_RESET"
    limactl start "$VM_NAME"
else
    printf "%s Unknown VM state for %s (%s)%s\n" "$TEXT_RED" "$VM_NAME" "$VM_STATE" "$FORMAT_RESET"
    exit 1
fi

printf "%s Starting create-image.sh in %s VM%s\n" "$TEXT_GREEN" "$VM_NAME" "$FORMAT_RESET"
limactl shell "$VM_NAME" BUILD_SUFFIX="$Version_Number" COMPRESS="$COMPRESS" ./create-image.sh

printf "%s Creating archlinux.yaml for lima-vm%s\n" "$TEXT_GREEN" "$FORMAT_RESET"
./create-archlinux-template.sh
