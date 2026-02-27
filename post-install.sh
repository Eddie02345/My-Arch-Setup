#!/bin/bash
# =====================================================
#  Arch Linux Base Installer: ThinkPad T470
#  - Hardware: i5-7300U | HD 620 | 8GB RAM (ZRAM)
#  - Stack: LUKS2 + Btrfs + Standalone IWD/Resolved
# =====================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
log() { echo -e "${GREEN}[STEP] $1${NC}"; }
err() { echo -e "${RED}[ERROR] $1${NC}"; }

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
echo "   THINKPAD T470 BASE INSTALLER"
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
    LUKS_PASSWORD="$UNIFIED_PASS"; ROOT_PASSWORD="$UNIFIED_PASS"; USER_PASSWORD="$UNIFIED_PASS"
else
    get_verified_password "Enter LUKS Password" LUKS_PASSWORD
    get_verified_password "Enter Root Password" ROOT_PASSWORD
    get_verified_password "Enter User Password" USER_PASSWORD
fi

echo
read -p "!!! DESTROY DATA ON $DISK? (y/N): " CONFIRM
[[ "$CONFIRM" == "y" ]] || exit 1

log "Forcing cleanup of locks..."
swapoff -a || true; umount -R /mnt || true; cryptsetup close cryptroot || true; udevadm settle; sleep 1

[[ "$DISK" =~ "nvme" || "$DISK" =~ "mmcblk" ]] && P="p" || P=""
EFI_PART="${DISK}${P}1"
ROOT_PART="${DISK}${P}2"

log "Wiping disk & Partitioning..."
wipefs --all --force "$DISK"
sgdisk -Z "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:0:0   -t 2:8300 -c 2:"LUKS" "$DISK"
partprobe "$DISK"; udevadm settle && sleep 2

log "Encrypting Root..."
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

log "Setting up Mirrors..."
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
if command -v reflector &> /dev/null; then
    reflector --country Philippines --country Singapore --country Japan --latest 10 --sort rate --save /etc/pacman.d/mirrorlist || true
fi
echo "Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" >> /etc/pacman.d/mirrorlist

log "Syncing databases..."
pacman -Sy

log "Installing Packages..."
PKGS=(base linux linux-firmware base-devel git rust sudo efibootmgr dosfstools btrfs-progs
      iwd bluez bluez-utils reflector stow
      intel-ucode mesa vulkan-intel intel-media-driver libva-utils
      sof-firmware acpi_call tlp acpid
      hyprland xdg-desktop-portal-hyprland hyprpaper waybar swaync
      pipewire pipewire-pulse wireplumber
      sddm qt5-wayland qt6-wayland qt5ct qt6ct kvantum
      alacritty nemo ttf-jetbrains-mono-nerd brightnessctl papirus-icon-theme
      zram-generator man-db fuzzel cliphist polkit-gnome)
pacstrap /mnt "${PKGS[@]}"

log "Configuring System..."
genfstab -U /mnt >> /mnt/etc/fstab
UUID=$(blkid -s UUID -o value "$ROOT_PART")

arch-chroot /mnt /bin/bash <<EOF
set -e
ln -sf /usr/share/zoneinfo/Asia/Manila /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel,video,input -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

mkdir -p /etc/iwd
cat > /etc/iwd/main.conf <<INI
[General]
EnableNetworkConfiguration=true
[Network]
NameResolvingService=systemd
INI

cat > /etc/systemd/zram-generator.conf <<INI
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
INI

cat > /etc/sysctl.d/99-zram.conf <<INI
vm.swappiness = 100
vm.page-cluster = 0
INI

cat >> /etc/environment <<ENV
LIBVA_DRIVER_NAME=iHD
QT_QPA_PLATFORMTHEME=qt5ct
QT_STYLE_OVERRIDE=kvantum
ENV

pacman -S --noconfirm grub
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf keyboard keymap block encrypt filesystems btrfs fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$UUID:cryptroot root=/dev/mapper/cryptroot loglevel=3 quiet i915.enable_guc=2\"|" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable iwd systemd-resolved bluetooth tlp sddm fstrim.timer
EOF

log "Base Installation Complete!"
echo "1. Type 'reboot' and remove your USB."
echo "2. Log in to your new system."
echo "3. Run: git clone <your-repo-url> && cd <repo> && ./post-install.sh"the hyprland.conf is in the github you just need to copy/stow i. I think stow is betterthe hyprland.conf is in the github you just need to copy/stow i. I think stow is better
