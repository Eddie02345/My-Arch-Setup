#!/bin/bash
# =====================================================
#  Post-Install Setup (Paru, Themes, Stow)
#  Run this AFTER rebooting into your new system.
# =====================================================

set -e

# Prevent running as root (makepkg will fail if run as root)
if [ "$EUID" -eq 0 ]; then
  echo "Please do not run this script as root. Run it as your normal user."
  exit 1
fi

echo ":: 1/4 Ensuring Network & DNS..."
# Quick test to make sure systemd-resolved is working
if ! ping -c 1 archlinux.org &> /dev/null; then
    echo "Network not reachable. Forcing DNS fallback..."
    echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null
fi

echo ":: 2/4 Compiling Paru from Source..."
# We compile from source to avoid libalpm mismatched versions
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

echo ":: 3/4 Installing Catppuccin Themes..."
paru -S --noconfirm catppuccin-gtk-theme catppuccin-kvantum

echo ":: 4/4 Configuring Visuals (Mocha)..."
mkdir -p ~/.config/{gtk-3.0,gtk-4.0,Kvantum,qt5ct}

# GTK Settings
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

echo ":: 5/5 Running GNU Stow..."
# Assuming you are running this script from the root of your My-Arch-Setup repo
echo "Stowing dotfiles..."
stow . || echo "Stow encountered a conflict. You may need to manually resolve it."

echo "================================================="
echo "DONE! Setup Complete."
echo "Reboot or restart Hyprland to apply the themes."
echo "================================================="
