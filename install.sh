#!/bin/bash
# Arch Linux Installer - Base + Hyprland
# Run from Arch live ISO
# Works with both NVMe and SATA disks

set -euo pipefail

# --------------------------
# Helper function: list disks
# --------------------------
list_disks() {
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL | grep -E "sd|nvme"
}

# --------------------------
# Prompt user for basic info
# --------------------------
echo "Arch Linux Installer (Hyprland)"

# Show available disks
list_disks

read -rp "Enter target disk (e.g., /dev/sda or /dev/nvme0n1): " DISK

read -rp "Enter hostname: " HOSTNAME
read -rp "Enter username: " USERNAME
read -rsp "Enter root password: " ROOT_PASSWORD; echo
read -rsp "Enter user password: " USER_PASSWORD; echo
read -rsp "Enter LUKS password: " LUKS_PASSWORD; echo

# --------------------------
# Disk partitioning
# --------------------------
EFI_PART="${DISK}1"
ROOT_PART="${DISK}2"
LUKS_NAME="cryptroot"

echo "Partitioning disk: $DISK"
sgdisk -Z "$DISK"               # Wipe
sgdisk -n 1:0:+1G -t 1:ef00 "$DISK"  # EFI
sgdisk -n 2:0:0 "$DISK"              # Root

# --------------------------
# LUKS encryption
# --------------------------
echo "Setting up LUKS encryption on $ROOT_PART"
echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" --type luks2 --batch-mode
echo -n "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" "$LUKS_NAME" --key-file=-

# --------------------------
# Btrfs formatting & subvolumes
# --------------------------
echo "Formatting Btrfs and creating subvolumes"
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
# Reflector: speed up mirrors
# --------------------------
pacman -Sy --noconfirm reflector
reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

# --------------------------
# Base system + Hyprland essentials
# --------------------------
pacstrap /mnt base linux linux-firmware linux-headers networkmanager sudo neovim man-db man-pages base-devel sddm hyprland alacritty ttf-jetbrains-mono-nerd

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# --------------------------
# Chroot configuration
# --------------------------
arch-chroot /mnt /bin/bash <<EOF
set -e

# Timezone & clock
ln -sf /usr/share/zoneinfo/Asia/Manila /etc/localtime
hwclock --systohc

# Hostname & users
echo "$HOSTNAME" > /etc/hostname
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# mkinitcpio for Btrfs + encryption
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Install GRUB
pacman -S --noconfirm grub efibootmgr intel-ucode
UUID=$(blkid -s UUID -o value "$ROOT_PART")
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$UUID:$LUKS_NAME root=/dev/mapper/$LUKS_NAME quiet\"|" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable essential services
systemctl enable NetworkManager
systemctl enable sddm

# Install paru-bin (prebuilt binary)
pacman -S --noconfirm git base-devel
git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin
makepkg -si --noconfirm
EOF

echo "Base installation complete. Reboot and run post-install script after first login."
