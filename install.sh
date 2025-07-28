#!/bin/bash
set -euo pipefail

# Check dependencies
for cmd in sgdisk cryptsetup mkfs.btrfs btrfs mkfs.fat pacstrap genfstab arch-chroot; do
    command -v $cmd > /dev/null || { echo "$cmd not found. Install it first."; exit 1; }
done

echo "Enter target NVMe disk (e.g., /dev/nvme0n1):"
read -r DISK
echo "Enter hostname:"
read -r HOSTNAME
echo "Enter username:"
read -r USERNAME

read -rsp "Enter root password: " ROOT_PASSWORD; echo
read -rsp "Enter user password: " USER_PASSWORD; echo
read -rsp "Enter LUKS password: " LUKS_PASSWORD; echo

EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"
LUKS_NAME="cryptroot"
LOCALE="en_PH.UTF-8"
TIMEZONE="Asia/Manila"
SUBVOL_ROOT="@"
SUBVOL_HOME="@home"

# Partition the disk
sgdisk -Z "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 "$DISK"
sgdisk -n 2:0:0 "$DISK"

# Set up encryption
echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" --type luks2 --batch-mode --key-file=-
echo -n "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" "$LUKS_NAME" --key-file=-

# Format and create subvolumes
mkfs.btrfs "/dev/mapper/$LUKS_NAME"
mount "/dev/mapper/$LUKS_NAME" /mnt
btrfs subvolume create /mnt/$SUBVOL_ROOT
btrfs subvolume create /mnt/$SUBVOL_HOME
umount /mnt

# Mount subvolumes
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SUBVOL_ROOT "/dev/mapper/$LUKS_NAME" /mnt
mkdir /mnt/home
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SUBVOL_HOME "/dev/mapper/$LUKS_NAME" /mnt/home

# EFI partition
mkfs.fat -F32 "$EFI_PART"
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# Install base system and desktop packages
pacstrap /mnt base linux linux-firmware linux-headers networkmanager sudo neovim man-db man-pages hyprland xdg-desktop-portal-hyprland bluez bluez-utils firewalld acpid pipewire wireplumber base-devel sddm alacritty ttf-jetbrains-mono-nerd

mkdir -p /mnt/etc
genfstab -U /mnt >> /mnt/etc/fstab

# Get UUID before chroot
UUID=$(blkid -s UUID -o value "$ROOT_PART")

arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
pacman -S grub efibootmgr intel-ucode --noconfirm
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="cryptdevice=UUID=$UUID:$LUKS_NAME root=/dev/mapper/$LUKS_NAME quiet"|' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager
systemctl enable firewalld
systemctl enable bluetooth
systemctl enable acpid
systemctl enable sddm
EOF

echo "Install complete. You can reboot now."
