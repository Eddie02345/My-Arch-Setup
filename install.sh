#!/bin/bash 
set -euo pipefail

read -p "Disk (e.g., /dev/nvme0n1): " DISK read -p "Hostname: " HOSTNAME read -p "Username: " USERNAME echo -n "Root password: " read -s ROOT_PASSWORD echo echo -n "User password: " read -s USER_PASSWORD echo echo -n "LUKS password: " read -s LUKS_PASSWORD echo

EFI_PART="${DISK}p1" ROOT_PART="${DISK}p2" LUKS_NAME="cryptroot" LOCALE="en_PH.UTF-8" TIMEZONE="Asia/Manila" SUBVOL_ROOT="@" SUBVOL_HOME="@home"

sgdisk -Z "$DISK" sgdisk -n 1:0:+1G -t 1:ef00 "$DISK" sgdisk -n 2:0:0 "$DISK" echo "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" -q --type luks2 --batch-mode echo "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" "$LUKS_NAME" --key-file=-

mkfs.btrfs "/dev/mapper/$LUKS_NAME" mount "/dev/mapper/$LUKS_NAME" /mnt btrfs subvolume create /mnt/$SUBVOL_ROOT btrfs subvolume create /mnt/$SUBVOL_HOME umount /mnt

mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SUBVOL_ROOT "/dev/mapper/$LUKS_NAME" /mnt mkdir /mnt/home mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SUBVOL_HOME "/dev/mapper/$LUKS_NAME" /mnt/home

mkfs.fat -F32 "$EFI_PART" mkdir /mnt/boot mount "$EFI_PART" /mnt/boot

pacstrap /mnt base linux linux-firmware linux-headers networkmanager sudo neovim man-db man-pages hyprland xdg-desktop-portal-hyprland bluez bluez-utils firewalld acpid pipewire wireplumber base-devel sddm alacritty ttf-jetbrains-mono-nerd

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime hwclock --systohc echo "$LOCALE UTF-8" >> /etc/locale.gen locale-gen echo "LANG=$LOCALE" > /etc/locale.conf echo "$HOSTNAME" > /etc/hostname echo "root:$ROOT_PASSWORD" | chpasswd useradd -m -G wheel -s /bin/bash "$USERNAME" echo "$USERNAME:$USER_PASSWORD" | chpasswd echo "$USERNAME ALL=(ALL) ALL" > /etc/sudoers.d/$USERNAME chmod 0440 /etc/sudoers.d/$USERNAME sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf sed -i 's/^HOOKS=./HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf mkinitcpio -P pacman -S grub efibootmgr intel-ucode --noconfirm grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB UUID=$(blkid -s UUID -o value "$ROOT_PART") sed -i "s|^GRUB_CMDLINE_LINUX=.|GRUB_CMDLINE_LINUX="cryptdevice=UUID=$UUID:$LUKS_NAME root=/dev/mapper/$LUKS_NAME quiet"|" /etc/default/grub grub-mkconfig -o /boot/grub/grub.cfg systemctl enable NetworkManager systemctl enable firewalld systemctl enable bluetooth systemctl enable acpid systemctl enable sddm EOF echo "Install done. You can now reboot."

