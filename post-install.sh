#!/bin/bash
# Post-install setup for Arch + Hyprland
# Run as root AFTER first boot
set -euo pipefail

# Set variables
USERNAME="your_username_here"  # <-- replace with your actual username

# --------------------------
# Network / WiFi power saving
# --------------------------
mkdir -p /etc/NetworkManager/conf.d/
cat <<EOF > /etc/NetworkManager/conf.d/wifi-powersave.conf
[connection]
wifi.powersave = 2
EOF
systemctl restart NetworkManager

# --------------------------
# ZRAM setup
# --------------------------
pacman -S --noconfirm zram-generator
mkdir -p /etc/systemd/zram-generator.conf.d/
cat <<EOF > /etc/systemd/zram-generator.conf.d/custom-zram.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF
systemctl daemon-reexec
systemctl enable --now /dev/zram0.swap || echo "ZRAM service may require a reboot to work properly"

# --------------------------
# Install essential AUR packages
# --------------------------
sudo -u "$USERNAME" paru -S --noconfirm \
uwsm libnewt mesa libva libva-utils libva-intel-driver hyprpolkitagent \
waybar swaync qt5-wayland qt6-wayland cliphist dolphin swww qt5ct qt6ct kvantum \
ttf-firacode-nerd hyprpaper wlsunset pipewire wireplumber pipewire-pulse \
catppuccin-gtk-theme-mocha ttf-ms-fonts

# --------------------------
# Enable user services
# --------------------------
sudo -u "$USERNAME" systemctl --user enable --now hyprpolkitagent.service
sudo -u "$USERNAME" systemctl --user enable --now pipewire-pulse.service

# --------------------------
# Configure GTK theme to Catppuccin Mocha
# --------------------------
sudo -u "$USERNAME" bash -c 'gsettings set org.gnome.desktop.interface gtk-theme "Catppuccin-Mocha"'
sudo -u "$USERNAME" bash -c 'gsettings set org.gnome.desktop.interface icon-theme "Papirus"'

# GTK2 fallback
sudo -u "$USERNAME" bash -c 'mkdir -p /home/$USER/.config/gtk-2.0 && echo "gtk-theme-name=\"Catppuccin-Mocha\"\ngtk-icon-theme-name=\"Papirus\"" > /home/$USER/.config/gtk-2.0/gtkrc'

# --------------------------
# Configure Kvantum / Qt theme
# --------------------------
# Ensure environment variables for Qt apps (you can also keep in hyprland.conf)
cat <<EOF > /home/$USERNAME/.xprofile
export QT_QPA_PLATFORMTHEME=qt5ct
export QT_STYLE_OVERRIDE=kvantum
export QT6CT_PLATFORMTHEME=qt6ct
export QT_AUTO_SCREEN_SCALE_FACTOR=1
EOF

sudo -u "$USERNAME" kvantum-manager --set Catppuccin-Mocha || echo "You can select Catppuccin-Mocha manually in Kvantum Manager"

echo "Post-install setup complete! GTK and Qt should now default to Catppuccin Mocha."
