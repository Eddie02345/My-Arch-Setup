# My Arch Setup

My personal Arch Linux setup: an opinionated installer plus the dotfiles I
actually run, for a ThinkPad T470. The installer also detects an X1 Carbon
Gen 7 and generic Intel/AMD machines and adjusts packages and kernel
parameters accordingly.

The whole thing is LUKS2 (argon2id) + Btrfs + IWD + systemd-resolved, with
Hyprland as the desktop.

## Layout

Every top-level directory is a [GNU Stow](https://www.gnu.org/software/stow/)
package whose contents mirror `$HOME`:

```
hypr/.config/hypr/        Hyprland configuration — Lua
waybar/.config/waybar/    Waybar bar: config.jsonc, style.css, scripts/
```

Supporting files:

| File | Purpose |
| --- | --- |
| `install.sh` | Runs from the Arch ISO. Partitions, encrypts, pacstraps, chroots. **Destroys the target disk.** |
| `post-install.sh` | Runs after first boot. Installs paru + AUR packages, configures snapper and TLP, stows the dotfiles. Idempotent. |
| `pkglist.txt` | Explicit native packages (`pacman -Qqen`). |
| `aur.txt` | AUR / foreign packages (`pacman -Qqem`). |
| `CLAUDE.md` | Notes for AI assistants working in this repo. |

## Hyprland configuration

The config is **Lua** and requires **Hyprland 0.55 or newer**.

`hyprland.lua` is a small entry point that `require()`s one module per
section, all in the same directory:

```
hyprland.lua     entry point — just the require() calls
monitors.lua     output, mode, scale
env.lua          environment variables
autostart.lua    exec-once processes
input.lua        keyboard, mouse, touchpad
appearance.lua   general, decoration, animations, dwindle, misc
binds.lua        keybindings
rules.lua        window / workspace rules
```

To change something, edit the module that owns that section. To add a
section, drop in a new module and `require()` it from `hyprland.lua`.

`hyprland.conf.bak` is the previous `.conf` configuration, kept for history
only — Hyprland does not load it, and it should not be edited.
`hyprpaper.conf` stays a plain `.conf` because hyprpaper has no Lua support.

### Verifying config changes

```bash
luac -p hypr/.config/hypr/*.lua                                     # syntax
bash -n install.sh post-install.sh                                  # shell syntax
hyprland --verify-config -c hypr/.config/hypr/hyprland.lua          # the real check
shellcheck install.sh post-install.sh                               # if installed
```

`hyprland --verify-config` executes the config, follows `require()` into the
modules, and rejects unknown configuration keys. It needs no running session,
so it is the safest and strongest check available.

## Installing

`install.sh` wipes the disk it is pointed at. There is no undo.

```bash
# From the Arch ISO
./install.sh --dry-run    # walk the questionnaire, print the plan, change nothing
./install.sh              # for real
```

Then, after reboot and connecting to Wi-Fi:

```bash
git clone <this repo> ~/My-Arch-Setup && cd ~/My-Arch-Setup
./post-install.sh --dry-run   # shows every change, including stow actions
./post-install.sh             # applies them
```

Both scripts support `--dry-run` (`-n`) and `--help`. Use `--dry-run` first —
it is the only supported way to test them.

`post-install.sh` never deletes a file to resolve a conflict: anything in the
way is moved to `.stow-backups/<timestamp>/` with its original path preserved.

## Packages

`pkglist.txt` and `aur.txt` describe what the current machine has installed:

```bash
pacman -S --needed - < pkglist.txt          # native packages
paru -S --needed - < aur.txt                # AUR packages (needs paru)
```

Regenerate them after changing what you use:

```bash
pacman -Qqen > pkglist.txt
pacman -Qqem > aur.txt
```

## graphify

This repo carries a [graphify](https://github.com/sponsors/safishamsi)
knowledge graph in `graphify-out/` (git-ignored — rebuild it locally rather
than committing it).

```bash
graphify query "how does post-install.sh stow the packages"   # scoped subgraph
graphify path "install.sh" "post-install.sh"                  # relationship between two things
graphify explain "stow conflicts"                             # focused concept
graphify update .                                             # refresh after edits (AST only, no API cost)
```

`graphify claude install` wires the graph into Claude Code: it registers
pre-tool hooks and adds the `## graphify` section to `CLAUDE.md`. A
post-commit hook rebuilds the graph automatically after each commit.

## License

GPL-3.0 — see [LICENSE](LICENSE).
