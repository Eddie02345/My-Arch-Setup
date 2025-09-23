#!/bin/bash
# Arch Linux Installer - Base + Hyprland
# Works with NVMe and SATA disks
# Run from Arch live ISO

set -euo pipefail

echo "=== Arch Linux Hyprland Installer ==="

# --------------------------
# List available disks
# --------------------------
echo "Detecting disks..."
lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E "disk"

# Prompt user until a valid disk is given
while true; do
    read -rp "Enter target disk (e.g., /dev/sda or /dev/nvme0n1): " DISK
    if [[ -b "$DISK" ]]; then
        echo "Selected disk: $DISK"
        break
    else
        echo "Invalid disk. Please enter a valid block device (e.g., /dev/sda)."
    fi
done

# --------------------------
# Prompt for other info
# --------------------------
read -rp "Enter hostname: " HOSTNAME
read -rp "Enter username: " USERNAME
read -rsp "Enter root password: " ROOT_PASSWORD; echo
read -rsp "Enter user password: " USER_PASSWORD; echo
read -rsp "Enter LUKS password: " LUKS_PASSWORD; echo

# --------------------------
# Partitioning
# --------------------------
EFI_PART="${DISK}1"
ROOT_PART="${DISK}2"
LUKS_NAME="cryptroot"

echo "Partitioning $DISK..."
sgdisk -Z "$DISK"  # wipe
sgdisk -n 1:0:+1G -t 1:ef00 "$DISK"  # EFI
sgdisk -n 2:0:0 "$DISK"             # root

# --------------------------
# Encrypt root partition
# --------------------------
echo "Setting up LUKS encryption on $ROOT_PART..."
echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" --type luks2 --batch-mode
echo -n "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" "$LUKS_NAME" --key-file=-

# --------------------------
# Format Btrfs and create subvolumes
# --------------------------
echo "Formatting Btrfs and creating subvolumes..."
mkfs.btrfs "/dev/mapper/$LUKS_NAME"
mount "/dev/mapper/$LUKS_NAME" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

# Mount subvolumes
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@ "/dev/mapper/$LUKS_NAME" /mnt
mkdir -p /mnt/home
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@home "/dev/mapper/$LUKS_NAME" /mnt/home

# EFI
mkfs.fat -F32 "$EFI_PART"
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# --------------------------
# Reflector - speed up mirrors
# --------------------------
pacman -Sy --noconfirm reflect
