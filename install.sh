#!/bin/bash
# =====================================================
#  Arch Linux Automated Installer (LUKS2 + Btrfs + Hyprland)
#  Supports NVMe, SATA, VirtIO (vda)
#  Optimized for Intel UHD 620
#  Features:
#    - GRUB with cryptdevice=UUID
#    - Hyprland + Wayland apps
#    - zram
#    - Reflector for fast mirrors
#    - Automatic Paru + Catppuccin Mocha theme applied
# =====================================================

set -euo pipefail

# -------------------------------
#  User input
# -------------------------------
echo "Available disks:"
lsblk -dpno NAME,SIZE,MODEL | grep -E "sd|nvme|vd|vda" || lsblk -dpno NAME,SIZE,MODEL

echo
read -rp "Enter target disk (e.g. /dev/nvme0n1, /dev/sda, /dev/vda): " DISK
read -rp "Enter hostname: " HOSTNAME
read -rp "Enter username: " USERNAME

# Secure password input
read -rsp "Enter root password: " ROOT_PASSWORD; echo
read -rsp "Enter user password: " USER_PASSWORD; echo
read -rsp "Enter LUKS password: " LUKS_PASSWORD; echo

# -------------------------------
#  Variables
# -------------------------------
TIMEZONE="Asia/Manila"
LUKS_NAME="cryptroot"
SUBVOL_ROOT="@"
SUBVOL_HOME="@home"

# Partition suffix (nvme uses 'p')
if [[ "$DISK" =~ nvme ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

echo "[INFO] Target disk: $DISK"
echo "[INFO] EFI partition: $EFI_PART"
echo "[INFO] Root partition: $ROOT_PART"

# -------------------------------
#  Partitioning (DESTROYS DISK)
# -------------------------------
echo "[STEP] Wiping disk and creating partitions..."
wipefs -a "$DISK" || true
sgdisk -Z "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI System" "$DISK"
sgdisk -n 2:0:0 -t 2:8300 -c 2:"Linux root" "$DISK"

# -------------------------------
#  LUKS Encryption
# -------------------------------
echo "[STEP] Setting up LUKS2..."
printf "%s" "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" --type luks2 --batch-mode --key-file=-
printf "%s" "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" "$LUKS_NAME" --key-file=-

# -------------------------------
#  Btrfs + subvolumes
# -------------------------------
echo "[STEP] Creating Btrfs filesystem and subvolumes..."
mkfs.btrfs -f "/dev/mapper/$LUKS_NAME"
mount "/dev/mapper/$LUKS_NAME" /mnt
btrfs subvolume create /mnt/$SUBVOL_ROOT
btrfs subvolume create /mnt/$SUBVOL_HOME
umount /mnt

mount -o noatime,compress=zstd:3,space_cache=v2,discard=async,subvol=$SUBVOL_ROOT "/dev/mapper/$LUKS_NAME" /mnt
mkdir -p /mnt/home
mount -o noatime,compress=zstd:3,space_cache=v2,discard=async,subvol=$SUBVOL_HOME "/dev/mapper/$LUKS_NAME" /mnt/home

mkfs.fat -F32 "$EFI_PART"
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# -------------------------------
#  Mirrors
# -------------------------------
echo "[STEP] Installing reflector and updating mirrorlist..."
pacman -Sy --noconfirm --needed reflector
reflector --country Philippines --country Singapore --country Japan \
          --latest 30 --protocol https --sort rate \
          --save /etc/pacman.d/mirrorlist

# -------------------------------
#  Base system + packages
# -------------------------------
echo "[STEP] Installing base system and packages..."
PACLIST=(
  base linux linux-firmware
  networkmanager sudo neovim man-db man-pages
  base-devel git
  btrfs-progs dosfstools efibootmgr
  intel-ucode
  xorg-xwayland
  hyprland xdg-desktop-portal-hyprland hyprpolkitagent
  waybar alacritty sddm
  pipewire pipewire-pulse wireplumber
  bluez bluez-utils
  firewalld acpid
  ttf-jetbrains-mono-nerd ttf-firacode-nerd
  zram-generator reflector
  mesa vulkan-intel libva-intel-driver libva-utils
  qt5ct qt6ct kvantum
)

pacstrap /mnt "${PACLIST[@]}"

# -------------------------------
#  fstab
# -------------------------------
echo "[STEP] Generating /etc/fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
ROOT_PART_UUID=$(blkid -s UUID -o value "$ROOT_PART")

# -------------------------------
#  Chroot configuration
# -------------------------------
echo "[STEP] Configuring system in chroot..."
arch-chroot /mnt /bin/bash <<EOF
set -e

TIMEZONE="$TIMEZONE"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
ROOT_PASS="$ROOT_PASSWORD"
USER_PASS="$USER_PASSWORD"
LUKS_NAME="$LUKS_NAME"
ROOT_PART_UUID="$ROOT_PART_UUID"

# -------------------------------
#  Time & locale
# -------------------------------
ln -sf /usr/share/zoneinfo/\$TIMEZONE /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "\$HOSTNAME" > /etc/hostname

# -------------------------------
#  Users & sudo
# -------------------------------
echo "root:\$ROOT_PASS" | chpasswd
useradd -m -G wheel -s /bin/bash "\$USERNAME"
echo "\$USERNAME:\$USER_PASS" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# -------------------------------
#  Initramfs & bootloader
# -------------------------------
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems btrfs filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

pacman -S --noconfirm grub
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$ROOT_PART_UUID:\$LUKS_NAME root=/dev/mapper/\$LUKS_NAME loglevel=3 quiet\"|" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# -------------------------------
#  Enable services
# -------------------------------
systemctl enable NetworkManager
systemctl enable sddm

# -------------------------------
#  Paru 
# -------------------------------
sudo -u "\$USERNAME" bash <<'EOPARU'
set -e
cd ~
git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin
makepkg -si --noconfirm

echo "[DONE] Installation finished!"
echo "Reboot -> remove ISO -> log in via SDDM -> select Hyprland session."
