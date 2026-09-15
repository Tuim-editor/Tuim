#!/usr/bin/env python3
"""Verify System theme selection and live palette updates in the terminal UI."""
import argparse
import json
import pathlib
import shlex
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(capture=None):
    with tempfile.TemporaryDirectory(prefix="tuim-system-ui-") as directory:
        base = pathlib.Path(directory)
        for name in ("config", "data/tuim", "state", "cache"):
            (base / name).mkdir(parents=True, exist_ok=True)
        (base / "data/tuim/settings.json").write_text('{"mode":"normal","nerd_fonts":false}')
        sample = base / "sample.zig"
        sample.write_text('const answer: u32 = 42;\n')
        socket = str(base / "tmux.sock")

        def tmux(*args):
            return subprocess.check_output(["tmux", "-S", socket, *args], text=True)

        def screen():
            return tmux("capture-pane", "-p", "-t", "ui")

        def wait_for(predicate, description, timeout=6):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                grid = screen()
                if predicate(grid):
                    return grid
                time.sleep(0.05)
            raise AssertionError(description + "\n" + screen())

        def send(*keys):
            for key in keys:
                tmux("send-keys", "-t", "ui", key)
                # A standalone Escape must finish the terminal's Alt-key
                # disambiguation window before the following keystroke.
                time.sleep(0.08)

        def text(value):
            tmux("send-keys", "-l", "-t", "ui", value)

        def palette(query):
            send("F1")
            wait_for(lambda s: "Commands / type to filter" in s, "Palette did not open")
            text(query)
            send("Enter")

        env = {
            "XDG_CONFIG_HOME": str(base / "config"),
            "XDG_DATA_HOME": str(base / "data"),
            "XDG_STATE_HOME": str(base / "state"),
            "XDG_CACHE_HOME": str(base / "cache"),
            "TUIM_DISABLE_PLUGINS": "1",
            "TUIM_SKIP_ONBOARDING": "1",
            "TERM": "xterm-256color",
        }
        command = shlex.join(["env", *(f"{k}={v}" for k, v in env.items()), str(ROOT / "zig-out/bin/tuim"), str(sample)])
        theme_dir = base / "state/omarchy/current/theme"
        theme_dir.mkdir(parents=True)
        colors = theme_dir / "colors.toml"
        colors.write_text('background = "#05182e"\nforeground = "#f6dcac"\naccent = "#faa968"\ndark_background = "#031222"\n')

        def ansi():
            return tmux("capture-pane", "-p", "-e", "-t", "ui")

        def save_capture(name):
            if capture:
                capture.mkdir(parents=True, exist_ok=True)
                (capture / (name + ".txt")).write_text(screen())
                (capture / (name + ".ansi")).write_text(ansi())

        def choose_system():
            palette("settings")
            wait_for(lambda s: "Appearance" in s and "General Settings" in s, "Settings did not open")
            send("Down", "Right", "Enter")
            # Home is not portable across terminal encodings; arrows are.
            send(*(["Up"] * 30))
            wait_for(lambda s: "System (follow desktop)" in s, "System absent from refreshed theme list")
            save_capture("system-option")
            row, line = next((i, line) for i, line in enumerate(screen().splitlines()) if "System (follow desktop)" in line)
            column = line.index("System (follow desktop)") + len("System (follow desktop)") - 1
            text(f"\x1b[<0;{column + 1};{row + 1}M\x1b[<0;{column + 1};{row + 1}m")
            send("C-s")
            wait_for(lambda _: json.loads((base / "data/tuim/settings.json").read_text()).get("theme") == "system", "System selection was not saved")
            wait_for(lambda _: "48;2;5;24;46m" in ansi(), "Editor did not use system background")
            assert "48;2;3;18;34m" not in ansi(), "Sidebar did not blend into the editor background"
            save_capture("system-dark")

        try:
            tmux("new-session", "-d", "-s", "ui", "-x", "100", "-y", "30", "-c", str(base), command)
            tmux("set-option", "-t", "ui", "remain-on-exit", "on")
            wait_for(lambda s: ("WORKSPACE" in s or "EXPLORER" in s) and "sample.zig" in s, "Workspace did not render")
            choose_system()
            colors.write_text('mode = "light"\nbackground = "#f8f4ee"\nforeground = "#242424"\naccent = "#805020"\ndark_background = "#eee4d8"\n')
            wait_for(lambda _: "48;2;248;244;238m" in ansi() and "48;2;5;24;46m" not in ansi(), "Desktop change did not update editor and sidebar")
            save_capture("system-light")
            send("C-q")
            deadline = time.monotonic() + 6
            while time.monotonic() < deadline and tmux("display-message", "-p", "-t", "ui", "#{pane_dead}").strip() != "1":
                time.sleep(0.05)
            assert tmux("display-message", "-p", "-t", "ui", "#{pane_dead}").strip() == "1"
            tmux("respawn-pane", "-t", "ui", "-c", str(base), command)
            wait_for(lambda s: ("WORKSPACE" in s or "EXPLORER" in s) and "48;2;248;244;238m" in ansi(), "System theme did not survive restart")
            send("C-q")
        finally:
            save_capture("last-screen")
            subprocess.run(["tmux", "-S", socket, "kill-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("System theme UI passed: selection, persistence, exact editor/sidebar colors, dark-to-light live update, restart")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", type=pathlib.Path)
    run(parser.parse_args().capture)
