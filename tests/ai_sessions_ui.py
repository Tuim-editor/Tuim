#!/usr/bin/env python3
"""Verify agent workspace input, session switching, and compact rendering."""
import os
import pathlib
import shlex
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="tuim-ai-ui-") as directory:
    base = pathlib.Path(directory)
    for name in ("config", "data/tuim", "state", "cache", "bin"):
        (base / name).mkdir(parents=True)
    (base / "data/tuim/settings.json").write_text('{"mode":"normal","nerd_fonts":false}')
    sample = base / "sample.py"
    sample.write_text('print("hello")\n')
    for name in ("codex", "claude"):
        command = base / "bin" / name
        command.write_text("#!/bin/sh\nexec cat\n")
        command.chmod(0o755)
    socket = str(base / "tmux.sock")

    def tmux(*args):
        return subprocess.check_output(["tmux", "-S", socket, *args], text=True)

    def screen():
        return tmux("capture-pane", "-p", "-t", "ui")

    def wait_for(text):
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            grid = screen()
            if text in grid:
                return grid
            time.sleep(0.05)
        raise AssertionError(text + " missing:\n" + screen())

    def click(label):
        grid = wait_for(label)
        row, line = next((row, line) for row, line in enumerate(grid.splitlines()) if label in line)
        col = line.index(label)
        tmux("send-keys", "-l", "-t", "ui", f"\x1b[<0;{col + 1};{row + 1}M\x1b[<0;{col + 1};{row + 1}m")
        time.sleep(0.1)

    env = {
        **{f"XDG_{name.upper()}_HOME": str(base / name) for name in ("config", "data", "state", "cache")},
        # Keep availability deterministic: only the fixture CLIs should be
        # discoverable, even when the host has other assistant commands.
        "PATH": str(base / "bin") + os.pathsep + "/usr/bin:/bin",
        "TUIM_DISABLE_PLUGINS": "1", "TUIM_SKIP_ONBOARDING": "1", "TERM": "xterm-256color", "SHELL": "/bin/sh",
    }
    command = shlex.join(["env", *(f"{k}={v}" for k, v in env.items()), str(ROOT / "zig-out/bin/tuim"), str(sample)])
    try:
        tmux("new-session", "-d", "-s", "ui", "-x", "120", "-y", "36", "-c", str(base), command)
        wait_for('sample.py')
        time.sleep(0.3)
        click("< Workspace")
        click("AI assistants")
        wait_for("AI CHAT")
        assert 'Context' not in screen() and 'Actions' not in screen()

        # The chooser owns Escape and all printable/navigation keys while the
        # sidebar is focused.  Cancelling must leave the chooser closed and
        # must not edit the source buffer behind it.
        click("Codex v")
        chooser = wait_for("CHOOSE AGENT")
        assert "Choose an assistant" in chooser, chooser
        assert "Enter pick  Esc back" in chooser, chooser
        tmux("send-keys", "-t", "ui", "Escape")
        wait_for("AI CHAT")
        assert "CHOOSE AGENT" not in screen()
        before = sample.read_text()
        tmux("send-keys", "-l", "-t", "ui", "sidebar-input")
        time.sleep(0.1)
        assert sample.read_text() == before, "Sidebar key leaked into the editor"
        assert "sidebar-input" not in screen(), "Sidebar key edited the visible editor buffer"

        click("Open chat")
        wait_for("Return to chat")
        click("Codex v")
        wait_for("CHOOSE AGENT")
        # Keyboard selection must activate the highlighted assistant.  Codex
        # is initially selected, so one Up selects Claude Code.
        tmux("send-keys", "-t", "ui", "Up")
        tmux("send-keys", "-t", "ui", "Enter")
        wait_for("Open chat")
        assert "Send file" not in screen(), "Actions target the previous agent"
        click("Open chat")
        wait_for("Return to chat")
        # Tab navigation followed by Enter activates the next assistant.
        click("Claude Code v")
        tmux("send-keys", "-t", "ui", "Tab")
        tmux("send-keys", "-t", "ui", "Enter")
        wait_for("Open chat")
        click("Open chat")
        wait_for("Return to chat")
        # Picking an unavailable assistant exposes a single recovery action;
        # that action must reopen the chooser rather than trying to launch it.
        click("Codex v")
        click("Antigravity")
        wait_for("Choose assistant")
        assert "Open chat" not in screen()
        click("Choose assistant")
        wait_for("CHOOSE AGENT")
        tmux("send-keys", "-t", "ui", "Escape")
        wait_for("Choose assistant")
        click("Antigravity v")
        click("Codex")
        click("Return to chat")
        grid = wait_for("Chat open")
        pathlib.Path('/tmp/tuim-ai-expanded.txt').write_text(grid)
        wait_for("Send selection")
        wait_for("Send file")
        wait_for("Review changes")
        tmux("resize-window", "-t", "ui", "-x", "65", "-y", "20")
        wait_for("AI CHAT")
        click("Stop chat")
        grid = wait_for("Chat stopped")
        pathlib.Path('/tmp/tuim-ai-compact.txt').write_text(grid)
        assert "Send selection" not in grid, grid
        assert "Send file" not in grid, grid
        assert "Review changes" not in grid, grid
        assert "Restart chat" in grid, grid
        click("Restart chat")
        wait_for("Chat open")
        tmux("send-keys", "-t", "ui", "F1")
        wait_for("Commands / type to filter")
        tmux("send-keys", "-l", "-t", "ui", "Open terminal right")
        wait_for("Open terminal right")
        tmux("send-keys", "-t", "ui", "Enter")
        time.sleep(0.4)
        marker = base / 'right-terminal'
        tmux("send-keys", "-l", "-t", "ui", "printf terminal-ok > " + shlex.quote(str(marker)))
        tmux("send-keys", "-t", "ui", "Enter")
        deadline = time.monotonic() + 5
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        assert marker.read_text() == 'terminal-ok', screen()
        tmux("send-keys", "-t", "ui", "F1")
        wait_for("Commands / type to filter")
        tmux("send-keys", "-l", "-t", "ui", "Close buffer")
        tmux("send-keys", "-t", "ui", "Enter")
        time.sleep(0.3)
        grid = screen()
        assert 'E89:' not in grid and 'Press ENTER' not in grid, grid
        tmux("send-keys", "-t", "ui", "F1")
        wait_for("Commands / type to filter")
        tmux("send-keys", "-t", "ui", "Escape")
        time.sleep(0.1)
        tmux("send-keys", "-t", "ui", "C-t")
        wait_for("[Terminal]")
        time.sleep(0.3)
        tmux("send-keys", "-l", "-t", "ui", "exit")
        tmux("send-keys", "-t", "ui", "Enter")
        time.sleep(0.3)
        tmux("send-keys", "-t", "ui", "C-t")
        time.sleep(0.1)
        tmux("send-keys", "-t", "ui", "C-t")
        time.sleep(0.3)
        marker = base / 'bottom-reopened'
        tmux("send-keys", "-l", "-t", "ui", "printf reopened > " + shlex.quote(str(marker)))
        tmux("send-keys", "-t", "ui", "Enter")
        deadline = time.monotonic() + 5
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        assert marker.read_text() == 'reopened', screen()
        tmux("send-keys", "-t", "ui", "C-q")
    finally:
        subprocess.run(["tmux", "-S", socket, "kill-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print("AI/terminal UI passed: chat actions, right terminal close, bottom terminal exit and reopen with working shell input")
