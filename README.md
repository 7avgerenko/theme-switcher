# theme-switcher

A system-tray theme toggler for Alacritty + Fish + Micro on i3/LXQt.

**Left-click** the tray icon or press **Mod4+F10** to flip between light and dark.
Right-click for auto-switch (time-based, 7am–7pm).

## Quick start

```bash
./install.sh
python3 ~/.config/theme/theme_tray.py &
```

Then reload i3 (`Mod4+F5`) or the keybind won't take effect until restart.

## What it sets up

| Tool | What changes |
|---|---|
| **Alacritty** | Imports `~/.config/alacritty/themes/current.toml` — a symlink the tray app flips |
| **Micro** | Sets `colorscheme: "simple"` so it follows terminal ANSI colors |
| **Fish** | Minimal `❯` prompt — green on success, red on failure |
| **i3** | Adds `Mod4+F10` keybind + autostarts the tray on login |

## Themes

- **Day** — Catppuccin Latte (`#EFF1F5` background)
- **Night** — Catppuccin Mocha (`#1E1E2E` background)

The `alacritty-theme` repo is cloned automatically if missing.

## Requirements

- Python 3 with `python3-gi`, `python3-cairo`, GTK 3, and libnotify GI bindings
- Alacritty, Fish, Micro, i3 (the install script checks and warns)

## Files

```
theme_tray.py    — the tray app (copied to ~/.config/theme/)
install.sh       — idempotent installer (safe to re-run)
.gitignore       — ignores runtime state files
```

The repo is not needed after installation — `theme_tray.py` is copied, not symlinked.
