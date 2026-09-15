#!/usr/bin/env python3
"""Check passive hover styling and default Explorer against a real terminal."""
import argparse
import json
import pathlib
import shlex
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(mode="ide"):
    with tempfile.TemporaryDirectory(prefix="tuim-hover-test-") as directory:
        base = pathlib.Path(directory)
        for name in ("config", "data/tuim", "state", "cache"):
            (base / name).mkdir(parents=True, exist_ok=True)
        (base / "data/tuim/settings.json").write_text(json.dumps({"mode": mode, "nerd_fonts": False}))
        (base / "sample.txt").write_text("hover must not edit this file\n")
        (base / ".gitignore").write_text("config/\ndata/\nstate/\ncache/\ntmux.sock\n")
        subprocess.run(["git", "init", "-q", str(base)], check=True)
        (base / "sample.txt").write_text("initial content\n")
        subprocess.run(["git", "-C", str(base), "add", "sample.txt", ".gitignore"], check=True)
        subprocess.run(["git", "-C", str(base), "-c", "user.name=Hover Test", "-c", "user.email=hover@example.invalid", "commit", "-qm", "Test fixture with a very long commit title that must end with an ellipsis"], check=True)
        (base / "sample.txt").write_text("hover must not edit this file\n")
        (base / "z-keyboard.txt").write_text("keyboard-selected file\n")
        socket = str(base / "tmux.sock")

        def tmux(*args):
            return subprocess.check_output(["tmux", "-S", socket, *args], text=True)

        def screen(ansi=False):
            return tmux("capture-pane", "-p", *(["-e"] if ansi else []), "-t", "ui")

        def text(value):
            tmux("send-keys", "-l", "-t", "ui", value)

        def send(key):
            tmux("send-keys", "-t", "ui", key)
            time.sleep(0.12)

        def wait_for(predicate, message):
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                if predicate():
                    return
                time.sleep(0.05)
            raise AssertionError(message + "\n" + screen())

        def locate(label):
            wait_for(lambda: label in screen(), "Missing control: " + label)
            for y, line in enumerate(screen().splitlines()):
                if label in line and (label != "sample.txt" or y > 1):
                    return line.index(label), y

        def hover(label):
            x, y = locate(label)
            text("\x1b[<35;99;29M")
            time.sleep(0.15)
            before = screen(True).splitlines()[y]
            plain = screen().splitlines()[y]
            text(f"\x1b[<35;{x + 1};{y + 1}M")
            wait_for(lambda: screen(True).splitlines()[y] != before, "No hover highlight: " + label)
            assert screen().splitlines()[y] == plain, "Hover changed control state: " + label
            text("\x1b[<35;99;29M")
            wait_for(lambda: screen(True).splitlines()[y] == before, "Hover did not clear: " + label)

        def click(label):
            x, y = locate(label)
            text(f"\x1b[<0;{x + 1};{y + 1}M\x1b[<0;{x + 1};{y + 1}m")
            time.sleep(0.15)

        def command(query):
            send("F1")
            wait_for(lambda: "Commands / type to filter" in screen(), "Command menu did not open")
            text(query)
            send("Enter")

        env = {"XDG_CONFIG_HOME": str(base / "config"), "XDG_DATA_HOME": str(base / "data"),
               "XDG_STATE_HOME": str(base / "state"), "XDG_CACHE_HOME": str(base / "cache"),
               "TUIM_DISABLE_PLUGINS": "1", "TUIM_SKIP_ONBOARDING": "1", "TERM": "xterm-256color"}
        launch = shlex.join(["env", *(f"{k}={v}" for k, v in env.items()), str(ROOT / "zig-out/bin/tuim"), str(base / "sample.txt")])
        try:
            tmux("new-session", "-d", "-s", "ui", "-x", "100", "-y", "30", "-c", str(base), launch)
            wait_for(lambda: "EXPLORER" in screen(), "Explorer is not the startup view")
            hover("+F")
            hover("+D")
            hover("sample.txt")
            hover("< Workspace")
            command("git")
            hover("[ More ]")
            hover("Message")
            hover("Changes")
            hover("sample.txt")
            # Hovering the stage control must leave the Git index untouched.
            hover("+")
            staged = subprocess.check_output(["git", "-C", str(base), "diff", "--cached", "--name-only"], text=True)
            assert staged == "", "Passive motion staged a file"
            commit_row = next(line for line in screen().splitlines() if "Test" in line)
            assert commit_row.split("│")[0].rstrip().endswith("..."), commit_row
            click("+")
            wait_for(lambda: subprocess.check_output(["git", "-C", str(base), "diff", "--cached", "--name-only"], text=True).strip() == "sample.txt", "Stage button did not add the file")
            wait_for(lambda: "Staged Changes" in screen(), "Staging did not refresh the panel")
            # Choose the action on the file row, not a dash inside a commit title.
            x, y = locate("sample.txt")
            row = screen().splitlines()[y].split("│")[0]
            minus = row.rindex("-")
            text(f"\x1b[<0;{minus + 1};{y + 1}M\x1b[<0;{minus + 1};{y + 1}m")
            wait_for(lambda: subprocess.check_output(["git", "-C", str(base), "diff", "--cached", "--name-only"], text=True).strip() == "", "Unstage button did not remove the file from the index")
            # Navigate and operate on the second change without mouse input.
            command("git")
            send("Home")
            wait_for(lambda: any(line.startswith("> sample.txt") for line in screen().splitlines()), "First Git change has no visible keyboard selection")
            send("Down")
            wait_for(lambda: any(line.startswith("> z-key") for line in screen().splitlines()), "Git selection marker did not move down")
            assert not any(line.startswith("> sample.txt") for line in screen().splitlines()), "Previous selection marker was not cleared"
            send("Up")
            wait_for(lambda: any(line.startswith("> sample.txt") for line in screen().splitlines()), "Git selection marker did not move up")
            send("Down")
            send("Space")
            wait_for(lambda: subprocess.check_output(["git", "-C", str(base), "diff", "--cached", "--name-only"], text=True).strip() == "z-keyboard.txt", "Keyboard selection/staging targeted the wrong file")
            send("u")
            wait_for(lambda: subprocess.check_output(["git", "-C", str(base), "diff", "--cached", "--name-only"], text=True).strip() == "", "Keyboard unstaging failed after list reorder")
            send("Enter")
            wait_for(lambda: "keyboard-selected file" in screen() and "Editor" in screen().splitlines()[-1], "Enter did not open the selected Git change")
            command("git")
            send("c")
            text("draft commit message")
            send("Escape")
            wait_for(lambda: "SOURCE CONTRO" in screen(), "Escape in the commit box left the Git panel")
            send("Home")
            send("Enter")
            wait_for(lambda: "hover must not edit this file" in screen(), "Could not reopen the first change")
            command("git")
            click("[ More ]")
            hover("Branches")
            send("Escape")
            command("ai assistants")
            hover("Open chat")
            command("extensions")
            hover("1 Installed")
            hover("2 Discover")
            command("settings")
            hover("Save Ctrl+S")
            hover("System Clipboard")
            hover("Appearance")
            click("Appearance")
            hover("Theme:")
            click("Theme:")
            hover("System")
            send("Escape")
            click("Plugins")
            hover("Mason Settings")
            hover("Plugin Manager...")
            click("Mason Settings")
            hover(" DAP ")
            hover("Install & Close")
            send("Escape")
            command("settings")
            click("Plugins")
            click("Plugin Manager...")
            hover(" Loaded ")
            send("Escape")
            command("report bug")
            hover("Send")
            hover("What went wrong?")
            send("Escape")
            assert (base / "sample.txt").read_text() == "hover must not edit this file\n"
            send("C-q")
        finally:
            subprocess.run(["tmux", "-S", socket, "kill-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("Hover UI passed: Explorer startup, controls, lists, Git, AI, extensions, settings, and clearing on exit")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("normal", "ide"), default="ide")
    run(parser.parse_args().mode)
