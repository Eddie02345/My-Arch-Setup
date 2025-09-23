#!/bin/bash
set -euo pipefail

# =====================================================
#  Automated Arch Linux Installation Script
# =====================================================
# Features:
# - Disk partitioning with GPT
# - Full disk encryption (LUKS2) + Btrfs subvolumes
# - EFI boot with GRUB
# - Hyprland desktop environment + ecosystem
# - ZRAM swap setup
# - WiFi powersave disabled
# - paru bootstrap for AUR packages
# =====================================================

# -------------------------
# Dependency check
# -------------------------
for cmd in sgdisk cryptsetup mkfs.btrfs btrfs mkfs.fat pacstrap genfstab arch-chroot; do
    command -v $cmd >/dev/null || { echo "❌ $cmd not found. Install it first."; exit 1; }
done

# -------------------------
# User prompts
# -------------------------
read -rp "Enter target disk (e.g., /dev/nvme0n1): " DISK
read -rp "Enter hostname: " HOSTNAME
read -rp "Enter username: " USERNAME
read -rsp "Enter root password: " ROOT_PASSWORD; echo
read -rsp "Enter user password: " USER_PASSWORD; echo
read -rsp "Enter LUKS password: " LUKS_PASSWORD; echo

# -------------------------
# Variables
# -------------------------
LUKS_NAME=cryptroot
EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"
TIMEZONE="Asia/Manila"
SUBVOL_ROOT="@"
SUBVOL_HOME="@home"

# =====================================================
#  Disk Partitioning & Encryption
# =====================================================
# Wipe disk and create:
#   1. EFI system partition (1G)
#   2. Root partition (rest of disk)
sgdisk -Z "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 "$DISK"
sgdisk -n 2:0:0 "$DISK"

# Setup LUKS2 encryption
echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" --type luks2 --batch-mode --key-file=-
echo -n "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" "$LUKS_NAME" --key-file=-

# =====================================================
#  Btrfs Filesystem & Subvolumes
# =====================================================
mkfs.btrfs "/dev/mapper/$LUKS_NAME"
mount "/dev/mapper/$LUKS_NAME" /mnt

# Create subvolumes
btrfs subvolume create /mnt/$SUBVOL_ROOT
btrfs subvolume create /mnt/$SUBVOL_HOME
umount /mnt

# Mount subvolumes
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SUBVOL_ROOT "/dev/mapper/$LUKS_NAME" /mnt
mkdir /mnt/home
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=$SUBVOL_HOME "/dev/mapper/$LUKS_NAME" /mnt/home

# Setup EFI partition
mkfs.fat -F32 "$EFI_PART"
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# =====================================================
#  Base System Install
# =====================================================
pacstrap /mnt base linux linux-firmware linux-headers \
    networkmanager sudo neovim man-db man-pages \
    hyprland xdg-desktop-portal-hyprland \
    bluez bluez-utils firewalld acpid pipewire wireplumber \
    base-devel sddm alacritty ttf-jetbrains-mono-nerd

genfstab -U /mnt >> /mnt/etc/fstab

# =====================================================
#  Inside Chroot Configuration
# =====================================================
arch-chroot /mnt /bin/bash <<EOF
# -------------------------
# Time & Host setup
# -------------------------
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "$HOSTNAME" > /etc/hostname

# -------------------------
# User accounts
# -------------------------
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# -------------------------
# Initramfs configuration
# -------------------------
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# -------------------------
# Bootloader (GRUB + EFI)
# -------------------------
pacman -S --noconfirm grub efibootmgr intel-ucode
UUID=\$(blkid -s UUID -o value "$ROOT_PART")
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$UUID:$LUKS_NAME root=/dev/mapper/$LUKS_NAME quiet\"|" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager

# =====================================================
#  Extra System Tweaks
# =====================================================

# ---- Disable WiFi powersave ----
mkdir -p /etc/NetworkManager/conf.d
cat << NMCONF > /etc/NetworkManager/conf.d/wifi-powersave.conf
[connection]
wifi.powersave = 2
NMCONF

# ---- ZRAM swap ----
pacman -S --noconfirm zram-generator
mkdir -p /etc/systemd/zram-generator.conf.d
cat << ZRAMCONF > /etc/systemd/zram-generator.conf.d/custom-zram.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
ZRAMCONF

systemctl daemon-reexec
systemctl enable --now /dev/zram0.swap

# ---- Hyprland ecosystem packages ----
pacman -S --noconfirm uwsm libnewt
pacman -S --noconfirm mesa libva libva-utils libva-intel-driver hyprpolkitagent
pacman -S --noconfirm waybar swaync qt5-wayland qt6-wayland cliphist dolphin swww qt5ct qt6ct kvantum ttf-firacode-nerd hyprpaper wlsunset
pacman -S --noconfirm pipewire wireplumber pipewire-pulse

systemctl --user enable --now hyprpolkitagent.service
systemctl --user enable --now pipewire-pulse.service

# ---- Paru bootstrap for AUR ----
cd /home/$USERNAME
sudo -u $USERNAME git clone https://aur.archlinux.org/paru.git
cd paru
sudo -u $USERNAME makepkg -si --noconfirm
cd ..
rm -rf paru

# Install AUR packages
sudo -u $USERNAME paru -S --noconfirm catppuccin-gtk-theme-mocha ttf-ms-fonts

# ---- Hyprland configuration tweaks ----
mkdir -p /home/$USERNAME/.config/hypr
cat << HYPRAPPEND >> /home/$USERNAME/.config/hypr/hyprland.conf

# --- Extra env settings ---
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_STYLE_OVERRIDE,kvantum
env = QT_AUTO_SCREEN_SCALE_FACTOR,1
env = QT6CT_PLATFORMTHEME,qt6ct

# --- Clipboard integration ---
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
bind = SUPER, V, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy
HYPRAPPEND

chown -R $USERNAME:$USERNAME /home/$USERNAME/.config
EOF

# =====================================================
echo "✅ Installation finished! You can reboot now."
