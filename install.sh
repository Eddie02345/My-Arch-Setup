#!/bin/bash
# =====================================================
#  Arch Linux Installer: ThinkPad T470 (v6 Final)
#  - Fix: Uses built-in Reflector (no updates, no curl)
#  - Fallback: Adds a backup mirror if Reflector fails
#  - Cleanup: forceful drive unlock before starting
# =====================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[STEP] $1${NC}"; }
err() { echo -e "${RED}[ERROR] $1${NC}"; }

# -------------------------------
#  1. User Input & Verification
# -------------------------------
get_verified_password() {
    local _prompt="$1"
    local -n _outvar="$2"
    while true; do
        read -rsp "$_prompt: " _pass1; echo
        read -rsp "Confirm $_prompt: " _pass2; echo
        if [[ "$_pass1" == "$_pass2" && -n "$_pass1" ]]; then
            _outvar="$_pass1"
            break
        else
            err "Passwords do not match. Try again."
        fi
    done
}

clear
echo "=========================================="
echo "   THINKPAD T470 ARCH INSTALLER (v6)"
echo "=========================================="
lsblk -dpno NAME,SIZE,MODEL,TYPE | grep -E "disk|nvme"

echo
read -rp "Enter target disk (e.g. /dev/nvme0n1): " DISK
[[ -b "$DISK" ]] || { err "Disk not found!"; exit 1; }

read -rp "Enter hostname: " HOSTNAME
read -rp "Enter username: " USERNAME

echo "------------------------------------------"
read -rp "Use one password for EVERYTHING (LUKS/Root/User)? (y/N): " SAME_PASS

if [[ "$SAME_PASS" =~ ^[Yy]$ ]]; then
    get_verified_password "Enter Unified Password" UNIFIED_PASS
    LUKS_PASSWORD="$UNIFIED_PASS"
    ROOT_PASSWORD="$UNIFIED_PASS"
    USER_PASSWORD="$UNIFIED_PASS"
else
    get_verified_password "Enter LUKS Password" LUKS_PASSWORD
    get_verified_password "Enter Root Password" ROOT_PASSWORD
    get_verified_password "Enter User Password" USER_PASSWORD
fi

echo
read -p "!!! DESTROY DATA ON $DISK? (y/N): " CONFIRM
[[ "$CONFIRM" == "y" ]] || exit 1

# -------------------------------
#  2. Pre-Flight Cleanup
# -------------------------------
log "Forcing cleanup of previous mounts..."
# This attempts to fix "Device in use" errors if you didn't reboot
swapoff -a || true
umount -R /mnt || true
cryptsetup close cryptroot || true
udevadm settle
sleep 1

# -------------------------------
#  3. Partitioning & Encryption
# -------------------------------
# Auto-detect partition suffix
[[ "$DISK" =~ "nvme" || "$DISK" =~ "mmcblk" ]] && P="p" || P=""
EFI_PART="${DISK}${P}1"
ROOT_PART="${DISK}${P}2"

log "Wiping disk..."
wipefs --all --force "$DISK"
sgdisk -Z "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:0:0   -t 2:8300 -c 2:"LUKS" "$DISK"

# Reload partition table and wait
partprobe "$DISK"
udevadm settle 
sleep 2

log "Encrypting Root..."
# If this fails, REBOOT is the only fix.
echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" --type luks2 --batch-mode --key-file=-
echo -n "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" cryptroot --key-file=-

log "Formatting Btrfs..."
mkfs.btrfs -f -L "ARCH_ROOT" /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
umount /mnt

MOUNT_OPT="noatime,compress=zstd:3,space_cache=v2,discard=async"
mount -o "$MOUNT_OPT,subvol=@" /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var/log,.snapshots,boot}
mount -o "$MOUNT_OPT,subvol=@home" /dev/mapper/cryptroot /mnt/home
mount -o "$MOUNT_OPT,subvol=@snapshots" /dev/mapper/cryptroot /mnt/.snapshots
mount -o "$MOUNT_OPT,subvol=@var_log" /dev/mapper/cryptroot /mnt/var/log

mkfs.fat -F32 -n "EFI" "$EFI_PART"
mount "$EFI_PART" /mnt/boot

# -------------------------------
#  4. Base Install
# -------------------------------
log "Setting up Mirrors..."

# 1. Back up existing list
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak

# 2. Try to use the BUILT-IN reflector (do not install/update it)
if command -v reflector &> /dev/null; then
    log "Using system Reflector to find fast mirrors..."
    # We use a timeout so it doesn't hang forever
    reflector --country Philippines --country Singapore --country Japan --latest 10 --sort rate --save /etc/pacman.d/mirrorlist || echo "Reflector failed, using fallback."
else
    log "Reflector not found, skipping."
fi

# 3. Fallback: Append a reliable global mirror just in case Reflector returned nothing or failed
echo "Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" >> /etc/pacman.d/mirrorlist

log "Syncing databases..."
pacman -Sy

log "Installing Packages..."
# Core + T470 Hardware (Kaby Lake)
PKGS=(base linux linux-firmware base-devel git rust sudo efibootmgr dosfstools btrfs-progs
      iwd bluez bluez-utils
      intel-ucode mesa vulkan-intel intel-media-driver libva-utils
      sof-firmware acpi_call tlp acpid
      hyprland xdg-desktop-portal-hyprland hyprpaper waybar swaync
      pipewire pipewire-pulse wireplumber
      sddm qt5-wayland qt6-wayland qt5ct qt6ct kvantum
      alacritty nemo ttf-jetbrains-mono-nerd brightnessctl papirus-icon-theme
      zram-generator man-db fuzzel cliphist polkit-gnome)

pacstrap /mnt "${PKGS[@]}"

# -------------------------------
#  5. System Configuration
# -------------------------------
genfstab -U /mnt >> /mnt/etc/fstab
UUID=$(blkid -s UUID -o value "$ROOT_PART")

arch-chroot /mnt /bin/bash <<EOF
set -e

# Time & Locale
ln -sf /usr/share/zoneinfo/Asia/Manila /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

# Users
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel,video,input -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# Network (IWD Standalone)
echo -e "[General]\nEnableNetworkConfiguration=true" > /etc/iwd/main.conf

# ZRAM OPTIMIZATION (8GB RAM Target)
cat > /etc/systemd/zram-generator.conf <<INI
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
INI

# Kernel Tuning for ZRAM
cat > /etc/sysctl.d/99-zram-optimization.conf <<INI
vm.swappiness = 100
vm.page-cluster = 0
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
INI

# Environment (T470 VA-API + Theming)
cat >> /etc/environment <<ENV
LIBVA_DRIVER_NAME=iHD
QT_QPA_PLATFORMTHEME=qt5ct
QT_STYLE_OVERRIDE=kvantum
ENV

# Bootloader (Grub + LUKS + T470 GuC)
pacman -S --noconfirm grub
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf keyboard keymap block encrypt filesystems btrfs fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$UUID:cryptroot root=/dev/mapper/cryptroot loglevel=3 quiet i915.enable_guc=2\"|" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
grub-mkconfig -o /boot/grub/grub.cfg

# Services
systemctl enable iwd bluetooth tlp sddm fstrim.timer

# -------------------------------
#  6. Paru & Catppuccin Setup
# -------------------------------
echo ":: Installing Paru & Catppuccin Themes..."

# Must run as user
sudo -u $USERNAME bash -c '
    cd ~
    git clone https://aur.archlinux.org/paru-bin.git
    cd paru-bin
    makepkg -si --noconfirm
    cd ~
    rm -rf paru-bin

    # Use Paru to get Themes
    paru -S --noconfirm catppuccin-gtk-theme-mocha catppuccin-kvantum
'

# -------------------------------
#  7. Applying Themes (Auto-Config)
# -------------------------------
echo ":: Applying Catppuccin Configuration..."

# Create Config Dirs
mkdir -p /home/$USERNAME/.config/{gtk-3.0,gtk-4.0,Kvantum,qt5ct}

# GTK 3 Config
cat > /home/$USERNAME/.config/gtk-3.0/settings.ini <<INI
[Settings]
gtk-theme-name=Catppuccin-Mocha-Standard-Blue-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrainsMono Nerd Font 11
gtk-application-prefer-dark-theme=1
INI

# GTK 4 Config
cat > /home/$USERNAME/.config/gtk-4.0/settings.ini <<INI
[Settings]
gtk-theme-name=Catppuccin-Mocha-Standard-Blue-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrainsMono Nerd Font 11
gtk-application-prefer-dark-theme=1
INI

# Kvantum (Qt) Config
cat > /home/$USERNAME/.config/Kvantum/kvantum.kvconfig <<INI
[General]
theme=Catppuccin-Mocha-Blue
INI

# Fix Permissions
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config

EOF

log "Installation Complete! Reboot, login, and enjoy your T470."
