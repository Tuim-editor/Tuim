#!/usr/bin/env python3
"""Exercise Ctrl+Q against a real Tuim/Neovim session in tmux."""

import json
import pathlib
import shlex
import subprocess
import tempfile
import time


ROOT = pathlib.Path(__file__).resolve().parents[1]


def run_mode(mode):
    with tempfile.TemporaryDirectory(prefix=f"tuim-quit-{mode}-") as directory:
        base = pathlib.Path(directory)
        for name in ("config", "data/tuim", "state", "cache"):
            (base / name).mkdir(parents=True, exist_ok=True)
        (base / "data/tuim/settings.json").write_text(json.dumps({"mode": mode, "nerd_fonts": False}))
        sample = base / "existing.txt"
        sample.write_text("original\n")
        socket = str(base / "tmux.sock")

        def tmux(*args):
            return subprocess.check_output(["tmux", "-S", socket, *args], text=True)

        def screen():
            return tmux("capture-pane", "-p", "-t", "ui")

        def wait_for(predicate, description, timeout=8):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if predicate():
                    return
                time.sleep(0.05)
            raise AssertionError(f"{mode}: {description}\n{screen()}")

        def dead():
            return tmux("display-message", "-p", "-t", "ui", "#{pane_dead}").strip() == "1"

        def send(*keys):
            for key in keys:
                tmux("send-keys", "-t", "ui", key)
                time.sleep(0.08)

        def text(value):
            tmux("send-keys", "-l", "-t", "ui", value)

        def insert(value):
            if mode == "normal":
                send("i")
            text(value)
            if mode == "normal":
                send("Escape")

        env = {
            "XDG_CONFIG_HOME": str(base / "config"),
            "XDG_DATA_HOME": str(base / "data"),
            "XDG_STATE_HOME": str(base / "state"),
            "XDG_CACHE_HOME": str(base / "cache"),
            "TUIM_DISABLE_PLUGINS": "1",
            "TUIM_SKIP_ONBOARDING": "1",
            "TERM": "xterm-256color",
        }
        def launch(file=sample):
            command = shlex.join(["env", *(f"{k}={v}" for k, v in env.items()), str(ROOT / "zig-out/bin/tuim"), str(file)])
            if (base / "tmux.sock").exists():
                tmux("respawn-pane", "-t", "ui", "-c", str(base), command)
            else:
                tmux("new-session", "-d", "-s", "ui", "-x", "100", "-y", "30", "-c", str(base), command)
                tmux("set-option", "-t", "ui", "remain-on-exit", "on")
            wait_for(lambda: file.name in screen(), "editor did not open")

        def open_file(file):
            if mode == "ide":
                send("C-o")  # One Normal command while IDE mode is in Insert.
            text(":edit " + str(file))
            send("Enter")
            wait_for(lambda: file.name in screen().splitlines()[0], f"{file.name} did not open")

        try:
            launch()
            insert("changed ")
            send("C-q")
            wait_for(lambda: "Save changes" in screen(), "dirty quit did not prompt")
            send("c")
            wait_for(lambda: "Save changes" not in screen() and "changed" in screen(), "Cancel lost the editor or edits")
            assert not dead()
            assert sample.read_text() == "original\n"

            send("C-q")
            wait_for(lambda: "Save changes" in screen(), "second quit did not prompt")
            send("y")
            wait_for(dead, "Save did not exit")
            assert "changed " in sample.read_text(), f"Save did not write the edited file: {sample.read_text()!r}"

            launch()
            insert("discarded ")
            send("C-q")
            wait_for(lambda: "Save changes" in screen(), "discard scenario did not prompt")
            send("n")
            wait_for(dead, "Discard did not exit")
            assert "discarded " not in sample.read_text(), "Discard wrote unwanted edits"

            launch()
            send("C-q")
            wait_for(dead, "clean quit did not exit")

            launch()
            insert("named edit ")
            send("C-n")
            wait_for(lambda: "[No Name]" in screen(), "new buffer did not open")
            insert("new buffer edit")
            send("C-q")
            wait_for(lambda: "Save changes" in screen(), "mixed named and unnamed buffers did not prompt")
            send("c")
            wait_for(lambda: "Save changes" not in screen() and "new buffer edit" in screen(), "mixed-buffer Cancel lost edits")
            assert not dead()
            assert "named edit " not in sample.read_text()

            # Neovim gives a new buffer the default name "Untitled" when
            # Save is chosen. Verify it writes both buffers before quitting.
            new_file = base / "Untitled"
            send("C-q")
            wait_for(lambda: 'Save changes to "Untitled"?' in screen(), "new buffer save prompt missing")
            send("y")
            wait_for(lambda: f'Save changes to "{sample}"?' in screen(), "existing file save prompt missing")
            send("y")
            wait_for(dead, "Save for mixed buffers did not exit")
            assert "named edit " in sample.read_text(), "named buffer was not saved"
            assert new_file.exists(), "new buffer was not saved"
            assert "new buffer edit" in new_file.read_text(), f"new buffer content was wrong: {new_file.read_text()!r}"

            # Cancel after saving one of two named buffers must leave the
            # other modified and allow the user to retry quitting.
            second = base / "second.txt"
            second.write_text("second original\n")
            launch()
            insert("first named edit ")
            open_file(second)
            insert("second named edit ")
            send("C-q")
            wait_for(lambda: f'Save changes to "{second}"?' in screen(), "current named buffer did not prompt first")
            send("y")
            wait_for(lambda: f'Save changes to "{sample}"?' in screen(), "earlier named buffer did not prompt second")
            send("c")
            wait_for(lambda: "Save changes" not in screen(), "Cancel after a partial save did not return to Tuim")
            assert not dead()
            assert "first named edit " not in sample.read_text(), "Cancel wrote the unsaved first buffer"
            assert "second named edit " in second.read_text(), "Save did not write the second buffer"
            send("C-q")
            wait_for(lambda: f'Save changes to "{sample}"?' in screen(), "remaining modified buffer did not prompt")
            send("y")
            wait_for(dead, "saving the remaining named buffer did not exit")
            assert "first named edit " in sample.read_text()

            # Ctrl+Q must route to the editor even when another region has
            # focus. Exercise Cancel and Save from the sidebar.
            launch()
            insert("sidebar pending ")
            send("F6", "C-q")
            wait_for(lambda: "Save changes" in screen(), "sidebar-focused quit did not prompt")
            send("c")
            wait_for(lambda: "Save changes" not in screen(), "sidebar Cancel did not return to Tuim")
            assert not dead() and "sidebar pending " not in sample.read_text()
            send("F6", "C-q")
            wait_for(lambda: "Save changes" in screen(), "sidebar-focused Save did not prompt")
            send("y")
            wait_for(dead, "sidebar-focused Save did not exit")
            assert "sidebar pending " in sample.read_text()

            # The terminal panel uses a separate Neovim instance; its focus
            # must be reset so the editor receives the confirmation response.
            launch()
            insert("terminal pending ")
            send("C-t", "C-q")
            wait_for(lambda: "Save changes" in screen(), "terminal-focused quit did not prompt")
            send("c")
            wait_for(lambda: "Save changes" not in screen(), "terminal Cancel did not return to Tuim")
            assert not dead() and "terminal pending " not in sample.read_text()
            send("C-t", "C-t", "C-q")
            wait_for(lambda: "Save changes" in screen(), "terminal-focused Discard did not prompt")
            send("n")
            wait_for(dead, "terminal-focused Discard did not exit")
            assert "terminal pending " not in sample.read_text()

            # A failed write must leave Tuim alive with the edit intact.
            missing = base / "missing-directory" / "unwritable.txt"
            launch(missing)
            insert("keep this edit")
            send("C-q")
            wait_for(lambda: "Save changes" in screen(), "unwritable file did not prompt")
            failed_prompt = screen()
            send("y")
            wait_for(
                lambda: dead()
                or "Press ENTER or type command to continue" in screen()
                or ("Save changes" not in screen() and "keep this edit" in screen()),
                "write failure did not resolve",
            )
            assert not dead(), f"failed write exited Tuim; file_exists={missing.exists()} prompt={failed_prompt!r}"
            assert not missing.exists()
            if "Press ENTER or type command to continue" in screen():
                send("Enter")
            wait_for(lambda: "Save changes" not in screen() and "keep this edit" in screen(), "failed write lost the buffer")
            send("C-q")
            wait_for(lambda: "Save changes" in screen(), "failed write did not leave the buffer modified")
            send("c")
            assert not dead() and not missing.exists()
        finally:
            subprocess.run(["tmux", "-S", socket, "kill-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    for editor_mode in ("normal", "ide"):
        run_mode(editor_mode)
    print("Quit UI passed: clean, Cancel, Save, Discard, multiple buffers, and failed writes in Normal and IDE modes")
