-- =====================================================
--  Environment Variables (Catppuccin & Wayland)
-- =====================================================

-- GTK_THEME is intentionally not set here. The old hyprlang line was
--   env = env = GTK_THEME,catppuccin-mocha-blue-standard+default
-- The doubled "env =" meant it never took effect, so a literal port to
--   hl.env("GTK_THEME", "catppuccin-mocha-blue-standard+default")
-- would turn a no-op into a real change — and to "blue", which then fights
-- the gsettings theme set in autostart.lua ("mauve"). Dropped cleanly so the
-- live appearance is unchanged; GTK theming is owned by gsettings there.

hl.env("XCURSOR_THEME", "Papirus-Dark")
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("LIBVA_DRIVER_NAME", "iHD")

-- Was: env = XDG_DATA_DIRS,$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:$XDG_DATA_DIRS
-- The old value relied on hyprlang expanding $HOME / $XDG_DATA_DIRS; build the
-- same literal string here so no expansion is needed.
local home          = os.getenv("HOME") or ""
local xdg_data_dirs = os.getenv("XDG_DATA_DIRS") or ""

hl.env(
    "XDG_DATA_DIRS",
    home .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:" .. xdg_data_dirs
)
