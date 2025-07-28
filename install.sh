#!/bin/bash set -euo pipefail

=== Prompt user for disk and basic config ===

echo "Available disks:" lsblk -d -o NAME,SIZE,MODEL

read -rp "Enter the target DISK (e.g., /dev/nvme0n1): " DISK read -rp "Enter the hostname: " HOSTNAME read -rp "Enter your username: " USERNAME read -rp "Enter a name for the LUKS container (e.g., cryptroot): " LUKS_NAME

echo "WARNING: This will erase all data on ${DISK}. Press Enter to continue or Ctrl+C to abort." read

=== Partition Disk ===

sgdisk -Z "$DISK" sgdisk -n 1:0:+1G -t 1:ef00 "$DISK"    # EFI sgdisk -n 2:0:0 -t 2:8300 "$DISK"     # Root

=== Wipe any existing filesystem and crypto signature ===

wipefs -a "${DISK}p2"

=== Setup LUKS Encryption ===

echo "Setting up encryption for ${DISK}p2" cryptsetup luksFormat "${DISK}p2" cryptsetup open "${DISK}p2" "$LUKS_NAME"

=== Format and Mount Btrfs ===

mkfs.btrfs "/dev/mapper/${LUKS_NAME}" mount "/dev/mapper/${LUKS_NAME}" /mnt

btrfs subvolume create /mnt/@ btrfs subvolume create /mnt/@home umount /mnt

mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ "/dev/mapper/${LUKS_NAME}" /mnt mkdir /mnt/home mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@home "/dev/mapper/${LUKS_NAME}" /mnt/home

=== EFI Partition ===

mkfs.fat -F32 "${DISK}p1" mkdir -p /mnt/boot mount "${DISK}p1" /mnt/boot

=== Mirrorlist and Base Install ===

pacman -Sy reflector --noconfirm reflector -c Singapore -a 12 --sort rate --save /etc/pacman.d/mirrorlist

pacstrap /mnt base linux linux-headers linux-firmware btrfs-progs sudo neovim networkmanager 
base-devel pipewire wireplumber acpid bluez bluez-utils ufw sddm alacritty ttf-jetbrains-mono-nerd 
hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk

genfstab -U /mnt >> /mnt/etc/fstab

=== Chroot Configuration ===

arch-chroot /mnt /bin/bash <<EOF

ln -sf /usr/share/zoneinfo/Asia/Manila /etc/localtime hwclock --systohc

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen sed -i 's/^#en_PH.UTF-8/en_PH.UTF-8/' /etc/locale.gen locale-gen echo "LANG=en_PH.UTF-8" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname

Set root password

echo "Set root password" passwd

Create user

useradd -m -g users -G wheel "$USERNAME" echo "Set password for $USERNAME" passwd "$USERNAME" echo "$USERNAME ALL=(ALL) ALL" > /etc/sudoers.d/$USERNAME chmod 0440 /etc/sudoers.d/$USERNAME

Initramfs Config

sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf sed -i 's/^HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck)/' /etc/mkinitcpio.conf mkinitcpio -P

GRUB Install

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB disk_uuid=$(blkid -s UUID -o value ${DISK}p2) sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="cryptdevice=UUID=$disk_uuid:$LUKS_NAME root=/dev/mapper/$LUKS_NAME"|" /etc/default/grub grub-mkconfig -o /boot/grub/grub.cfg

Enable services

systemctl enable NetworkManager sddm bluetooth acpid ufw EOF

umount -R /mnt echo "\n✅ Done! You can reboot now."

