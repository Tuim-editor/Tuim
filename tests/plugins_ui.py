#!/usr/bin/env python3
"""Exercise installed-plugin controls through Tuim's real terminal UI."""
import json
import pathlib
import shlex
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run():
    with tempfile.TemporaryDirectory(prefix="tuim-plugin-ui-") as directory:
        base = pathlib.Path(directory)
        data = base / "data/tuim"
        (data / "lazy/alpha-demo").mkdir(parents=True)
        (data / "settings.json").write_text('{"mode":"normal","nerd_fonts":false}')
        (data / "store_db.json").write_text(json.dumps({"items": [
            {"name": "demo-theme", "full_name": "example/demo-theme", "description": "A colorful editor theme", "tags": ["colorscheme"], "stars": {"curr": 120}},
            {"name": "demo-git", "full_name": "example/demo-git", "description": "Git tools for your workspace", "tags": ["git"], "stars": {"curr": 90}}]}))
        (data / "user_plugins.json").write_text('["example/alpha-demo"]')
        (base / "sample.txt").write_text("Plugin manager fixture\n")
        socket = str(base / "tmux.sock")

        def tmux(*args):
            return subprocess.check_output(["tmux", "-S", socket, *args], text=True)

        def screen():
            return tmux("capture-pane", "-p", "-t", "ui")

        def wait(label):
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                grid = screen()
                if label in grid:
                    return grid
                time.sleep(.05)
            raise AssertionError("Missing " + label + "\n" + screen())

        def send(key):
            tmux("send-keys", "-t", "ui", key)
            time.sleep(.15)

        def text(value):
            tmux("send-keys", "-l", "-t", "ui", value)

        def click(label):
            for y, row in enumerate(wait(label).splitlines()):
                if label in row and (label != "Plugins" or 17 <= row.index(label) < 35):
                    x = row.index(label)
                    text(f"\x1b[<0;{x+1};{y+1}M\x1b[<0;{x+1};{y+1}m")
                    time.sleep(.15)
                    return

        def command(query):
            send("F1")
            wait("Commands / type to filter")
            text(query)
            send("Enter")

        def states():
            return json.loads((data / "plugin_states.json").read_text())

        env = {"XDG_DATA_HOME": str(base / "data"), "XDG_CONFIG_HOME": str(base / "config"),
               "XDG_STATE_HOME": str(base / "state"), "XDG_CACHE_HOME": str(base / "cache"),
               "TUIM_DISABLE_PLUGINS": "1", "TUIM_SKIP_ONBOARDING": "1", "TERM": "xterm-256color"}
        launch = shlex.join(["env", *(f"{k}={v}" for k, v in env.items()), str(ROOT / "zig-out/bin/tuim"), str(base / "sample.txt")])
        try:
            tmux("new-session", "-d", "-s", "ui", "-x", "110", "-y", "36", "-c", str(base), launch)
            tmux("set-option", "-t", "ui", "remain-on-exit", "on")
            wait("EXPLORER")
            command("extensions")
            wait("Your plugins")
            wait("alpha-demo")
            send("Enter")
            wait("Configure plugin")
            send("e")
            wait("lazy.nvim spec override")
            config = data / "plugin_configs/example_alpha-demo.lua"
            assert config.exists()
            original = config.read_text()
            command("extensions")
            send("Enter")
            send("d")
            prompt = wait("Restart Tuim?")
            assert "Plugin changes saved." in prompt
            assert "[Y] Restart" in prompt and "[N] Later" in prompt
            prompt_rows = prompt.splitlines()
            assert next(i for i, row in enumerate(prompt_rows) if "Restart Tuim?" in row) < len(prompt_rows) - 4
            assert states()["example/alpha-demo"] == "disabled"
            tmux("resize-window", "-t", "ui", "-x", "60", "-y", "20")
            time.sleep(.3)
            prompt = wait("Restart Tuim?")
            assert "[Y] Restart" in prompt and "[N] Later" in prompt
            assert prompt.count("Restart Tuim?") == 1, prompt
            pathlib.Path("/tmp/tuim-plugin-confirmation.txt").write_text(prompt)
            click("[N] Later")
            wait("Disabled")
            tmux("resize-window", "-t", "ui", "-x", "110", "-y", "36")
            send("Enter")
            click("D  Enable plugin")
            wait("Restart Tuim?")
            assert states()["example/alpha-demo"] == "enabled"
            send("Escape")
            send("Enter")
            click("U  Uninstall plugin")
            prompt = wait("Uninstall?")
            assert "Configuration will be kept." in prompt, prompt
            assert "[Y] Remove" in prompt and "[N] Cancel" in prompt, prompt
            assert next(i for i, row in enumerate(prompt.splitlines()) if "Uninstall?" in row) < len(prompt.splitlines()) - 4
            tmux("resize-window", "-t", "ui", "-x", "60", "-y", "20")
            time.sleep(.3)
            prompt = wait("Uninstall?")
            assert "[Y] Remove" in prompt and "[N] Cancel" in prompt, prompt
            pathlib.Path("/tmp/tuim-plugin-uninstall.txt").write_text(prompt)
            tmux("resize-window", "-t", "ui", "-x", "40", "-y", "20")
            time.sleep(.3)
            wait("Enlarge to confirm")
            send("y")
            assert states()["example/alpha-demo"] == "enabled"
            tmux("resize-window", "-t", "ui", "-x", "60", "-y", "20")
            time.sleep(.3)
            click("[N] Cancel")
            assert "Uninstall?" not in screen()
            tmux("resize-window", "-t", "ui", "-x", "110", "-y", "36")
            time.sleep(.3)
            assert states()["example/alpha-demo"] == "enabled"
            send("u")
            wait("Uninstall?")
            send("Escape")
            assert states()["example/alpha-demo"] == "enabled"
            send("u")
            wait("Uninstall?")
            click("[Y] Remove")
            wait("Restart Tuim?")
            assert states()["example/alpha-demo"] == "removed"
            assert config.read_text() == original
            send("Escape")
            wait("Removal pending restart")
            wait("Enter  Install plugin")
            send("Enter")
            wait("Restart Tuim?")
            assert states()["example/alpha-demo"] == "enabled"
            send("Escape")
            send("Escape")
            command("settings")
            click("Plugins")
            click("Installed Plugins...")
            wait("alpha-demo")
            click("2 Discover")
            wait("demo-theme")
            click("Git Integrations")
            wait("demo-git")
            assert "demo-theme" not in screen()
            send("1")
            wait("alpha-demo")
            send("/")
            text("no-such-plugin")
            send("Enter")
            wait("No matching plugins")
            send("1")
            wait("alpha-demo")
            tmux("resize-window", "-t", "ui", "-x", "70", "-y", "26")
            send("Enter")
            wait("Configure plugin")
            send("Escape")
            tmux("resize-window", "-t", "ui", "-x", "35", "-y", "10")
            send("Down")
            send("Escape")
            tmux("resize-window", "-t", "ui", "-x", "110", "-y", "36")
            send("C-q")
        finally:
            subprocess.run(["tmux", "-S", socket, "kill-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("Installed plugins UI passed: keyboard, mouse, config, disable/enable, uninstall confirmation, reinstall, Settings, resize")


if __name__ == "__main__":
    run()
