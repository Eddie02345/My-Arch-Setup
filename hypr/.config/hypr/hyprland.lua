-- =====================================================
--  Hyprland Config: ThinkPad T470  (Lua, Hyprland 0.55+)
-- =====================================================
--
-- Entry point only — every section lives in its own module
-- next to this file, so the whole config stays greppable.
--
-- Verified against /usr/share/hypr/stubs/hl.meta.lua.
-- The previous hyprland.conf is kept as hyprland.conf.bak.

require("monitors")   -- output / mode / scale
require("env")        -- environment variables
require("autostart")  -- exec-once processes
require("input")      -- keyboard, mouse and touchpad
require("appearance") -- general, decoration, animations, dwindle, misc
require("binds")      -- keybindings
require("rules")      -- window / workspace rules
