#!/usr/bin/env python3
"""
Theme tray icon for LXQt + i3.
Left-click toggles light/dark. Right-click opens menu.
i3 keybind: run with --toggle to flip without touching the tray.
SIGUSR1 also toggles the running tray instance.
"""

import os
import sys
import signal
import threading
import time
from datetime import datetime

import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Notify", "0.7")
from gi.repository import Gtk, GdkPixbuf, Notify, GLib

CONFIG_DIR = os.path.expanduser("~/.config/theme")
STATE_FILE = os.path.join(CONFIG_DIR, "current")
AUTO_FILE = os.path.join(CONFIG_DIR, "auto")
PID_FILE = os.path.join(CONFIG_DIR, ".pid")
ALACRITTY_THEMES = os.path.expanduser("~/.config/alacritty/themes/themes")
ALACRITTY_LINK = os.path.expanduser("~/.config/alacritty/themes/current.toml")

LIGHT_THEME = "catppuccin_latte.toml"
DARK_THEME = "catppuccin_mocha.toml"

DAY_START = 7   # switch to light at 7am
DAY_END = 19    # switch to dark at 7pm


# ─── theme state ────────────────────────────────────────────────

def get_current_theme():
    try:
        with open(STATE_FILE) as f:
            return f.read().strip()
    except FileNotFoundError:
        return None


def set_theme(theme):
    theme_file = LIGHT_THEME if theme == "light" else DARK_THEME
    src = os.path.join(ALACRITTY_THEMES, theme_file)
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        f.write(theme)
    if os.path.exists(ALACRITTY_LINK) or os.path.islink(ALACRITTY_LINK):
        os.unlink(ALACRITTY_LINK)
    if os.path.exists(src):
        os.symlink(src, ALACRITTY_LINK)
    print(f"Theme -> {theme}")


def toggle_theme():
    current = get_current_theme() or "light"
    new = "dark" if current == "light" else "light"
    set_theme(new)
    return new


def is_auto_enabled():
    try:
        with open(AUTO_FILE) as f:
            return f.read().strip() == "true"
    except FileNotFoundError:
        return False


def set_auto(enabled):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(AUTO_FILE, "w") as f:
        f.write("true" if enabled else "false")


def auto_theme_for_hour(hour):
    return "light" if DAY_START <= hour < DAY_END else "dark"


# ─── icon drawing ───────────────────────────────────────────────

def _make_pixbuf(draw_fn, size=22):
    """Create a GdkPixbuf from a Cairo drawing function."""
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    ctx = cairo.Context(surface)
    draw_fn(ctx, size)
    surface.flush()
    return GdkPixbuf.Pixbuf.new_from_data(
        bytes(surface.get_data()),
        GdkPixbuf.Colorspace.RGB,
        True,
        8,
        size,
        size,
        surface.get_stride(),
    )


def _draw_sun(ctx, size):
    """Yellow circle with subtle rays."""
    cx, cy = size / 2, size / 2
    r = 6
    # rays
    ctx.set_source_rgba(0.9, 0.65, 0.09, 1.0)
    for angle in [i * 360 / 8 for i in range(8)]:
        import math

        a = math.radians(angle)
        x1 = cx + (r + 2) * math.cos(a)
        y1 = cy + (r + 2) * math.sin(a)
        x2 = cx + (r + 5) * math.cos(a)
        y2 = cy + (r + 5) * math.sin(a)
        ctx.set_line_width(1.5)
        ctx.move_to(x1, y1)
        ctx.line_to(x2, y2)
        ctx.stroke()
    # body
    ctx.set_source_rgba(0.95, 0.75, 0.15, 1.0)
    ctx.arc(cx, cy, r, 0, 6.283)
    ctx.fill()


def _draw_moon(ctx, size):
    """Silver crescent."""
    cx, cy = size / 2, size / 2
    r = 7
    ctx.set_source_rgba(0.54, 0.71, 0.98, 1.0)  # blue
    ctx.arc(cx, cy, r, 0, 6.283)
    ctx.fill()
    # cut out a circle to make crescent
    ctx.set_operator(cairo.OPERATOR_CLEAR)
    ctx.arc(cx + 3, cy - 1, r - 1.5, 0, 6.283)
    ctx.fill()


def create_icon(theme):
    draw = _draw_sun if theme == "light" else _draw_moon
    return _make_pixbuf(draw)


# ─── tray app ───────────────────────────────────────────────────

class ThemeTray:
    def __init__(self):
        self.current_theme = get_current_theme() or "light"
        self.auto_mode = is_auto_enabled()
        self._stop_event = threading.Event()
        self._auto_thread = None

        self.icon = Gtk.StatusIcon()
        self.icon.set_title("Theme Switcher")
        self._update_icon()
        self._update_tooltip()

        self.icon.connect("activate", self._on_left_click)
        self.icon.connect("popup-menu", self._on_right_click)

        if self.auto_mode:
            self._start_auto_switch()

    def _update_icon(self):
        self.icon.set_from_pixbuf(create_icon(self.current_theme))

    def _update_tooltip(self):
        t = f"Theme: {self.current_theme}"
        if self.auto_mode:
            t += " (auto 7am–7pm)"
        self.icon.set_tooltip_text(t)

    def _notify(self):
        try:
            Notify.init("theme-tray")
            n = Notify.Notification.new(
                "Theme",
                f"Switched to {self.current_theme} mode",
                "dialog-information",
            )
            n.set_timeout(2000)
            n.show()
        except Exception:
            pass

    def _on_left_click(self, *args):
        self._do_toggle()

    def _on_right_click(self, icon, button, time):
        menu = Gtk.Menu()

        item = Gtk.MenuItem(
            label="Switch to Dark" if self.current_theme == "light" else "Switch to Light"
        )
        item.connect("activate", lambda w: self._do_toggle())
        menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())

        auto = Gtk.CheckMenuItem(label="Auto-switch (7am – 7pm)")
        auto.set_active(self.auto_mode)
        auto.connect("toggled", self._on_auto_toggled)
        menu.append(auto)

        menu.append(Gtk.SeparatorMenuItem())

        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", lambda w: self._quit())
        menu.append(quit_item)

        menu.show_all()
        menu.popup(None, None, Gtk.StatusIcon.position_menu, icon, button, time)

    def _do_toggle(self):
        self.current_theme = toggle_theme()
        self._update_icon()
        self._update_tooltip()
        self._notify()

    def _refresh(self):
        """Re-read state from disk and update icon (for SIGUSR1)."""
        theme = get_current_theme()
        if theme and theme != self.current_theme:
            self.current_theme = theme
            self._update_icon()
            self._update_tooltip()

    def _on_auto_toggled(self, item):
        self.auto_mode = item.get_active()
        set_auto(self.auto_mode)
        if self.auto_mode:
            self._start_auto_switch()
        else:
            self._stop_auto_switch()
        self._update_tooltip()

    def _start_auto_switch(self):
        if self._auto_thread and self._auto_thread.is_alive():
            return
        self._stop_event.clear()
        self._auto_thread = threading.Thread(target=self._auto_loop, daemon=True)
        self._auto_thread.start()

    def _stop_auto_switch(self):
        self._stop_event.set()

    def _auto_loop(self):
        while not self._stop_event.is_set():
            expected = auto_theme_for_hour(datetime.now().hour)
            if expected != self.current_theme:
                self.current_theme = expected
                set_theme(expected)
                GLib.idle_add(self._update_icon)
                GLib.idle_add(self._update_tooltip)
                GLib.idle_add(self._notify)
            for _ in range(10):
                if self._stop_event.is_set():
                    return
                time.sleep(30)

    def _quit(self):
        self._stop_auto_switch()
        Gtk.main_quit()

    def on_signal(self):
        """Called from SIGUSR1 — re-read state and refresh icon."""
        GLib.idle_add(self._refresh)


# ─── entry points ───────────────────────────────────────────────

def run_tray():
    """Start the persistent tray icon."""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))

    # Initialize theme if first run
    if not get_current_theme():
        set_theme(auto_theme_for_hour(datetime.now().hour))

    tray = ThemeTray()
    signal.signal(signal.SIGUSR1, lambda sig, frame: tray.on_signal())

    try:
        Notify.init("theme-tray")
        Gtk.main()
    except KeyboardInterrupt:
        pass
    finally:
        try:
            os.remove(PID_FILE)
        except OSError:
            pass


def run_toggle():
    """One-shot toggle — for i3 keybind."""
    new = toggle_theme()
    # Ping running tray to update its icon
    try:
        with open(PID_FILE) as f:
            os.kill(int(f.read().strip()), signal.SIGUSR1)
    except (FileNotFoundError, ProcessLookupError, ValueError):
        pass
    # Still notify even if tray isn't running
    try:
        Notify.init("theme-tray")
        n = Notify.Notification.new("Theme", f"Switched to {new} mode", "dialog-information")
        n.set_timeout(2000)
        n.show()
    except Exception:
        pass


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--toggle":
        run_toggle()
    else:
        run_tray()
