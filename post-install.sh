#!/bin/bash
# =====================================================
#  Post-Install Setup (Paru, Themes, Stow)
#  Run this AFTER rebooting into your new system.
# =====================================================

set -e

# Prevent running as root
if [ "$EUID" -eq 0 ]; then
  echo "Please do not run this script as root. Run it as your normal user."
  exit 1
fi

echo ":: 1/5 Ensuring Network & DNS..."
if ! ping -c 1 archlinux.org &> /dev/null; then
    echo "Network not reachable. Forcing DNS fallback..."
    echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null
fi

echo ":: 2/5 Compiling Paru from Source..."
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

echo ":: 3/5 Installing AUR Packages & Themes..."
# Added throttled, topgrade, nwg-look, and proper Catppuccin AUR theme packages
paru -S --noconfirm topgrade throttled kvantum-theme-catppuccin-git catppuccin-gtk-theme-mocha

echo ":: 4/5 Configuring Visuals (Mocha)..."
mkdir -p ~/.config/{gtk-3.0,gtk-4.0,Kvantum,qt5ct}

# Apply using gsettings (Crucial for Wayland/Hyprland)
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Catppuccin-Mocha-Standard-Blue-Dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface font-name 'JetBrainsMono Nerd Font 11'

# Fallback for older GTK3/GTK4 apps
cat > ~/.config/gtk-3.0/settings.ini <<INI
[Settings]
gtk-theme-name=Catppuccin-Mocha-Standard-Blue-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrainsMono Nerd Font 11
gtk-application-prefer-dark-theme=1
INI

cat > ~/.config/gtk-4.0/settings.ini <<INI
[Settings]
gtk-theme-name=Catppuccin-Mocha-Standard-Blue-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrainsMono Nerd Font 11
gtk-application-prefer-dark-theme=1
INI

# Kvantum (Qt) Settings
cat > ~/.config/Kvantum/kvantum.kvconfig <<INI
[General]
theme=Catppuccin-Mocha-Blue
INI

echo ":: Configuring Btrfs Snapshots..."
sudo umount /.snapshots || true
sudo rm -rf /.snapshots
sudo snapper -c root create-config /
sudo mount -a
sudo chmod 750 /.snapshots

echo ":: 5/5 Running GNU Stow..."
# Clear out any default configs that Hyprland/Waybar created so stow doesn't conflict
rm -rf ~/.config/hypr ~/.config/waybar 2>/dev/null

# Make sure we are in the repo directory (Change this path if your repo name is different)
if [ -d "$HOME/git-files/My-Arch-Setup" ]; then
    cd ~/git-files/My-Arch-Setup
    echo "Stowing hyprland and waybar..."
    stow -t ~ hypr
    stow -t ~ waybar
else
    echo "WARNING: Could not find ~/git-files/My-Arch-Setup. Please stow manually."
fi

echo ":: Setting up Shell Productivity Tools..."
cat >> ~/.bashrc <<EOF

# GOAT Shell Tools
eval "\$(zoxide init bash)"
source /usr/share/fzf/completion.bash 2>/dev/null
source /usr/share/fzf/key-bindings.bash 2>/dev/null

# Better Git Workflow (for your CS projects)
alias lg='lazygit'
alias update='topgrade'
EOF

echo ":: Applying ThinkPad Thermal Fixes..."
sudo systemctl enable --now throttled.service
sudo powertop --auto-tune

echo ":: Protecting Dual Battery Health..."
sudo tlp setthreshold 75 80 BAT0
sudo tlp setthreshold 75 80 BAT1

sudo sed -i 's/#START_CHARGE_THRESH_BAT0=75/START_CHARGE_THRESH_BAT0=75/' /etc/tlp.conf
sudo sed -i 's/#STOP_CHARGE_THRESH_BAT0=80/STOP_CHARGE_THRESH_BAT0=80/' /etc/tlp.conf
sudo sed -i 's/#START_CHARGE_THRESH_BAT1=75/START_CHARGE_THRESH_BAT1=75/' /etc/tlp.conf
sudo sed -i 's/#STOP_CHARGE_THRESH_BAT1=80/STOP_CHARGE_THRESH_BAT1=80/' /etc/tlp.conf

echo "================================================="
echo "DONE! Setup Complete."
echo "Reboot or restart Hyprland to apply the themes."
echo "================================================="
