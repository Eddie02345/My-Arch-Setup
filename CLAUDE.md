# CLAUDE.md

Personal Arch Linux setup and dotfiles for a ThinkPad T470. The installer also
carries profiles for an X1 Carbon Gen 7 and generic Intel/AMD machines.
Dotfiles are deployed with GNU Stow.

## Layout

Each top-level directory is a Stow package mirroring `$HOME`:

    hypr/.config/hypr/       Hyprland config — Lua, see below
    waybar/.config/waybar/   Waybar bar (config.jsonc, style.css, scripts/)

    install.sh               Arch install from the live ISO — WIPES THE TARGET DISK
    post-install.sh          first boot: paru, AUR packages, snapper, stow
    pkglist.txt              explicit native packages  (pacman -Qqen)
    aur.txt                  AUR / foreign packages    (pacman -Qqem)
    .stow-backups/           conflicts parked by post-install.sh (gitignored)

## How the scripts work

`install.sh` runs from the Arch ISO: it partitions a disk (LUKS2 + Btrfs
subvolumes), pacstraps a package list, and configures the system in a chroot.
It is destructive and cannot be undone.

`post-install.sh` runs on the installed system as a normal user. It is
idempotent and profile-aware: it installs paru and AUR packages, sets up
snapper and TLP, stows the packages above, and appends shell aliases.

Both scripts **may only ever be tested with `--dry-run`**, which prints every
change and touches nothing.

## Hyprland conventions

- The config is **Lua** and needs Hyprland **0.55+** (this box: 0.56.2).
  `hyprland.lua` is a small entry point that `require()`s one module per
  section, all sitting beside it: `monitors`, `env`, `autostart`, `input`,
  `appearance`, `binds`, `rules`. Add a section as a new module and require it.
- Before using any `hl.*` function or config key, check
  `/usr/share/hypr/stubs/hl.meta.lua` — it is the generated source of truth.
  `/usr/share/hypr/hyprland.lua` is the style reference.
- `hyprland.conf.bak` is history only. **Never edit it or bring it back into
  use** — Hyprland does not load it.
- `hyprpaper.conf` stays plain conf: hyprpaper has no Lua support.

## Verification — run these after any config change

    luac -p hypr/.config/hypr/*.lua
    bash -n install.sh post-install.sh
    hyprland --verify-config -c hypr/.config/hypr/hyprland.lua
    shellcheck install.sh post-install.sh    # not installed on this box

`--verify-config` executes the config, follows `require()`, and rejects unknown
config keys, so it is far stronger than `luac -p` and needs no running session.

## Safety rules

- **Never run `install.sh` or `post-install.sh`.** They wipe disks and
  reconfigure the system. Use `--dry-run` to review them.
- **Never run `stow`.** Stowing belongs to `post-install.sh`; doing it by hand
  litters `$HOME` with symlinks.
- **No `sudo`. Never push. Never commit secrets.**
- Always back up before overwriting. `post-install.sh` parks conflicts in
  `.stow-backups/<timestamp>/` rather than deleting them — keep it that way.
- Treat `~/.config/hypr` and `~/.config/waybar` as read-only references.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
