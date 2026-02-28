#!/bin/bash
# =====================================================
#  Post-Install Setup (Paru, System, Stow)
#  Run this AFTER rebooting into your new system.
# =====================================================

set -e

# Prevent running as root
if [ "$EUID" -eq 0 ]; then
  echo "Please do not run this script as root. Run it as your normal user."
  exit 1
fi

echo ":: 1/4 Ensuring Network & DNS..."
if ! ping -c 1 archlinux.org &> /dev/null; then
    echo "Network not reachable. Forcing DNS fallback..."
    echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null
fi

echo ":: 2/4 Compiling Paru from Source..."
if ! command -v paru &> /dev/null; then
    rm -rf ~/paru
    git clone https://aur.archlinux.org/paru.git ~/paru
    cd ~/paru
    makepkg -si --noconfirm
    cd ..
    rm -rf ~/paru
else
    echo "Paru is already installed. Skipping."
fi

echo ":: 3/4 Installing System Utilities..."
paru -S --noconfirm topgrade throttled

echo ":: Configuring Btrfs Snapshots..."
sudo umount /.snapshots || true
sudo rm -rf /.snapshots
sudo snapper -c root create-config /
sudo mount -a
sudo chmod 750 /.snapshots

echo ":: 4/4 Running GNU Stow..."
# Clear out any default configs that Hyprland/Waybar created so stow doesn't conflict
rm -rf ~/.config/hypr ~/.config/waybar 2>/dev/null

echo "Stowing hyprland and waybar..."
stow -t ~ hypr
stow -t ~ waybar

echo ":: Setting up Shell Productivity Tools..."
cat >> ~/.bashrc <<EOF

# Shell Tools
eval "\$(zoxide init bash)"
source /usr/share/fzf/completion.bash 2>/dev/null
source /usr/share/fzf/key-bindings.bash 2>/dev/null

# Better Git Workflow
alias lg='lazygit'
alias update='topgrade'
EOF

echo ":: Applying ThinkPad Thermal Fixes..."
sudo systemctl enable --now throttled.service

echo ":: Protecting Dual Battery Health..."
sudo tlp setthreshold 75 80 BAT0
sudo tlp setthreshold 75 80 BAT1

sudo sed -i 's/#START_CHARGE_THRESH_BAT0=75/START_CHARGE_THRESH_BAT0=75/' /etc/tlp.conf
sudo sed -i 's/#STOP_CHARGE_THRESH_BAT0=80/STOP_CHARGE_THRESH_BAT0=80/' /etc/tlp.conf
sudo sed -i 's/#START_CHARGE_THRESH_BAT1=75/START_CHARGE_THRESH_BAT1=75/' /etc/tlp.conf
sudo sed -i 's/#STOP_CHARGE_THRESH_BAT1=80/STOP_CHARGE_THRESH_BAT1=80/' /etc/tlp.conf

echo "================================================="
echo "DONE! Setup Complete."
echo "================================================="
