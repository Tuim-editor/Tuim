#!/usr/bin/env python3
"""Check first-run mouse dismissal and the native language-tools shortcut."""
import pathlib
import shlex
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="tuim-onboarding-ui-") as directory:
    base = pathlib.Path(directory)
    socket = str(base / "tmux.sock")

    def tmux(*args):
        return subprocess.check_output(["tmux", "-S", socket, *args], text=True)

    def screen():
        return tmux("capture-pane", "-p", "-t", "ui")

    def wait_for(predicate, description):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            grid = screen()
            if predicate(grid):
                return grid
            time.sleep(0.05)
        raise AssertionError(description + "\n" + screen())

    env = {f"XDG_{name}_HOME": str(base / name.lower())
           for name in ("CONFIG", "DATA", "STATE", "CACHE")}
    env.update(TUIM_DISABLE_PLUGINS="1", TUIM_SKIP_ONBOARDING="0", TERM="xterm-256color")
    command = shlex.join(["env", *(f"{k}={v}" for k, v in env.items()),
                          str(ROOT / "zig-out/bin/tuim")])
    try:
        tmux("new-session", "-d", "-s", "ui", "-x", "110", "-y", "36", command)
        grid = wait_for(lambda s: "Click to close guide" in s, "Guide did not open")
        row, line = next((i, line) for i, line in enumerate(grid.splitlines())
                         if "Click to close guide" in line)
        col = line.index("Click to close guide") + 3
        tmux("send-keys", "-l", "-t", "ui", f"\x1b[<0;{col + 1};{row + 1}M\x1b[<0;{col + 1};{row + 1}m")
        wait_for(lambda s: "Click to close guide" not in s, "Click did not close guide")
        assert (base / "data/tuim/onboarding-complete").exists()
        tmux("send-keys", "-l", "-t", "ui", ":TuimOnboarding")
        tmux("send-keys", "-t", "ui", "Enter")
        wait_for(lambda s: "Click to close guide" in s, "Guide did not reopen")
        tmux("send-keys", "-t", "ui", "l")
        wait_for(lambda s: "Mason Package Manager" in s, "Language tools did not open")
        wait_for(lambda s: "Enable Mason in Settings > Plugins" in s,
                 "Missing plugins did not provide recovery instructions")
        tmux("send-keys", "-t", "ui", "Escape")
        wait_for(lambda s: "Mason Package Manager" not in s, "Language tools did not close")
        print("Onboarding click and language-tools UI checks passed")
    finally:
        subprocess.run(["tmux", "-S", socket, "kill-server"], capture_output=True)
