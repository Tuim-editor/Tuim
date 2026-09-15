#!/usr/bin/env python3
"""Test command shortcut editing and native buffer switching without plugins."""
import argparse
import json
import pathlib
import shlex
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(capture=None):
    with tempfile.TemporaryDirectory(prefix="tuim-workspace-test-") as directory:
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
        def settings():
            return json.loads((base / "data/tuim/settings.json").read_text()).get("keybindings", {})

        def search(query):
            send("F1")
            wait_for(lambda s: "Commands / type to filter" in s, "Commands did not open")
            text(query)
            wait_for(lambda s: query in s, "Command query missing")

        def capture_screen(name):
            if capture:
                capture.mkdir(parents=True, exist_ok=True)
                (capture / (name + ".txt")).write_text(screen())
                (capture / (name + ".ansi")).write_text(tmux("capture-pane", "-p", "-e", "-t", "ui"))

        def command_text(value):
            text(":" + value)
            send("Enter")

        def picker_rows():
            return "\n".join(line[18:82] for line in screen().splitlines()[4:18])

        second = base / "second.zig"
        second.write_text("const second = true;\n")
        try:
            tmux("new-session", "-d", "-s", "ui", "-x", "100", "-y", "30", "-c", str(base), command)
            tmux("set-option", "-t", "ui", "remain-on-exit", "on")
            wait_for(lambda s: ("WORKSPACE" in s or "EXPLORER" in s) and "sample.zig" in s, "Workspace did not render")
            search("close buffer")
            send("F2")
            wait_for(lambda s: "Set shortcut / press a key" in s, "F2 did not start shortcut editing")
            send("C-s")
            wait_for(lambda s: "Shortcut already in use" in s, "Duplicate core shortcut accepted")
            assert settings().get("close_buffer", "") == ""
            send("Escape")
            assert settings().get("close_buffer", "") == "", "Cancel persisted a shortcut"
            send("F2", "C-k")
            wait_for(lambda s: "Shortcut saved" in s and settings().get("close_buffer") == "<C-k>", "Ctrl shortcut not saved")
            capture_screen("shortcut-saved")
            send("F2", "C-l")
            wait_for(lambda s: "Shortcut saved" in s and settings().get("close_buffer") == "<C-l>", "Existing shortcut not replaced")
            send("F2", "C-k", "Escape")

            search("switch buffers")
            send("F2", "F4")
            wait_for(lambda s: "Shortcut saved" in s and settings().get("switch_buffers") == "<F4>", "Function shortcut not saved")
            send("Escape")

            # The shortcut column edits the command; it must not execute it.
            search("settings")
            grid = wait_for(lambda s: "[Set shortcut]" in s, "Unbound shortcut affordance missing")
            row = next(i for i, line in enumerate(grid.splitlines()) if "Settings" in line[18:65] and "[Set shortcut]" in line)
            text(f"\x1b[<0;70;{row + 1}M\x1b[<0;70;{row + 1}m")
            wait_for(lambda s: "Set shortcut / press a key" in s, "Click did not edit shortcut")
            send("M-u")
            wait_for(lambda s: "Shortcut saved" in s and settings().get("settings") == "<M-u>", "Alt shortcut not saved")
            send("Escape", "M-u")
            wait_for(lambda s: "General" in s and "Appearance" in s, "Assigned Alt shortcut did not open settings")
            send("C-s")

            command_text("edit " + str(second))
            wait_for(lambda s: "const second = true;" in s, "Second buffer did not open")
            palette("switch buffers")
            wait_for(lambda s: "Open buffers / type to filter" in s, "Switch buffers command did not open picker")
            capture_screen("open-buffers")
            text("sample")
            send("Enter")
            wait_for(lambda s: "const answer: u32 = 42;" in s and "Open buffers /" not in s, "Filtered buffer did not activate")

            send("i")
            text("// unsaved ")
            send("Escape", "C-k")
            wait_for(lambda s: "Save changes" in s, "Close shortcut did not protect unsaved changes")
            send("c")
            wait_for(lambda s: "Save changes" not in s and "// unsaved" in s, "Cancel did not keep the buffer")
            send("C-s", "C-k")
            send("F4")
            wait_for(lambda s: "Open buffers / type to filter" in s, "Assigned function shortcut did not open picker")
            assert "sample.zig" not in picker_rows(), "Closed buffer remains in picker"
            text("second")
            grid = wait_for(lambda s: "second" in s, "Buffer query missing")
            row = next(i for i, line in enumerate(grid.splitlines()[4:18], 4) if "second.zig" in line[18:82])
            text(f"\x1b[<0;22;{row + 1}M\x1b[<0;22;{row + 1}m")
            wait_for(lambda s: "Open buffers /" not in s and "const second = true;" in s, "Mouse did not activate buffer")

            # Native buffer selection stays available in Zen and small windows.
            send("F11", "F4")
            wait_for(lambda s: "Open buffers / type to filter" in s and "WORKSPACE" not in s, "Zen buffer picker unavailable")
            text("not-a-real-buffer")
            wait_for(lambda s: "No matching buffers" in s, "Empty buffer query missing")
            send("Escape", "Escape", "F11")
            command_text("lua for i=1,18 do vim.cmd('badd buffer-' .. i .. '.zig') end")
            send("F4")
            tmux("resize-window", "-t", "ui", "-x", "40", "-y", "10")
            send(*(["Down"] * 24))
            wait_for(lambda s: "buffer-18.zig" in s, "Short buffer picker did not scroll")
            capture_screen("buffers-compact")
            send("Escape", "Escape")
            tmux("resize-window", "-t", "ui", "-x", "100", "-y", "30")

            # Relaunch the same binary and isolated settings to verify persistence.
            send("C-q")
            deadline = time.monotonic() + 6
            while time.monotonic() < deadline and tmux("display-message", "-p", "-t", "ui", "#{pane_dead}").strip() != "1":
                time.sleep(0.05)
            assert tmux("display-message", "-p", "-t", "ui", "#{pane_dead}").strip() == "1"
            tmux("respawn-pane", "-t", "ui", "-c", str(base), command)
            wait_for(lambda s: ("WORKSPACE" in s or "EXPLORER" in s) and "sample.zig" in s, "Relaunch failed")
            send("F4")
            wait_for(lambda s: "Open buffers / type to filter" in s, "Shortcut did not survive restart")
            send("Escape", "Escape")
            palette("close buffer")
            send("F4")
            wait_for(lambda s: "Open buffers / type to filter" in s, "Picker failed after closing via command menu")
            assert "sample.zig" not in picker_rows(), "Close buffer command did not close current buffer"
            send("Escape", "Escape", "C-q")
        finally:
            subprocess.run(["tmux", "-S", socket, "kill-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("Command UI passed: shortcut editing, conflicts, mouse, persistence, buffer switch/close, unsaved cancel, Zen, compact scrolling")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", type=pathlib.Path)
    run(parser.parse_args().capture)
