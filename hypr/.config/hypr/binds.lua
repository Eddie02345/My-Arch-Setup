-- =====================================================
--  Keybindings
-- =====================================================

local mainMod  = "SUPER"       -- was: $mainMod = SUPER
local terminal = "alacritty"

-- ── Screenshots (grim + slurp + swappy) ─────────────────────────
-- Super + S        : select area and edit
-- Super + Shift + S: screenshot entire screen to clipboard
hl.bind(mainMod .. " + S",         hl.dsp.exec_cmd([[grim -g "$(slurp)" - | swappy -f -]]))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("grim - | wl-copy"))

-- ── Terminal tools (workflow boosters) ──────────────────────────
-- Launched with '<terminal> -e' to drop straight into the tool
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd(terminal .. " -e lazygit"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(terminal .. " -e btm"))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd(terminal .. [[ -e bash -c "zoxide query -i | xargs -r cd && exec bash"]]))

-- ── File manager & launcher ─────────────────────────────────────
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(terminal .. " -e yazi"))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("fuzzel"))

hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q",      hl.dsp.window.close())

-- ── System / UI ─────────────────────────────────────────────────
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exit())
hl.bind(mainMod .. " + V",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F",         hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("killall waybar; waybar &"))

-- ── ThinkPad media keys (brightnessctl + wireplumber) ───────────
-- bindel was repeating + locked; bindl was locked only
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"),    { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),    { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),   { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"),                        { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"),                        { locked = true, repeating = true })

-- ── Window focus (arrow keys) ───────────────────────────────────
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- ── Workspaces 1–5, and moving the active window to them ────────
for i = 1, 5 do
    hl.bind(mainMod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- ── Scroll through existing workspaces ──────────────────────────
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- ── Move / resize windows with mainMod + LMB / RMB drag ─────────
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
