#!/bin/bash
# =====================================================
#  Automated Arch Linux Installation Script
#  Supports NVMe and SATA disks
#  Features: LUKS + Btrfs, Hyprland setup, zram, configs
#  Author: You
# =====================================================

set -euo pipefail

# -------------------------------
# FUNCTIONS
# -------------------------------

confirm() {
    read -rp "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) true ;;
        *) false ;;
    esac
}

# -------------------------------
# USER INPUT
# -------------------------------

echo "Available disks:"
lsblk -dpno NAME,SIZE | grep -E "sd|nvme"

echo
read -rp "Enter target disk (e.g., /dev/nvme0n1 or /dev/sda): " DISK

read -rp "Enter hostname: " HOSTNAME
read -rp "Enter username: " USERNAME

# Secure password input
read -rsp "Enter root password: " ROOT_PASSWORD; echo
read -rsp "Enter user password: " USER_PASSWORD; echo
read -rsp "Enter LUKS password: " LUKS_PASSWORD; echo

# -------------------------------
# VARIABLES
# -------------------------------

TIMEZONE="Asia/Manila"
LUKS_NAME="cryptroot"
SUBVOL_ROOT="@"
SUBVOL_HOME="@home"

# Handle NVMe vs SATA naming
if [[ "$DISK" =~ nvme ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

# -------------------------------
# PARTITIONING
# -------------------------------

echo "[*] Partitioning $DISK..."
sgdisk -Z "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 "$DISK"   # EFI
sgdisk -n 2:0:0 "$DISK"               # Root

# -------------------------------
# ENCRYPTION SETUP
# -------------------------------

echo "[*] Setting up LUKS encryption..."
echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" --type luks2 --batch-mode --key-file=-
echo -n "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" "$LUKS_NAME" --key-file=-

# -------------------------------
# FILESYSTEM SETUP
# -------------------------------

echo "[*] Formatting partitions..."
mkfs.fat -F32 "$EFI_PART"
mkfs.btrfs "/dev/mapper/$LUKS_NAME"

echo "[*] Creating Btrfs subvolumes..."
mount "/dev/mapper/$LUKS_NAME" /mnt
btrfs subvolume create /mnt/$SUBVOL_ROOT
btrfs subvolume create /mnt/$SUBVOL_HOME
umount /mnt

echo "[*] Mounting subvolumes..."
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SUBVOL_ROOT "/dev/mapper/$LUKS_NAME" /mnt
mkdir /mnt/home
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SUBVOL_HOME "/dev/mapper/$LUKS_NAME" /mnt/home

mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# -------------------------------
# BASE INSTALL
# -------------------------------

echo "[*] Installing base system..."
pacstrap /mnt base linux linux-firmware linux-headers \
    networkmanager sudo neovim man-db man-pages \
    hyprland xdg-desktop-portal-hyprland \
    bluez bluez-utils firewalld acpid pipewire wireplumber \
    base-devel sddm alacritty ttf-jetbrains-mono-nerd

mkdir -p /mnt/etc
genfstab -U /mnt >> /mnt/etc/fstab

UUID=$(blkid -s UUID -o value "$ROOT_PART")

# -------------------------------
# CHROOT CONFIG
# -------------------------------

arch-chroot /mnt /bin/bash <<EOF
echo "[*] Inside chroot..."

# Time & locale
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Hostname
echo "$HOSTNAME" > /etc/hostname

# Users
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# Initramfs
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Bootloader
pacman -S --noconfirm grub efibootmgr intel-ucode
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$UUID:$LUKS_NAME root=/dev/mapper/$LUKS_NAME quiet\"|" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager
systemctl enable sddm

# -------------------------------
# EXTRA CONFIGS
# -------------------------------

# Disable WiFi power saving
mkdir -p /etc/NetworkManager/conf.d
cat <<NMCONF > /etc/NetworkManager/conf.d/wifi-powersave.conf
[connection]
wifi.powersave = 2
NMCONF

# Zram setup
pacman -S --noconfirm zram-generator
mkdir -p /etc/systemd/zram-generator.conf.d
cat <<ZCONF > /etc/systemd/zram-generator.conf.d/custom-zram.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
ZCONF
systemctl daemon-reexec
systemctl enable /dev/zram0.swap

# Hyprland & tools
pacman -S --noconfirm uwsm libnewt mesa libva libva-utils libva-intel-driver hyprpolkitagent
pacman -S --noconfirm waybar swaync qt5-wayland qt6-wayland cliphist dolphin swww qt5ct qt6ct kvantum \
    ttf-firacode-nerd hyprpaper wlsunset
pacman -S --noconfirm pipewire wireplumber pipewire-pulse
systemctl --user enable --now hyprpolkitagent.service
systemctl --user enable --now pipewire-pulse.service

# AUR themes/fonts (requires paru after reboot)
echo "After reboot, run: paru -S catppuccin-gtk-theme-mocha ttf-ms-fonts"

# Hyprland config
mkdir -p /home/$USERNAME/.config/hypr
cat <<HCONF >> /home/$USERNAME/.config/hypr/hyprland.conf
# QT + theme env
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_STYLE_OVERRIDE,kvantum
env = QT_AUTO_SCREEN_SCALE_FACTOR,1
env = QT6CT_PLATFORMTHEME,qt6ct

# Clipboard history
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
bind = SUPER, V, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy
HCONF
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config
EOF

echo "[*] Installation complete! You may reboot now."
