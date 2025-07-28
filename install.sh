#!/bin/bash
set -euo pipefail

read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -s -p "Enter password for root: " ROOT_PASSWORD; echo
read -s -p "Enter password for $USERNAME: " USER_PASSWORD; echo
read -s -p "Enter disk encryption password: " LUKS_PASSWORD; echo

DISK="/dev/nvme0n1"
EFI="${DISK}p1"
ROOT="${DISK}p2"
LUKS_NAME="main"
LOCALE="en_PH.UTF-8"
TIMEZONE="Asia/Manila"
SVOL_ROOT="@"
SVOL_HOME="@home"

sgdisk --zap-all "$DISK"
wipefs -a "$DISK"
parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart ESP fat32 1MiB 1025MiB
parted "$DISK" -- set 1 esp on
parted "$DISK" -- mkpart primary 1025MiB 100%

mkfs.fat -F32 "$EFI"
echo "$LUKS_PASSWORD" | cryptsetup luksFormat --type luks2 --batch-mode "$ROOT" -
echo "$LUKS_PASSWORD" | cryptsetup open "$ROOT" "$LUKS_NAME" -

mkfs.btrfs /dev/mapper/$LUKS_NAME
mount /dev/mapper/$LUKS_NAME /mnt
btrfs su cr /mnt/$SVOL_ROOT
btrfs su cr /mnt/$SVOL_HOME
umount /mnt

mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SVOL_ROOT /dev/mapper/$LUKS_NAME /mnt
mkdir /mnt/home
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SVOL_HOME /dev/mapper/$LUKS_NAME /mnt/home
mkdir /mnt/boot
mount "$EFI" /mnt/boot

pacstrap /mnt base linux linux-firmware linux-headers sudo neovim man-db man-pages \
networkmanager hyprland xdg-desktop-portal-hyprland sddm alacritty ttf-jetbrains-mono-nerd \
bluez bluez-utils firewalld acpid pipewire wireplumber base-devel grub efibootmgr intel-ucode

genfstab -U /mnt >> /mnt/etc/fstab

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
echo "$USERNAME ALL=(ALL) ALL" > /etc/sudoers.d/$USERNAME
chmod 0440 /etc/sudoers.d/$USERNAME

sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

UUID=\$(blkid -s UUID -o value "$ROOT")
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$UUID:$LUKS_NAME root=/dev/mapper/$LUKS_NAME quiet splash loglevel=3\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
systemctl enable firewalld
systemctl enable bluetooth
systemctl enable acpid
systemctl enable sddm
EOF

echo "✅ Installation finished. You can now reboot."
