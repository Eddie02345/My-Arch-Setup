-- =====================================================
--  Environment Variables (Catppuccin & Wayland)
-- =====================================================

-- TODO(unicode-safe-translation): the old config line was
--   env = env = GTK_THEME,catppuccin-mocha-blue-standard+default
-- The doubled "env =" is a long-standing typo and it is unclear what
-- hyprlang actually did with it (most likely it set a variable literally
-- named "env = GTK_THEME", which setenv() rejects). Left disabled rather
-- than guessed at, because either reading is a behaviour change.
-- If the intent was to set the GTK theme, replace this comment with:
--   hl.env("GTK_THEME", "catppuccin-mocha-blue-standard+default")
--
-- The GTK theme is set via gsettings at startup instead — see autostart.lua.

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
