#!/bin/bash
# ================================================================
#  Post-Install Setup v2.0
#  Profile-aware: ThinkPad T470 | X1 Carbon Gen 7 | Generic
#
#  Run as your normal user from inside your dotfiles directory:
#    cd ~/dotfiles && bash post-install.sh
#
#  Test it safely first:
#    bash post-install.sh --dry-run
# ================================================================
set -euo pipefail

# ── Colors & Logging ────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m';   CYAN='\033[0;36m'
BOLD='\033[1m';     NC='\033[0m'
log()  { echo -e "${GREEN}[>>]  $*${NC}"; }
info() { echo -e "${CYAN}[--]  $*${NC}"; }
warn() { echo -e "${YELLOW}[!!]  $*${NC}"; }
err()  { echo -e "${RED}[XX]  $*${NC}" >&2; exit 1; }
ok()   { echo -e "${GREEN}[OK]  $*${NC}"; }
hr()   { echo -e "${BOLD}────────────────────────────────────────────────${NC}"; }
step() { echo; hr; echo -e "${BOLD}  $*${NC}"; hr; }

# ── Safety Guards ───────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] && err "Do not run as root. Run as your normal user."

# ── Options ─────────────────────────────────────────────────────
# --dry-run prints every change instead of making it. Nothing is written,
# installed, moved or removed while it is active.
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        --help|-h)
            cat <<'USAGE'
post-install.sh [--dry-run]

  -n, --dry-run   Show every change that would be made, touch nothing.
  -h, --help      Show this text.

Run with --dry-run before a real run: it is the only supported way to
test this script.
USAGE
            exit 0 ;;
        *) err "Unknown option: '$arg' (try --help)" ;;
    esac
done

if (( DRY_RUN )); then
    warn "DRY RUN — no changes will be made."
    # 'run' executes a command normally, or prints it under --dry-run.
    run() { printf '  %s[dry-run]%s %s\n' "$CYAN" "$NC" "$*"; }
else
    run() { "$@"; }
fi

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
info "Dotfiles dir: ${DOTFILES_DIR}"

# ================================================================
#  HARDWARE PROFILE DETECTION
#  Mirrors the same logic as install.sh so behaviour is consistent.
# ================================================================
detect_profile() {
    local name version combined
    name=$(cat /sys/class/dmi/id/product_name    2>/dev/null || true)
    version=$(cat /sys/class/dmi/id/product_version 2>/dev/null || true)
    combined="$name $version"

    if   [[ "$combined" =~ [Xx]1[[:space:]][Cc]arbon.*7 || "$name" =~ ^20Q[DE] ]]; then echo "X1C7"
    elif [[ "$combined" =~ T470 ]];                                                       then echo "T470"
    elif grep -qi "amd" /proc/cpuinfo 2>/dev/null;                                        then echo "AMD"
    else echo "INTEL"; fi
}

apply_profile() {
    case "$1" in
    T470)
        PROFILE_NAME="ThinkPad T470"
        # throttled fixes the Intel ME power-limit firmware bug present on
        # Kaby Lake ThinkPads — prevents artificial sustained-load throttling.
        # NOT needed on X1C7 where thermald handles this correctly.
        AUR_PROFILE_PKGS=(throttled)
        ENABLE_THROTTLED=1
        ENABLE_DUAL_BATTERY=1   # T470 supports a rear slice battery (BAT1)
        ;;
    X1C7)
        PROFILE_NAME="ThinkPad X1 Carbon Gen 7"
        # thermald was already installed + enabled by install.sh — skip throttled.
        AUR_PROFILE_PKGS=()
        ENABLE_THROTTLED=0
        ENABLE_DUAL_BATTERY=0   # X1C7 has a single internal battery only (BAT0)
        ;;
    AMD|INTEL)
        PROFILE_NAME="Generic $1 System"
        AUR_PROFILE_PKGS=()
        ENABLE_THROTTLED=0
        ENABLE_DUAL_BATTERY=0
        ;;
    esac
}

PROFILE=$(detect_profile)
apply_profile "$PROFILE"

clear
echo -e "${BOLD}"
echo " ╔══════════════════════════════════════════════════╗"
echo " ║       POST-INSTALL SETUP  v2.0                 ║"
echo " ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
info "Detected profile: ${GREEN}${PROFILE_NAME}${NC}"
(( DRY_RUN )) && warn "Running in DRY RUN mode — nothing will be changed."
echo

# ================================================================
#  STEP 1 — NETWORK & DNS
# ================================================================
step "1 / 6 — Network & DNS"

if ping -c 1 -W 3 archlinux.org &>/dev/null; then
    ok "Network is up."
elif (( DRY_RUN )); then
    warn "Network check failed, but this is a dry run."
    info "[dry-run] would write /etc/systemd/resolved.conf.d/fallback.conf (FallbackDNS=1.1.1.1 1.0.0.1 8.8.8.8)"
    info "[dry-run] would restart systemd-resolved"
else
    warn "DNS not resolving — injecting Cloudflare fallback via systemd-resolved..."
    # Writing directly to /etc/resolv.conf breaks systemd-resolved's symlink.
    # The correct fix is a drop-in resolved config with FallbackDNS.
    sudo mkdir -p /etc/systemd/resolved.conf.d
    sudo tee /etc/systemd/resolved.conf.d/fallback.conf > /dev/null <<EOF
[Resolve]
FallbackDNS=1.1.1.1 1.0.0.1 8.8.8.8
EOF
    sudo systemctl restart systemd-resolved
    sleep 2
    ping -c 1 -W 3 archlinux.org &>/dev/null \
        && ok "Network restored." \
        || err "Still no network. Check 'iwctl' / 'systemctl status iwd'."
fi

# ================================================================
#  STEP 2 — PARU (AUR HELPER)
# ================================================================
step "2 / 6 — Paru (AUR helper)"

if command -v paru &>/dev/null; then
    ok "Paru already installed — skipping."
elif (( DRY_RUN )); then
    info "[dry-run] would clone https://aur.archlinux.org/paru.git and build it with 'makepkg -si --noconfirm'"
else
    log "Cloning and building paru from AUR..."
    local_paru=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$local_paru"
    pushd "$local_paru" > /dev/null
    makepkg -si --noconfirm
    popd > /dev/null
    rm -rf "$local_paru"
    ok "Paru installed."
fi

# ================================================================
#  STEP 3 — AUR PACKAGES
# ================================================================
step "3 / 6 — AUR Packages"

# Common AUR packages for all profiles
AUR_COMMON=(topgrade nwg-look)

# Combine with profile-specific packages
ALL_AUR=("${AUR_COMMON[@]}" "${AUR_PROFILE_PKGS[@]}")

if [[ ${#ALL_AUR[@]} -gt 0 ]]; then
    if (( DRY_RUN )); then
        info "[dry-run] paru -S --noconfirm ${ALL_AUR[*]}"
    else
        log "Installing: ${ALL_AUR[*]}"
        paru -S --noconfirm "${ALL_AUR[@]}"
    fi
fi

# T470 only: enable the throttled daemon
if [[ "$ENABLE_THROTTLED" -eq 1 ]]; then
    log "Enabling throttled (Intel power-limit fix)..."
    run sudo systemctl enable --now throttled.service
    ok "throttled running."
fi

# ================================================================
#  STEP 4 — SNAPPER SNAPSHOT CONFIGURATION
# ================================================================
step "4 / 6 — Snapper"

# The install.sh already runs snapper create-config in chroot.
# This block is here as an idempotent safety net and to set sane limits.
if snapper -c root list &>/dev/null; then
    ok "Snapper 'root' config already exists."
elif (( DRY_RUN )); then
    info "[dry-run] would run: umount /.snapshots; rm -rf /.snapshots; snapper -c root create-config /; mount -a"
else
    log "Creating snapper root config..."
    sudo umount /.snapshots 2>/dev/null || true
    sudo rm -rf /.snapshots
    sudo snapper -c root create-config /
    sudo mount -a
fi

# Protect the .snapshots dir from other users
run sudo chmod 750 /.snapshots
run sudo chown root:wheel /.snapshots 2>/dev/null || true

# Tighten snapshot retention so the Btrfs volume doesn't balloon.
# Hourly: keep 5, Daily: 7, Weekly: 2, Monthly: 1, Yearly: 0
run sudo snapper -c root set-config \
    NUMBER_LIMIT=10          \
    NUMBER_LIMIT_IMPORTANT=5 \
    TIMELINE_LIMIT_HOURLY=5  \
    TIMELINE_LIMIT_DAILY=7   \
    TIMELINE_LIMIT_WEEKLY=2  \
    TIMELINE_LIMIT_MONTHLY=1 \
    TIMELINE_LIMIT_YEARLY=0
ok "Snapper configured."

# ================================================================
#  STEP 5 — GNU STOW (DOTFILES)
# ================================================================
step "5 / 6 — GNU Stow (Dotfiles)"

# Stow packages to attempt — each must be a top-level dir in $DOTFILES_DIR.
# The script skips any that don't exist in your repo.
STOW_PACKAGES=(hypr waybar nvim kitty alacritty bash zsh)

# Corresponding paths to clean before stowing to avoid conflicts.
# Add entries here whenever you add new stow packages above.
declare -A STOW_CONFLICTS=(
    [hypr]="${HOME}/.config/hypr"
    [waybar]="${HOME}/.config/waybar"
    [nvim]="${HOME}/.config/nvim"
    [kitty]="${HOME}/.config/kitty"
    [alacritty]="${HOME}/.config/alacritty"
)

# Nothing is ever deleted: anything moved out of the way is parked here,
# preserving its original path underneath.
BACKUP_DIR="${DOTFILES_DIR}/.stow-backups/$(date +%Y%m%d-%H%M%S)"

backup_path() {
    local path="$1" dest="${BACKUP_DIR}${1}"
    if (( DRY_RUN )); then
        info "[dry-run] would back up ${path} -> ${dest}"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    mv "$path" "$dest"
    warn "Backed up: ${path} -> ${dest}"
}

# True when $1 is a symlink that already points into the stow package $2.
is_stowed() {
    [[ -L "$1" ]] || return 1
    local target; target=$(readlink -f "$1") || return 1
    [[ "$target" == "$(readlink -f "$2")" ]]
}

# ── Hyprland .conf → .lua migration guard ───────────────────────
# This repo now ships hyprland.lua (+ modules). A real, non-symlink
# ~/.config/hypr/hyprland.conf left over from the previous setup would
# shadow it, so it gets parked along with the rest of the conflicting
# directory below. Purely informational — the move happens in the loop.
HYPR_TARGET="${HOME}/.config/hypr"
if [[ -d "$HYPR_TARGET" && ! -L "$HYPR_TARGET" && -f "${HYPR_TARGET}/hyprland.conf" ]]; then
    warn "Legacy ${HYPR_TARGET}/hyprland.conf found — Hyprland loads hyprland.lua now; it will be backed up."
fi

stowed=()
skipped=()

for pkg in "${STOW_PACKAGES[@]}"; do
    pkg_path="${DOTFILES_DIR}/${pkg}"
    if [[ ! -d "$pkg_path" ]]; then
        skipped+=("$pkg")
        continue
    fi

    # Deal with the known conflict path for this package, if any.
    conflict="${STOW_CONFLICTS[$pkg]:-}"
    if [[ -n "$conflict" ]] && [[ -e "$conflict" || -L "$conflict" ]]; then
        if is_stowed "$conflict" "$pkg_path"; then
            # Already stowed — stow is idempotent, re-running just picks up
            # any files added to the package since the last run.
            info "Already stowed: ${pkg}"
        elif [[ -L "$conflict" ]]; then
            # A symlink that is not ours. Never delete it: we do not know
            # what it points at, and clobbering it could destroy user data.
            warn "${conflict} is a symlink to '$(readlink "$conflict")' — not managed by this repo."
            warn "Leaving it alone and skipping '${pkg}'. Resolve it by hand, then re-run."
            skipped+=("$pkg")
            continue
        else
            backup_path "$conflict"
        fi
    fi

    if (( DRY_RUN )); then
        info "[dry-run] stow --dir=${DOTFILES_DIR} --target=${HOME} ${pkg}"
        stowed+=("$pkg")
        continue
    fi

    if stow --dir="$DOTFILES_DIR" --target="$HOME" "$pkg" 2>/dev/null; then
        ok "Stowed: $pkg"
        stowed+=("$pkg")
    else
        warn "Stow conflict in '$pkg' — run 'stow -nvt ~ $pkg' to inspect."
    fi
done

[[ ${#skipped[@]} -gt 0 ]] && info "Skipped (not in repo, or unresolved): ${skipped[*]}"
(( DRY_RUN )) || { [[ -d "$BACKUP_DIR" ]] && info "Backups from this run: ${BACKUP_DIR}"; }

# ================================================================
#  STEP 6 — SHELL & SYSTEM CONFIGURATION
# ================================================================
step "6 / 6 — Shell, TLP & Firmware"

# ── Shell productivity tools ──────────────────────────────────
# Detect the active login shell and write to the right RC file.
case "$SHELL" in
    */zsh)  SHELL_RC="${HOME}/.zshrc";  SHELL_NAME="zsh" ;;
    */fish) SHELL_RC="";                SHELL_NAME="fish" ;;
    *)      SHELL_RC="${HOME}/.bashrc"; SHELL_NAME="bash" ;;
esac

SHELL_MARKER="# === post-install additions ==="

if [[ -n "$SHELL_RC" ]] && ! grep -qF "$SHELL_MARKER" "$SHELL_RC" 2>/dev/null; then
    if (( DRY_RUN )); then
        info "[dry-run] would append zoxide/fzf init and aliases to ${SHELL_RC}"
    else
        log "Appending shell tools to ${SHELL_RC}..."
        cat >> "$SHELL_RC" <<'SHELLCFG'

# === post-install additions ===

# Smarter directory jumping
eval "$(zoxide init bash)"     # change 'bash' to 'zsh' if using zsh

# FZF completions & keybindings
[[ -f /usr/share/fzf/completion.bash   ]] && source /usr/share/fzf/completion.bash
[[ -f /usr/share/fzf/key-bindings.bash ]] && source /usr/share/fzf/key-bindings.bash

# Aliases
alias lg='lazygit'
alias ff='fastfetch'
alias update='topgrade'
alias ls='ls --color=auto'
alias ll='ls -lah'
alias grep='grep --color=auto'
SHELLCFG
        ok "Shell config written to ${SHELL_RC}."
    fi
elif [[ -z "$SHELL_RC" ]]; then
    warn "Fish shell detected — add zoxide/fzf init to ~/.config/fish/config.fish manually."
else
    info "Shell additions already present in ${SHELL_RC} — skipping."
fi

# ── TLP Battery Charge Thresholds ────────────────────────────
# Keeps batteries between 75–80% to maximise long-term health.
# NOTE: 'tlp setthreshold' is not a valid command — the correct
# approach is to edit tlp.conf and restart the TLP service.
if command -v tlp &>/dev/null; then
    log "Configuring TLP battery thresholds (75 / 80)..."
    TLP_CONF="/etc/tlp.conf"

    # Uncomment and set BAT0 thresholds (present on all ThinkPads)
    run sudo sed -i 's/^#\?\(START_CHARGE_THRESH_BAT0\)=.*/\1=75/' "$TLP_CONF"
    run sudo sed -i 's/^#\?\(STOP_CHARGE_THRESH_BAT0\)=.*/\1=80/'  "$TLP_CONF"

    # BAT1 only exists on T470 (rear slice battery slot)
    if [[ "$ENABLE_DUAL_BATTERY" -eq 1 ]]; then
        run sudo sed -i 's/^#\?\(START_CHARGE_THRESH_BAT1\)=.*/\1=75/' "$TLP_CONF"
        run sudo sed -i 's/^#\?\(STOP_CHARGE_THRESH_BAT1\)=.*/\1=80/'  "$TLP_CONF"
        info "Dual-battery thresholds set (BAT0 + BAT1)."
    else
        info "Single-battery threshold set (BAT0 only)."
    fi

    # Apply immediately without reboot
    run sudo tlp start
    ok "TLP thresholds applied."
else
    info "TLP not installed — skipping battery thresholds."
fi

# ── Firmware Updates ─────────────────────────────────────────
# Check LVFS for available firmware (does NOT auto-apply — review first).
if command -v fwupdmgr &>/dev/null; then
    log "Checking for firmware updates via fwupd..."
    if (( DRY_RUN )); then
        info "[dry-run] would run 'fwupdmgr refresh --force' and 'fwupdmgr get-updates'"
    else
        sudo fwupdmgr refresh --force 2>/dev/null || warn "fwupdmgr refresh failed (check network/LVFS)."
        echo
        fwupdmgr get-updates 2>/dev/null || info "No firmware updates available right now."
        echo
        info "To apply firmware updates: sudo fwupdmgr update"
    fi
fi

# ================================================================
#  DONE
# ================================================================
hr
if (( DRY_RUN )); then
    echo -e "${YELLOW}${BOLD}  ▸ Dry run complete — nothing was changed.${NC}"
else
    echo -e "${GREEN}${BOLD}  ✓ Post-install complete! (${PROFILE_NAME})${NC}"
fi
hr
echo
echo "  Stowed packages : ${stowed[*]:-none}"
echo "  Shell config    : ${SHELL_RC:-not configured (fish)}"
echo
echo "  Recommended next steps:"
echo "   1. source ${SHELL_RC:-~/.bashrc}   (reload shell)"
echo "   2. Verify VAAPI:  vainfo"
echo "   3. Reboot to pick up TLP / kernel param changes"
[[ "$ENABLE_THROTTLED" -eq 1 ]] && \
echo "   4. Check throttled: systemctl status throttled"
hr
