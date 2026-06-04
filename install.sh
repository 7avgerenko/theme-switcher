#!/usr/bin/env bash
set -euo pipefail

# ─── theme-switcher install ─────────────────────────────────────
# Idempotent — safe to run repeatedly. Symlinks the tray app into
# ~/.config/theme/ and sets up Alacritty, Micro, Fish, and i3.
# The repo itself is NOT needed after install (the tray app is copied).
# ─────────────────────────────────────────────────────────────────

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_THEME_DIR="$HOME/.config/theme"
ALACRITTY_CONFIG="$HOME/.config/alacritty/alacritty.toml"
ALACRITTY_THEMES_DIR="$HOME/.config/alacritty/themes"
MICRO_CONFIG="$HOME/.config/micro/settings.json"
FISH_CONFIG="$HOME/.config/fish/config.fish"
FISH_FUNCTIONS_DIR="$HOME/.config/fish/functions"
I3_CONFIG="$HOME/.config/i3/config"

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

say()  { printf "${BOLD}%s${NC}\n" "$*"; }
ok()   { printf "${GREEN}  ✔${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}  ⚠${NC} %s\n" "$*"; }
err()  { printf "${RED}  ✘${NC} %s\n" "$*"; }

# ─── 1. check dependencies ──────────────────────────────────────

say "Checking dependencies..."

MISSING_PKGS=()

if ! python3 -c "import gi; gi.require_version('Gtk','3.0'); gi.require_version('Notify','0.7'); from gi.repository import Gtk, Notify" 2>/dev/null; then
    MISSING_PKGS+=("python3-gi" "gir1.2-gtk-3.0" "gir1.2-notify-0.7")
fi

if ! python3 -c "import cairo" 2>/dev/null; then
    MISSING_PKGS+=("python3-cairo")
fi

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    warn "Missing packages: ${MISSING_PKGS[*]}"
    printf "Install them now? [Y/n] "
    read -r answer
    if [ "$answer" != "n" ] && [ "$answer" != "N" ]; then
        sudo apt install -y "${MISSING_PKGS[@]}"
        ok "Packages installed"
    else
        err "Dependencies missing — install them manually:"
        echo "  sudo apt install ${MISSING_PKGS[*]}"
        exit 1
    fi
else
    ok "Python dependencies present"
fi

# ─── 2. install tray app ────────────────────────────────────────

say "Installing tray app..."

mkdir -p "$CONFIG_THEME_DIR"

# Copy the tray script (not symlink — so repo can be deleted)
if [ -f "$CONFIG_THEME_DIR/theme_tray.py" ]; then
    # Keep a backup if different
    if ! cmp -s "$REPO_DIR/theme_tray.py" "$CONFIG_THEME_DIR/theme_tray.py"; then
        cp "$CONFIG_THEME_DIR/theme_tray.py" "$CONFIG_THEME_DIR/theme_tray.py.bak"
        warn "Backed up existing theme_tray.py → theme_tray.py.bak"
    fi
fi
cp "$REPO_DIR/theme_tray.py" "$CONFIG_THEME_DIR/theme_tray.py"
chmod +x "$CONFIG_THEME_DIR/theme_tray.py"
ok "theme_tray.py → $CONFIG_THEME_DIR/"

# ─── 3. alacritty themes (external dependency) ──────────────────

say "Checking Alacritty themes..."

if [ -d "$ALACRITTY_THEMES_DIR/themes" ]; then
    ok "Alacritty themes already present"
else
    warn "Alacritty themes not found — cloning..."
    git clone https://github.com/alacritty/alacritty-theme "$ALACRITTY_THEMES_DIR"
    ok "Cloned alacritty-theme"
fi

# Verify our theme files exist
for theme in catppuccin_latte.toml catppuccin_mocha.toml; do
    if [ ! -f "$ALACRITTY_THEMES_DIR/themes/$theme" ]; then
        err "Theme file missing: $theme — the alacritty-theme repo may have changed"
        exit 1
    fi
done
ok "Catppuccin Latte + Mocha themes available"

# ─── 4. alacritty config ────────────────────────────────────────

say "Setting up Alacritty..."

# Create config dir if needed
mkdir -p "$(dirname "$ALACRITTY_CONFIG")"

IMPORT_LINE='    "~/.config/alacritty/themes/current.toml"'

if [ -f "$ALACRITTY_CONFIG" ]; then
    if grep -q "current.toml" "$ALACRITTY_CONFIG" 2>/dev/null; then
        ok "Alacritty already imports current.toml"
    else
        # Check if there's an existing import block
        if grep -q "import = \[" "$ALACRITTY_CONFIG" 2>/dev/null; then
            warn "Alacritty has an import block pointing elsewhere — update it manually:"
            echo "  Change the import in $ALACRITTY_CONFIG to:"
            echo "  import = ["
            echo "$IMPORT_LINE"
            echo "  ]"
        else
            # Add the import block before any existing [section]
            warn "Adding import to Alacritty config..."
            # Insert after any [general] line, or at top
            if grep -q '^\[general\]' "$ALACRITTY_CONFIG" 2>/dev/null; then
                sed -i '/^\[general\]/a import = [\n'"$IMPORT_LINE"'\n]' "$ALACRITTY_CONFIG"
            else
                # Insert at beginning
                sed -i '1i import = [\n'"$IMPORT_LINE"'\n]\n' "$ALACRITTY_CONFIG"
            fi
            ok "Added import to Alacritty config"
        fi
    fi
else
    # Create a minimal Alacritty config
    cat > "$ALACRITTY_CONFIG" <<'ALACRITTY_EOF'
[general]
import = [
    "~/.config/alacritty/themes/current.toml"
]

[font]
normal = { family = "JetBrainsMonoNL Nerd Font Mono" }
size = 14

[scrolling]
history = 100000
multiplier = 1

[window]
resize_increments = true
ALACRITTY_EOF
    ok "Created Alacritty config"
fi

# ─── 5. micro config ────────────────────────────────────────────

say "Setting up Micro..."

mkdir -p "$(dirname "$MICRO_CONFIG")"

if [ -f "$MICRO_CONFIG" ]; then
    # Merge colorscheme into existing JSON
    if grep -q '"colorscheme"' "$MICRO_CONFIG" 2>/dev/null; then
        if grep -q '"colorscheme": "simple"' "$MICRO_CONFIG" 2>/dev/null; then
            ok "Micro already set to 'simple' colorscheme"
        else
            warn "Micro colorscheme is set to something else — update manually:"
            echo "  Set \"colorscheme\": \"simple\" in $MICRO_CONFIG"
        fi
    else
        # JSON file exists but no colorscheme key — add it
        # Simple approach: overwrite if it's just {}, otherwise warn
        if [ "$(cat "$MICRO_CONFIG" | tr -d '[:space:]')" = "{}" ]; then
            echo '{"colorscheme": "simple"}' > "$MICRO_CONFIG"
            ok "Set Micro colorscheme to 'simple'"
        else
            warn "Micro config exists with other settings — add manually:"
            echo '  Add "colorscheme": "simple" to '"$MICRO_CONFIG"
        fi
    fi
else
    echo '{"colorscheme": "simple"}' > "$MICRO_CONFIG"
    ok "Created Micro config with 'simple' colorscheme"
fi

# ─── 6. fish prompt ─────────────────────────────────────────────

say "Setting up Fish prompt..."

FISH_PROMPT='function fish_prompt
    set -l last_status $status

    if test $last_status -eq 0
        set_color green
    else
        set_color red
    end

    echo -n '"'"'❯ '"'"'
    set_color normal
end'

mkdir -p "$FISH_FUNCTIONS_DIR"

if [ -f "$FISH_FUNCTIONS_DIR/fish_prompt.fish" ]; then
    if grep -q "last_status" "$FISH_FUNCTIONS_DIR/fish_prompt.fish" 2>/dev/null; then
        ok "Fish prompt already has exit-code coloring"
    else
        cp "$FISH_FUNCTIONS_DIR/fish_prompt.fish" "$FISH_FUNCTIONS_DIR/fish_prompt.fish.bak"
        echo "$FISH_PROMPT" > "$FISH_FUNCTIONS_DIR/fish_prompt.fish"
        ok "Replaced fish prompt (backup saved)"
    fi
elif grep -q "function fish_prompt" "$FISH_CONFIG" 2>/dev/null; then
    ok "Fish prompt defined in config.fish — already present"
else
    echo "$FISH_PROMPT" > "$FISH_FUNCTIONS_DIR/fish_prompt.fish"
    ok "Created fish_prompt.fish"
fi

# ─── 7. i3 config ───────────────────────────────────────────────

say "Setting up i3..."

I3_KEYBIND="bindsym \$mod+F10\t\texec --no-startup-id python3 $CONFIG_THEME_DIR/theme_tray.py --toggle"
I3_AUTOSTART="exec --no-startup-id python3 $CONFIG_THEME_DIR/theme_tray.py"

if [ -f "$I3_CONFIG" ]; then
    if grep -q "theme_tray.py" "$I3_CONFIG" 2>/dev/null; then
        ok "i3 already configured for theme-switcher"
    else
        # Add autostart near other exec lines
        if grep -q "exec --no-startup-id picom" "$I3_CONFIG" 2>/dev/null; then
            sed -i '/exec --no-startup-id picom/a exec --no-startup-id python3 '"$CONFIG_THEME_DIR"'/theme_tray.py' "$I3_CONFIG"
            ok "Added i3 autostart"
        else
            warn "Could not find picom line in i3 config — add this manually:"
            echo "  $I3_AUTOSTART"
        fi

        # Add keybind near other F-key binds
        if grep -q "bindsym \\\$mod+F9" "$I3_CONFIG" 2>/dev/null; then
            sed -i '/bindsym \$mod+F9/a bindsym \$mod+F10\t\texec --no-startup-id python3 '"$CONFIG_THEME_DIR"'/theme_tray.py --toggle' "$I3_CONFIG"
            ok "Added i3 keybind Mod4+F10"
        else
            warn "Could not find Mod4+F9 in i3 config — add this keybind manually:"
            echo "  $I3_KEYBIND"
        fi
    fi
else
    warn "No i3 config found at $I3_CONFIG — skipping"
fi

# ─── 8. initial theme ───────────────────────────────────────────

say "Setting initial theme..."

hour=$(date +%H)
if [ "$hour" -ge 7 ] && [ "$hour" -lt 19 ]; then
    initial="light"
else
    initial="dark"
fi

python3 "$CONFIG_THEME_DIR/theme_tray.py" --toggle 2>/dev/null || true
# Force correct initial theme
echo "$initial" > "$CONFIG_THEME_DIR/current"
ALACRITTY_LINK="$HOME/.config/alacritty/themes/current.toml"
THEME_FILE="catppuccin_latte.toml"
[ "$initial" = "dark" ] && THEME_FILE="catppuccin_mocha.toml"
ln -sf "$ALACRITTY_THEMES_DIR/themes/$THEME_FILE" "$ALACRITTY_LINK"
ok "Initial theme set to $initial"

# ─── 9. done ────────────────────────────────────────────────────

echo ""
say "Installation complete!"
echo ""
echo "  Tray app:  $CONFIG_THEME_DIR/theme_tray.py"
echo "  Keybind:   Mod4+F10 to toggle light/dark"
echo "  Themes:    Catppuccin Latte (day) ↔ Mocha (night)"
echo ""
echo "  Start now:  python3 $CONFIG_THEME_DIR/theme_tray.py &"
echo "  Or reload:  i3: Mod4+F5   fish: exec fish"
echo ""
echo "  The repo at $REPO_DIR can be deleted after install."
