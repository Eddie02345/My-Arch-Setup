#!/bin/bash

set -e

# ========== USER PROMPTS ==========
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME

echo -n "Enter password for root: "
read -s ROOT_PASSWORD
echo

echo -n "Enter password for $USERNAME: "
read -s USER_PASSWORD
echo

echo -n "Enter LUKS disk encryption password: "
read -s LUKS_PASSWORD
echo

# ========== STATIC CONFIG ==========
DISK="/dev/nvme0n1"
EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"
LUKS_NAME="main"
LOCALE="en_PH.UTF-8"
TIMEZONE="Asia/Manila"
SUBVOL_ROOT="@"
SUBVOL_HOME="@home"

# ========== PARTITIONING ==========
echo "==> Partitioning disk..."
sgdisk -Z "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 "$DISK"     # 1 GiB EFI partition
sgdisk -n 2:0:0 "$DISK"                 # Remaining = root

# ========== ENCRYPTION ==========
echo "==> Setting up encryption and Btrfs..."
echo "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" -
echo "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" "$LUKS_NAME" -

mkfs.btrfs /dev/mapper/$LUKS_NAME
mount /dev/mapper/$LUKS_NAME /mnt
btrfs subvolume create /mnt/$SUBVOL_ROOT
btrfs subvolume create /mnt/$SUBVOL_HOME
umount /mnt

mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SUBVOL_ROOT /dev/mapper/$LUKS_NAME /mnt
mkdir /mnt/home
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SUBVOL_HOME /dev/mapper/$LUKS_NAME /mnt/home

# ========== EFI BOOT ==========
mkfs.fat -F32 "$EFI_PART"
mkdir /mnt/boot
mount "$EFI_PART" /mnt/boot

# ========== BASE INSTALL ==========
echo "==> Installing base system and packages..."
reflector -c Singapore -a 12 --sort rate --save /etc/pacman.d/mirrorlist
pacstrap /mnt base linux linux-headers linux-firmware \
  networkmanager sudo vim neovim man-db man-pages \
  hyprland xdg-desktop-portal-hyprland \
  bluez bluez-utils firewalld acpid pipewire wireplumber base-devel \
  sddm alacritty ttf-jetbrains-mono-nerd

genfstab -U /mnt >> /mnt/etc/fstab

# ========== CHROOT SETUP ==========
echo "==> Configuring system inside chroot..."
arch-chroot /mnt /bin/bash <<EOF
# Timezone and locale
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

# Set passwords
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "$USERNAME ALL=(ALL) ALL" > /etc/sudoers.d/$USERNAME
chmod 0440 /etc/sudoers.d/$USERNAME

# Initramfs
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# GRUB
pacman -S grub efibootmgr intel-ucode --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

UUID=\$(blkid -s UUID -o value "$ROOT_PART")
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$UUID:$LUKS_NAME root=/dev/mapper/$LUKS_NAME quiet splash loglevel=3\"|" /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager
systemctl enable firewalld
systemctl enable bluetooth
systemctl enable acpid
systemctl enable sddm
EOF

echo "✅ Arch Linux with Hyprland is installed.You can now reboot."
