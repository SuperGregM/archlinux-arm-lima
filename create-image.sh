#!/usr/bin/env bash
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

# Prevent running on macOS (Darwin)
if [[ "$(uname)" == "Darwin" ]]; then
    echo "[ERROR] This script must be run inside a Linux environment (e.g., a Lima VM)."
    echo "macOS lacks required tools and kernel features. Exiting for safety."
    exit 1
fi

# Only allow Debian/Ubuntu or Arch Linux
if ! { [ -f /etc/lsb-release ] || [ -x "$(command -v apt-get)" ]; }; then
    printf "%s[ERROR] This script supports only Debian/Ubuntu. Exiting.%s\n" "$TEXT_RED" "$FORMAT_RESET"
    exit 1
fi

printf '%s Starting Arch Linux ARM image build...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"

# --- Dependency checks (Debian/Ubuntu only) ---
declare -A pkg_map=(
    ["arch-chroot"]=arch-install-scripts
    ["update-ca-certificates"]=ca-certificates
    ["curl"]=curl
    ["mkfs.fat"]=dosfstools
    ["makepkg"]=makepkg
    ["pacman"]=pacman-package-manager
    ["parted"]=parted
    ["qemu-img"]=qemu-utils
    ["xz"]=xz-utils
    ["zstd"]=zstd
)

missing_pkgs=()
for cmd in "${!pkg_map[@]}"; do
    pkg="${pkg_map[$cmd]}"
    printf '%s Checking for %s (provided by %s)...%s\n' "$TEXT_GREEN" "$cmd" "$pkg" "$FORMAT_RESET"
    if ! command -v "$cmd" &>/dev/null; then
        printf '%s%s not found, will install package %s...%s\n' "$TEXT_YELLOW" "$cmd" "$pkg" "$FORMAT_RESET"
        missing_pkgs+=("$pkg")
    else
        printf '%s%s already present.%s\n' "$TEXT_GREEN" "$cmd" "$FORMAT_RESET"
    fi
done

if [ "${#missing_pkgs[@]}" -gt 0 ]; then
    printf '%s Installing missing packages: %s...%s\n' "$TEXT_YELLOW" "${missing_pkgs[*]}" "$FORMAT_RESET"
    sudo apt-get update
    sudo apt-get install --yes -qq --no-install-recommends "${missing_pkgs[@]}"
    # Verify install
    for cmd in "${!pkg_map[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            printf '%s ERROR: %s still not found after installing %s!%s\n' "$TEXT_RED" "$cmd" "${pkg_map[$cmd]}" "$FORMAT_RESET"
            exit 1
        fi
    done
    printf '%s All missing packages installed successfully.%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
fi

# --- Static configuration ---
BUILD_SUFFIX="${BUILD_SUFFIX:-0}"
IMAGE_NAME="Arch-Linux-aarch64-cloudimg-$(date '+%Y%m%d').${BUILD_SUFFIX}.img"
COMPRESS=1
WORKDIR=/tmp/lima/output

printf '%s Editing pacman.conf to add Archlinux ARM mirrorlist...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
if ! grep -q "^\[alarm\]" /etc/pacman.conf || ! grep -q "^Include = /etc/pacman.d/mirrorlist" /etc/pacman.conf; then
    sudo tee -a /etc/pacman.conf >/dev/null <<'PACMAN_CONF'
[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[community]
Include = /etc/pacman.d/mirrorlist

[alarm]
Include = /etc/pacman.d/mirrorlist

[aur]
Include = /etc/pacman.d/mirrorlist
PACMAN_CONF
else
    printf '%s Pacman configuration already includes Archlinux ARM mirrorlist.%s\n' "$TEXT_YELLOW" "$FORMAT_RESET"
fi
sudo mkdir -p /etc/pacman.d
MIRRORLIST_URL="https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/master/core/pacman-mirrorlist/mirrorlist"
curl -L "$MIRRORLIST_URL" | sed -E 's/^\s*#\s*Server\s*=/Server =/g' | sudo tee /etc/pacman.d/mirrorlist >/dev/null
sudo sed -i 's/\$arch/aarch64/g' /etc/pacman.d/mirrorlist

printf '%s Adding Archlinux ARM keyring...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
# Download and install the Archlinux ARM keyring
EXTRA_KEYRING_FILES="
    archlinuxarm-revoked
    archlinuxarm-trusted
    archlinuxarm.gpg
"
EXTRA_KEYRING_URL="https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/master/core/archlinuxarm-keyring/"
for EXTRA_KEYRING_FILE in $EXTRA_KEYRING_FILES; do
    if [ -f "/usr/share/keyrings/$EXTRA_KEYRING_FILE" ]; then
        printf '%s%s already exists, skipping download.%s\n' "$TEXT_YELLOW" "$EXTRA_KEYRING_FILE" "$FORMAT_RESET"
        continue
    else
        printf '%s Downloading %s...%s\n' "$TEXT_GREEN" "$EXTRA_KEYRING_FILE" "$FORMAT_RESET"
        sudo mkdir -p /usr/share/keyrings
        sudo curl "$EXTRA_KEYRING_URL$EXTRA_KEYRING_FILE" -o /usr/share/keyrings/"$EXTRA_KEYRING_FILE" -L
    fi
done

# --- Preparation ---
printf '%s Creating output directory...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
mkdir -p $WORKDIR
cd $WORKDIR

printf '%s Creating image file...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
truncate -s 4G "$IMAGE_NAME"

printf '%s Setting up loop device...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
LOOPDEV=$(sudo losetup -fP --show "$IMAGE_NAME")

printf '%s Partitioning image...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
sudo parted -s "$LOOPDEV" mklabel gpt
sudo parted -s "$LOOPDEV" mkpart ESP fat32 1MiB 513MiB
sudo parted -s "$LOOPDEV" set 1 boot on
sudo parted -s "$LOOPDEV" set 1 esp on
sudo parted -s "$LOOPDEV" mkpart primary ext4 513MiB 100%
sudo parted -s "$LOOPDEV" name 1 BOOT
sudo parted -s "$LOOPDEV" name 2 ROOT

printf '%s Formatting partitions...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
BOOTP="${LOOPDEV}p1"
ROOTP="${LOOPDEV}p2"
sudo mkfs.fat -F32 "$BOOTP"
sudo mkfs.ext4 -E lazy_itable_init=1,lazy_journal_init=1 "$ROOTP"

printf '%s Mounting partitions...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
sudo mkdir -p /mnt/arch-root
sudo mount "$ROOTP" /mnt/arch-root
sudo mkdir -p /mnt/arch-root/boot
sudo mount "$BOOTP" /mnt/arch-root/boot

printf '%s Installing base system...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
sudo pacman-key --init
sudo pacman-key --populate

sudo pacstrap /mnt/arch-root base linux-aarch64 archlinuxarm-keyring

# alarm's linux-aarch64 kernel workaround
if [ -f /mnt/arch-root/boot/Image ]; then
    sudo mv /mnt/arch-root/boot/Image /mnt/arch-root/boot/vmlinuz-linux
fi

printf "%s Setting up Arch environment ...%s\n" "$TEXT_GREEN" "$FORMAT_RESET"
sudo arch-chroot /mnt/arch-root /bin/bash <<'CHROOT'
# --- Color output ---
TEXT_RED=$'\e[31m'    # Warning
TEXT_GREEN=$'\e[32m'  # Command Completed
TEXT_YELLOW=$'\e[33m' # Recommended Commands / Extras
FORMAT_RESET=$'\e[0m'

printf '%s Setting timezone and locale ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

printf '%s Setting hardware clock ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >/etc/locale.gen
echo "LANG=en_US.UTF-8" >/etc/locale.conf
locale-gen

printf '%s Setting /etc/hostname ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
echo "archarm" >/etc/hostname

PARTUUID_ROOT=$(blkid -s PARTUUID -o value /dev/disk/by-partlabel/ROOT)
PARTUUID_BOOT=$(blkid -s PARTUUID -o value /dev/disk/by-partlabel/BOOT)
printf '%s Setting up /etc/fstab ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
cat <<FSTAB >>/etc/fstab
PARTUUID=$PARTUUID_ROOT  /       ext4    defaults,noatime    0 1
PARTUUID=$PARTUUID_BOOT  /boot   vfat    defaults            0 2
FSTAB

printf '%s Setting up pacman ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
pacman-key --init
pacman-key --populate archlinuxarm

printf "%s Setting up bootloader (systemd-boot) ...%s\n" "$TEXT_GREEN" "$FORMAT_RESET"
bootctl install --esp-path=/boot

printf '%s Creating loader.conf ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
cat <<EOF >/boot/loader/loader.conf
default arch
timeout 0
console-mode max
EOF

printf '%s Creating entry for Arch Linux ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
cat <<EOF >/boot/loader/entries/arch.conf
title   Arch Linux ARM
efi     /vmlinuz-linux
options root=PARTUUID=$PARTUUID_ROOT rw console=ttyAMA0 rootwait
initrd  /initramfs-linux.img
EOF

printf '%s Installing cloud-guest-utils ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
pacman -Sy cloud-guest-utils --needed --noconfirm

printf '%s Installing cloud-init ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
CLOUD_INIT_PKG="cloud-init-25.1.2-1-any.pkg.tar.zst"
curl -LO --output-dir /tmp/ "https://archive.archlinux.org/packages/c/cloud-init/$CLOUD_INIT_PKG"
pacman -U /tmp/"$CLOUD_INIT_PKG" --needed --noconfirm
rm -f /tmp/"$CLOUD_INIT_PKG"

printf '%s Enabling cloud-init services ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
systemctl enable cloud-init-main.service
systemctl enable cloud-final.service

printf '%s Setting up network configuration ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
mkdir -p /etc/systemd/network
cat <<EOF >/etc/systemd/network/20-wired.network
[Match]
Name=e*             # Match Ethernet interfaces

[Network]
DHCP=yes            # Enable DHCP for automatic IP configuration
DNSSEC=no
EOF

printf '%s Enabling systemd-networkd and systemd-resolved services ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service

printf '%s Installing OpenSSH ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
pacman -Sy openssh --needed --noconfirm

printf '%s Enabling OpenSSH Daemon ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
systemctl enable sshd.service

printf '%s Clearing package cache ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
printf "y\ny\n" | pacman -Scc
CHROOT

# --- Zero out free space in root partition to improve compressibility ---
printf '%s Zeroing out free space in root partition ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
sudo dd if=/dev/zero of=/mnt/arch-root/zero.fill bs=1M status=progress || true
sudo sync
sudo rm -f /mnt/arch-root/zero.fill

# --- Unmount boot if still mounted ---
printf '%s Unmounting boot partition ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
if mountpoint -q /mnt/arch-root/boot; then
    sudo umount /mnt/arch-root/boot || sudo umount -l /mnt/arch-root/boot
fi

# --- Unmount partitions ---
printf '%s Unmounting root partition ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
sudo umount /mnt/arch-root || sudo umount -l /mnt/arch-root

sudo losetup --detach "$LOOPDEV"

# --- Create VM images ---
RAW_IMG="$IMAGE_NAME"
QCOW2_IMG="${IMAGE_NAME%.img}.qcow2"
VMDK_IMG="${IMAGE_NAME%.img}.vmdk"

printf '%s Creating VM images ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
sudo qemu-img convert -p -O qcow2 "$RAW_IMG" "$QCOW2_IMG"
sudo qemu-img convert -p -O vmdk "$RAW_IMG" "$VMDK_IMG"

if [ "$COMPRESS" = 1 ]; then
    printf '%s Compressing images ...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
    sudo xz -T 0 --verbose "$RAW_IMG"
    sudo xz -T 0 --verbose "$QCOW2_IMG"
    sudo xz -T 0 --verbose "$VMDK_IMG"
fi

printf '%s All images created:%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
if [ "$COMPRESS" = 1 ]; then
    echo "  Raw:   $RAW_IMG.xz"
    echo "  QCOW2: $QCOW2_IMG.xz"
    echo "  VMDK:  $VMDK_IMG.xz"
else
    echo "  Raw:   $RAW_IMG"
    echo "  QCOW2: $QCOW2_IMG"
    echo "  VMDK:  $VMDK_IMG"
fi
printf '%s Static build finished.%s\n' "$TEXT_GREEN" "$FORMAT_RESET"

exit 0
