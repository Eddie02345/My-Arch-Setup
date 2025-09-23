#!/bin/bash
set -e  # stop on error

echo "=== Arch Linux + Hyprland Auto Installer ==="

# --- Disk Selection ---
echo "[INFO] Available disks:"
lsblk -d -o NAME,SIZE,TYPE | grep disk  # list only whole disks

disk_count=$(lsblk -dno NAME,TYPE | grep disk | wc -l)

if [ "$disk_count" -eq 1 ]; then
    # Auto-pick if only 1 disk is detected
    disk=$(lsblk -dno NAME,TYPE | grep disk | awk '{print $1}')
    disk="/dev/$disk"
    echo "[INFO] Auto-selected disk: $disk"
else
    # Ask if multiple disks exist
    read -rp "Enter the target disk (e.g. /dev/sda): " disk
fi

# --- Partitioning (no confirmation, wipes immediately) ---
echo "[INFO] Wiping and partitioning $disk ..."
wipefs -a "$disk"            # clear filesystem signatures
sgdisk -Z "$disk"            # zap GPT/MBR
sgdisk -n1:0:+512M -t1:ef00 -c1:"EFI System" "$disk"   # 512MB EFI
sgdisk -n2:0:0     -t2:8300 -c2:"Linux root" "$disk"   # rest = root

# Handle different disk naming (nvme vs vda/sda)
if [[ "$disk" =~ "nvme" ]]; then
    boot="${disk}p1"
    root="${disk}p2"
else
    boot="${disk}1"
    root="${disk}2"
fi

# Format partitions
mkfs.fat -F32 "$boot"
mkfs.ext4 -F "$root"

# Mount target system
mount "$root" /mnt
mkdir /mnt/boot
mount "$boot" /mnt/boot

# --- Base System Installation ---
echo "[INFO] Installing base system ..."
pacstrap /mnt base linux linux-firmware sudo nano networkmanager reflector

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# --- System Configuration inside chroot ---
arch-chroot /mnt /bin/bash <<EOF
echo "[INFO] Configuring system inside chroot ..."

# Timezone & clock
ln -sf /usr/share/zoneinfo/Asia/Manila /etc/localtime
hwclock --systohc

# Locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "arch" > /etc/hostname

# Enable networking
systemctl enable NetworkManager

# Optimize mirrors for PH/SG/JP
reflector --country Philippines --country Singapore --country Japan \
    --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Install systemd-boot bootloader
bootctl --path=/boot install
cat <<BOOT > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=$root rw
BOOT

# Install Hyprland + essential packages
pacman -S --noconfirm \
    mesa vulkan-intel libva-intel-driver libva-utils \  # Intel graphics stack
    xorg-xwayland \                                    # XWayland support
    hyprland xdg-desktop-portal-hyprland \             # Wayland compositor + portal
    sddm waybar alacritty firefox \                    # desktop environment
    network-manager-applet                             # tray network tool

# Enable display manager
systemctl enable sddm
EOF

echo "=== Installation complete! ==="
echo "👉 Reboot into your new Arch Linux with Hyprland."
