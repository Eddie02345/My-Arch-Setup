#!/bin/bash
# ================================================================
#  Arch Linux Universal Installer v2.0
#  Profiles: ThinkPad T470 | X1 Carbon Gen 7 | Generic Intel/AMD
#  Stack:    LUKS2 (argon2id) + Btrfs + IWD + systemd-resolved
# ================================================================
set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m';   CYAN='\033[0;36m'
BOLD='\033[1m';     NC='\033[0m'
log()  { echo -e "${GREEN}[STEP]  $*${NC}"; }
info() { echo -e "${CYAN}[INFO]  $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN]  $*${NC}"; }
err()  { echo -e "${RED}[ERR]   $*${NC}" >&2; exit 1; }
hr()   { echo -e "${BOLD}────────────────────────────────────────────────${NC}"; }

# ── Password Helper ──────────────────────────────────────────────
get_verified_password() {
    local prompt="$1"
    local -n outvar="$2"
    while true; do
        read -rsp "${prompt}: " _p1; echo
        read -rsp "Confirm ${prompt}: " _p2; echo
        [[ "$_p1" == "$_p2" && -n "$_p1" ]] && { outvar="$_p1"; return; }
        warn "Passwords don't match — try again."
    done
}

# ================================================================
#  HARDWARE PROFILES
#  Each profile sets: PROFILE_NAME, MICROCODE, GPU_PKGS[],
#  EXTRA_PKGS[], KERNEL_PARAMS, LIBVA_DRIVER, SVC_EXTRA
# ================================================================

auto_detect_profile() {
    local name version combined
    name=$(cat /sys/class/dmi/id/product_name    2>/dev/null || true)
    version=$(cat /sys/class/dmi/id/product_version 2>/dev/null || true)
    combined="$name $version"

    if   [[ "$combined" =~ [Xx]1[[:space:]][Cc]arbon.*7 || "$name" =~ ^20Q[DE] ]]; then
        echo "X1C7"
    elif [[ "$combined" =~ T470 ]]; then
        echo "T470"
    elif grep -qi "amd" /proc/cpuinfo 2>/dev/null; then
        echo "AMD"
    else
        echo "INTEL"
    fi
}

apply_profile() {
    case "$1" in

    # ── ThinkPad T470 ─────────────────────────────────────────
    # 7th-gen Kaby Lake · HD 620 · no Thunderbolt · no fingerprint
    T470)
        PROFILE_NAME="ThinkPad T470"
        MICROCODE="intel-ucode"
        GPU_PKGS=(mesa vulkan-intel intel-media-driver libva-utils)
        EXTRA_PKGS=(acpi_call tlp tlp-rdw sof-firmware)
        # enable_guc=2 → GuC only (safe for Kaby Lake)
        # enable_fbc=1 → framebuffer compression (saves power)
        KERNEL_PARAMS="i915.enable_guc=2 i915.enable_fbc=1"
        LIBVA_DRIVER="iHD"
        SVC_EXTRA="tlp"
        ;;

    # ── ThinkPad X1 Carbon Gen 7 ──────────────────────────────
    # 8th-gen Whiskey Lake · UHD 620 · Thunderbolt 3 · fingerprint
    X1C7)
        PROFILE_NAME="ThinkPad X1 Carbon Gen 7"
        MICROCODE="intel-ucode"
        GPU_PKGS=(mesa vulkan-intel intel-media-driver libva-utils)
        EXTRA_PKGS=(acpi_call tlp tlp-rdw thermald fprintd bolt sof-firmware)
        # enable_guc=3 → GuC + HuC (supported on 8th-gen+)
        # mem_sleep_default=deep → S3 suspend (fix S0ix/s2idle issues)
        # nvme.noacpi=1 → avoids ACPI quirk that can stall NVMe on resume
        KERNEL_PARAMS="i915.enable_guc=3 i915.enable_fbc=1 mem_sleep_default=deep nvme.noacpi=1"
        LIBVA_DRIVER="iHD"
        SVC_EXTRA="tlp thermald fprintd bolt"
        ;;

    # ── Generic Intel ─────────────────────────────────────────
    INTEL)
        PROFILE_NAME="Generic Intel System"
        MICROCODE="intel-ucode"
        GPU_PKGS=(mesa vulkan-intel intel-media-driver libva-utils)
        EXTRA_PKGS=(sof-firmware)
        KERNEL_PARAMS=""
        LIBVA_DRIVER="iHD"
        SVC_EXTRA=""
        ;;

    # ── Generic AMD ───────────────────────────────────────────
    AMD)
        PROFILE_NAME="Generic AMD System"
        MICROCODE="amd-ucode"
        GPU_PKGS=(mesa vulkan-radeon libva-mesa-driver mesa-vdpau libva-utils)
        EXTRA_PKGS=(sof-firmware)
        KERNEL_PARAMS=""
        LIBVA_DRIVER="radeonsi"
        SVC_EXTRA=""
        ;;

    *) err "Unknown profile: $1" ;;
    esac
}

# ================================================================
#  INTERACTIVE SETUP
# ================================================================
clear
echo -e "${BOLD}"
echo " ╔════════════════════════════════════════════════╗"
echo " ║     ARCH LINUX UNIVERSAL INSTALLER  v2.0     ║"
echo " ║   LUKS2 · Btrfs · IWD · systemd-resolved    ║"
echo " ╚════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── 1. Hardware Profile ─────────────────────────────────────────
hr; echo -e "${BOLD} 1. Hardware Profile${NC}"; hr
DETECTED=$(auto_detect_profile)
info "Auto-detected: ${YELLOW}${DETECTED}${NC}"
echo
echo "  1) ThinkPad T470           (7th-gen Intel · HD 620)"
echo "  2) ThinkPad X1 Carbon G7   (8th-gen Intel · UHD 620 · TB3 · Fingerprint)"
echo "  3) Generic Intel"
echo "  4) Generic AMD"
echo "  5) Use auto-detected       (${DETECTED})"
echo
read -rp "Select [1-5] (default 5): " _p; _p="${_p:-5}"
case "$_p" in
    1) apply_profile T470  ;;
    2) apply_profile X1C7  ;;
    3) apply_profile INTEL ;;
    4) apply_profile AMD   ;;
    *) apply_profile "$DETECTED" ;;
esac
info "Profile set: ${GREEN}${PROFILE_NAME}${NC}"

# ── 2. Disk ─────────────────────────────────────────────────────
hr; echo -e "${BOLD} 2. Disk Selection${NC}"; hr
lsblk -dpno NAME,SIZE,MODEL | grep -v loop
echo
read -rp "Target disk (e.g. /dev/nvme0n1): " DISK
[[ -b "$DISK" ]] || err "Disk '$DISK' not found."

# ── 3. System Config ────────────────────────────────────────────
hr; echo -e "${BOLD} 3. System Configuration${NC}"; hr
read -rp "Hostname: "                  HOSTNAME
read -rp "Username: "                  USERNAME
read -rp "Timezone [Asia/Manila]: "    TIMEZONE; TIMEZONE="${TIMEZONE:-Asia/Manila}"
read -rp "Locale   [en_US.UTF-8]: "   LOCALE;   LOCALE="${LOCALE:-en_US.UTF-8}"
[[ -n "$HOSTNAME" && -n "$USERNAME" ]] || err "Hostname and username cannot be empty."
[[ -f "/usr/share/zoneinfo/$TIMEZONE" ]] || warn "Timezone '$TIMEZONE' not found in zoneinfo — double-check spelling."

# ── 4. Bootloader ───────────────────────────────────────────────
hr; echo -e "${BOLD} 4. Bootloader${NC}"; hr
echo "  1) systemd-boot  (recommended · no extra package · EFI-only)"
echo "  2) GRUB          (wider compatibility · supports legacy BIOS)"
read -rp "Select [1-2] (default 1): " _bl; _bl="${_bl:-1}"
[[ "$_bl" == "2" ]] && BOOTLOADER="grub" || BOOTLOADER="systemd-boot"

# ── 5. Passwords ────────────────────────────────────────────────
hr; echo -e "${BOLD} 5. Passwords${NC}"; hr
read -rp "Use a single password for LUKS + root + $USERNAME? (y/N): " _sp
if [[ "$_sp" =~ ^[Yy]$ ]]; then
    get_verified_password "Unified Password" _UP
    LUKS_PASS="$_UP"; ROOT_PASS="$_UP"; USER_PASS="$_UP"
else
    get_verified_password "LUKS Encryption Password"  LUKS_PASS
    get_verified_password "Root Password"              ROOT_PASS
    get_verified_password "Password for $USERNAME"     USER_PASS
fi

# ── 6. Final Confirmation ───────────────────────────────────────
hr; echo -e "${BOLD} Summary${NC}"; hr
printf "  %-18s %s\n" "Profile:"    "$PROFILE_NAME"
printf "  %-18s %s\n" "Disk:"       "${RED}${DISK}  ← WILL BE WIPED${NC}"
printf "  %-18s %s\n" "Hostname:"   "$HOSTNAME"
printf "  %-18s %s\n" "Username:"   "$USERNAME"
printf "  %-18s %s\n" "Timezone:"   "$TIMEZONE"
printf "  %-18s %s\n" "Locale:"     "$LOCALE"
printf "  %-18s %s\n" "Bootloader:" "$BOOTLOADER"
printf "  %-18s %s\n" "Microcode:"  "$MICROCODE"
printf "  %-18s %s\n" "GPU Pkgs:"   "${GPU_PKGS[*]}"
[[ -n "$SVC_EXTRA" ]] && printf "  %-18s %s\n" "Extra Services:" "$SVC_EXTRA"
hr
echo -e "${RED}  ALL DATA ON $DISK WILL BE PERMANENTLY DESTROYED.${NC}"
read -rp "  Type 'yes' to continue: " _confirm
[[ "$_confirm" == "yes" ]] || { info "Aborted."; exit 0; }

# ================================================================
#  DISK PREPARATION
# ================================================================
log "Cleaning up existing mounts and LUKS devices..."
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
cryptsetup close cryptroot 2>/dev/null || true
udevadm settle; sleep 1

# nvme/mmcblk partitions use a 'p' separator (e.g. nvme0n1p1)
[[ "$DISK" =~ nvme|mmcblk ]] && P="p" || P=""
EFI_PART="${DISK}${P}1"
ROOT_PART="${DISK}${P}2"

log "Wiping and partitioning ${DISK}..."
wipefs --all --force "$DISK"
sgdisk -Z "$DISK"
sgdisk -n 1:0:+1G  -t 1:ef00 -c 1:"EFI"   "$DISK"   # 1 GB EFI — roomy for dual-boot
sgdisk -n 2:0:0    -t 2:8300 -c 2:"LUKS"  "$DISK"   # rest → LUKS2
partprobe "$DISK"; udevadm settle; sleep 2

log "Formatting LUKS2 with argon2id (3-second benchmark)..."
echo -n "$LUKS_PASS" | cryptsetup luksFormat "$ROOT_PART" \
    --type luks2 --batch-mode --key-file=- \
    --pbkdf argon2id --iter-time 3000
echo -n "$LUKS_PASS" | cryptsetup open "$ROOT_PART" cryptroot --key-file=-

log "Creating Btrfs filesystem and subvolumes..."
mkfs.btrfs -f -L "ARCH_ROOT" /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
for sv in @ @home @snapshots @var_log @var_cache_pacman; do
    btrfs subvolume create "/mnt/$sv"
done
umount /mnt

log "Mounting subvolumes..."
MOPT="noatime,compress=zstd:3,space_cache=v2,discard=async"
mount -o "$MOPT,subvol=@"                /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot}
mount -o "$MOPT,subvol=@home"            /dev/mapper/cryptroot /mnt/home
mount -o "$MOPT,subvol=@snapshots"       /dev/mapper/cryptroot /mnt/.snapshots
mount -o "$MOPT,subvol=@var_log"         /dev/mapper/cryptroot /mnt/var/log
mount -o "$MOPT,subvol=@var_cache_pacman" /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mkfs.fat -F32 -n "EFI" "$EFI_PART"
mount "$EFI_PART" /mnt/boot

# ================================================================
#  MIRROR SETUP & PACKAGE INSTALLATION
# ================================================================
log "Optimizing mirrors (PH → SG → JP)..."
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
if command -v reflector &>/dev/null; then
    reflector --country Philippines,Singapore,Japan --latest 10 --sort rate \
        --save /etc/pacman.d/mirrorlist 2>/dev/null || true
fi
grep -q "geo.mirror.pkgbuild.com" /etc/pacman.d/mirrorlist || \
    echo "Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" >> /etc/pacman.d/mirrorlist
pacman -Sy

# Core packages — profile-independent
BASE_PKGS=(
    # Base system
    base linux linux-firmware base-devel git rust sudo
    efibootmgr dosfstools btrfs-progs
    # Network
    iwd bluez bluez-utils reflector
    # Wayland / Hyprland
    hyprland xdg-desktop-portal-hyprland hyprpaper waybar swaync
    # Audio (PipeWire)
    pipewire pipewire-pulse wireplumber
    # Display manager & Qt theming
    sddm qt5-wayland qt6-wayland qt5ct qt6ct kvantum dconf
    # GUI apps & tools
    alacritty kitty neovim nemo brightnessctl stow
    papirus-icon-theme cantarell-fonts ttf-jetbrains-mono-nerd ttf-font-awesome
    fuzzel cliphist polkit-gnome
    lazygit fastfetch fzf zoxide
    grim slurp swappy
    # System utilities
    zram-generator man-db acpid fwupd
    snapper snap-pac
)

# Add GRUB if selected as bootloader
[[ "$BOOTLOADER" == "grub" ]] && BASE_PKGS+=(grub)

# Assemble final list: base + microcode + GPU + profile extras
ALL_PKGS=("${BASE_PKGS[@]}" "$MICROCODE" "${GPU_PKGS[@]}" "${EXTRA_PKGS[@]}")

log "Installing ${#ALL_PKGS[@]} packages via pacstrap..."
pacstrap /mnt "${ALL_PKGS[@]}"

# ================================================================
#  CHROOT CONFIGURATION
# ================================================================
log "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

# Build systemd service list dynamically from profile
ALL_SERVICES="iwd systemd-resolved bluetooth acpid sddm fstrim.timer snapper-timeline.timer snapper-cleanup.timer"
[[ -n "$SVC_EXTRA" ]] && ALL_SERVICES="$ALL_SERVICES $SVC_EXTRA"

log "Entering chroot — configuring ${PROFILE_NAME}..."

# NOTE: The outer heredoc (<<CHROOT, unquoted) expands all $VARIABLES
# before handing the script to bash in the chroot. Inner <<EOF blocks
# also benefit from this — no escaping needed for our config values.
arch-chroot /mnt /bin/bash <<CHROOT
set -e

# ── Locale & Clock ────────────────────────────────────────────
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# ── Hostname & Hosts ─────────────────────────────────────────
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain  $HOSTNAME
EOF

# ── Users & sudo ─────────────────────────────────────────────
echo "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel,video,input,audio -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# ── IWD (standalone network / DNS via systemd-resolved) ──────
mkdir -p /etc/iwd
cat > /etc/iwd/main.conf <<EOF
[General]
EnableNetworkConfiguration=true
[Network]
NameResolvingService=systemd
EOF

# ── ZRAM swap ────────────────────────────────────────────────
cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
EOF
cat > /etc/sysctl.d/99-zram.conf <<EOF
vm.swappiness = 100
vm.page-cluster = 0
EOF

# ── System-wide environment ──────────────────────────────────
cat >> /etc/environment <<EOF
LIBVA_DRIVER_NAME=$LIBVA_DRIVER
QT_QPA_PLATFORMTHEME=qt5ct
QT_STYLE_OVERRIDE=kvantum
EOF

# ── mkinitcpio (encrypt + btrfs hooks) ───────────────────────
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf keyboard keymap block encrypt filesystems btrfs fsck)/' \
    /etc/mkinitcpio.conf
mkinitcpio -P

# ── Bootloader ───────────────────────────────────────────────
if [[ "$BOOTLOADER" == "systemd-boot" ]]; then
    bootctl install
    mkdir -p /boot/loader/entries

    cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
console-mode max
editor  no
EOF

    # Normal entry
    cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux ($PROFILE_NAME)
linux   /vmlinuz-linux
initrd  /$MICROCODE.img
initrd  /initramfs-linux.img
options cryptdevice=UUID=$ROOT_UUID:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw $KERNEL_PARAMS loglevel=3 quiet
EOF

    # Fallback entry (verbose, no quiet)
    cat > /boot/loader/entries/arch-fallback.conf <<EOF
title   Arch Linux — Fallback ($PROFILE_NAME)
linux   /vmlinuz-linux
initrd  /$MICROCODE.img
initrd  /initramfs-linux-fallback.img
options cryptdevice=UUID=$ROOT_UUID:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw $KERNEL_PARAMS
EOF

else
    # GRUB
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$ROOT_UUID:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ $KERNEL_PARAMS loglevel=3 quiet\"|" \
        /etc/default/grub
    # Enable GRUB to unlock LUKS at boot
    sed -i 's/^#\(GRUB_ENABLE_CRYPTODISK=y\)/\1/' /etc/default/grub
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
    grub-mkconfig -o /boot/grub/grub.cfg
fi

# ── Snapper ──────────────────────────────────────────────────
# NOTE: 'snapper create-config' requires a live D-Bus session and
# CANNOT run inside a chroot. The timers are enabled here so they
# are ready to fire, but the actual config is created by post-install.sh
# on first boot (Step 4), which runs on the live system.

# ── Enable systemd services ──────────────────────────────────
systemctl enable $ALL_SERVICES

CHROOT

# ── Teardown ────────────────────────────────────────────────────
log "Unmounting filesystems..."
umount -R /mnt
cryptsetup close cryptroot

hr
echo -e "${GREEN}  ✓ Installation complete! (${PROFILE_NAME})${NC}"
hr
echo "  Next steps:"
echo "  1. reboot — remove the USB drive when the screen goes dark"
echo "  2. Unlock LUKS, then connect to Wi-Fi:"
echo "     iwctl station wlan0 connect <YOUR_SSID>"
echo "  3. git clone <your-dotfiles-repo> && ./post-install.sh"
hr
