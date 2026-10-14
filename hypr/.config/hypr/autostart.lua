-- =====================================================
--  Autostart  (was: exec-once)
-- =====================================================
--
-- Everything here ran as exec-once in the old config. The two gsettings
-- lines lived further down the old file under "GTK theming"; they are
-- grouped here because exec-once ordering does not matter for them.

local home = os.getenv("HOME") or ""

hl.on("hyprland.start", function()
    -- Status bar and notification daemon
    hl.exec_cmd("waybar & swaync")

    -- PolicyKit authentication agent
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Wallpaper. Was hardcoded to /home/Eddie/.config/hypr/hyprpaper.conf;
    -- built from $HOME so it survives a username change.
    hl.exec_cmd("hyprpaper -c " .. home .. "/.config/hypr/hyprpaper.conf")

    -- GTK theming
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'catppuccin-mocha-mauve-standard+default'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
end)
