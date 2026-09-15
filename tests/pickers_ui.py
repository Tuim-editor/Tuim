#!/usr/bin/env python3
"""Test real Telescope windows in an isolated Tuim terminal session.

Uses installed Telescope/plenary sources, without lazy bootstrap or downloads.
"""
import argparse
import pathlib
import shlex
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(plugin_root, capture):
    for plugin in ("telescope.nvim", "plenary.nvim"):
        if not (plugin_root / plugin / "lua").is_dir():
            raise SystemExit(f"Missing local dependency: {plugin_root / plugin}")
    with tempfile.TemporaryDirectory(prefix="tuim-picker-test-") as directory:
        base = pathlib.Path(directory)
        for name in ("config", "data/tuim", "state", "cache", "project"):
            (base / name).mkdir(parents=True, exist_ok=True)
        (base / "data/tuim/settings.json").write_text('{"mode":"normal","nerd_fonts":false}')
        project = base / "project"
        (project / "alpha.lua").write_text('-- alpha preview\nlocal answer = 42\nreturn answer\n')
        (project / "beta.lua").write_text('-- beta preview\nreturn "hello"\n')
        setup = base / "setup.lua"
        setup.write_text("\n".join([
            f"vim.opt.rtp:prepend({str(plugin_root / plugin)!r})"
            for plugin in ("plenary.nvim", "telescope.nvim")
        ]) + "\nvim.cmd('runtime plugin/telescope.lua')\nlocal ok, err = pcall(_G.tuim_configure_pickers)\n"
            + f"vim.fn.writefile({{tostring(ok), tostring(err)}}, {str(base / 'setup-result')!r})\n")
        socket = str(base / "tmux.sock")

        def tmux(*args):
            return subprocess.check_output(["tmux", "-S", socket, *args], text=True)

        def screen():
            return tmux("capture-pane", "-p", "-t", "ui")

        def wait_for(predicate, description, timeout=8):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                grid = screen()
                if predicate(grid):
                    return grid
                time.sleep(0.05)
            raise AssertionError(description + "\n" + tmux("capture-pane", "-p", "-S", "-200", "-t", "ui"))

        def send(*keys):
            for key in keys:
                tmux("send-keys", "-t", "ui", key)
                time.sleep(0.1)

        def text(value):
            tmux("send-keys", "-l", "-t", "ui", value)

        def command(value):
            text(":" + value)
            send("Enter")

        def picker(name, title):
            command(f"lua require('telescope.builtin').{name}()")
            return wait_for(lambda s: title in s and "Esc Close" in s, title + " did not open")

        def close():
            send("Escape")
            wait_for(lambda s: "Esc Close" not in s, "Escape did not close picker in one press")

        def save_capture(name):
            if capture:
                capture.mkdir(parents=True, exist_ok=True)
                (capture / (name + ".txt")).write_text(screen())
                (capture / (name + ".ansi")).write_text(tmux("capture-pane", "-p", "-e", "-t", "ui"))

        env = {
            "XDG_CONFIG_HOME": str(base / "config"), "XDG_DATA_HOME": str(base / "data"),
            "XDG_STATE_HOME": str(base / "state"), "XDG_CACHE_HOME": str(base / "cache"),
            "TUIM_DISABLE_PLUGINS": "1", "TUIM_SKIP_ONBOARDING": "1", "TERM": "xterm-256color",
        }
        launch = shlex.join(["env", *(f"{k}={v}" for k, v in env.items()), str(ROOT / "zig-out/bin/tuim"), str(project / "alpha.lua")])
        try:
            tmux("new-session", "-d", "-s", "ui", "-x", "160", "-y", "38", "-c", str(project), launch)
            tmux("set-option", "-t", "ui", "remain-on-exit", "on")
            wait_for(lambda s: ("WORKSPACE" in s or "EXPLORER" in s) and "alpha.lua" in s, "Tuim did not start")
            time.sleep(0.3)
            wait_for(lambda s: "Plugins are disabled" not in s, "Startup notice did not clear", timeout=12)
            command("luafile " + str(setup))
            wait_for(lambda _: (base / "setup-result").exists(), "Picker setup did not execute")
            assert (base / "setup-result").read_text().startswith("true"), (base / "setup-result").read_text()
            send("C-p")
            wide = wait_for(lambda s: "Find files" in s and "Esc Close" in s and "beta.lua" in s and s.count("alpha preview") == 2, "Wide file picker missing results or preview")
            assert "Telescope" not in wide, "Legacy frame still visible"
            # Explorer also lists beta.lua; compare rows inside the picker.
            wide_rows = wide.splitlines()
            title_row = next(i for i, line in enumerate(wide_rows) if "Find files" in line)
            picker_left = wide_rows[title_row].index("╭")
            result_rows = [i for i, line in enumerate(wide_rows) if "beta.lua" in line[picker_left:]]
            assert result_rows and min(result_rows) > title_row, "Search title is below picker results\n" + wide
            save_capture("find-files-normal")
            send("C-n")
            wait_for(lambda s: "beta preview" in s and "Esc Close" in s, "Ctrl-N did not move selection inside picker")
            send("C-p")
            wait_for(lambda s: s.count("alpha preview") == 2 and "Esc Close" in s, "Ctrl-P did not move selection inside picker")
            send("M-p")
            wait_for(lambda s: s.count("alpha preview") == 1 and "Esc Close" in s, "Alt-P did not hide preview")
            # Footer preview action is available to mouse users too.
            text("\x1b[<0;42;38M\x1b[<0;42;38m")
            wait_for(lambda s: s.count("alpha preview") == 2, "Mouse preview action did not restore preview")
            tmux("resize-window", "-t", "ui", "-x", "100", "-y", "30")
            wait_for(lambda s: "Find files" in s and "beta.lua" in s and s.count("alpha preview") == 1
                     and any("Find files" in line and line.rstrip().endswith("╮") for line in s.splitlines()),
                     "Narrow picker did not hide preview and fit its bounds")
            save_capture("find-files-compact")
            close()
            tmux("resize-window", "-t", "ui", "-x", "30", "-y", "12")
            picker("find_files", "Find files")
            close()
            tmux("resize-window", "-t", "ui", "-x", "160", "-y", "38")
            picker("find_files", "Find files")
            text("beta")
            wait_for(lambda s: "> beta" in s and "beta preview" in s, "Filtering did not update preview")
            text("\x1b[<0;4;38M\x1b[<0;4;38m")
            wait_for(lambda s: "Esc Close" not in s and "beta.lua" in s.splitlines()[0], "Mouse Open did not select file")
            picker("buffers", "Open files")
            close()
            picker("oldfiles", "Recent files")
            close()
            send("M-g")
            wait_for(lambda s: "Search project" in s and "Esc Close" in s, "Alt-G did not open project search")
            text("answer")
            wait_for(lambda s: "alpha.lua" in s and "answer" in s and "Esc Close" in s, "Project search did not return matches")
            save_capture("search-project")
            close()
            picker("current_buffer_fuzzy_find", "Search this file")
            close()
            picker("commands", "Commands")
            close()
            send("F11")
            wait_for(lambda s: "WORKSPACE" not in s and "Return" in s, "Zen did not open")
            picker("find_files", "Find files")
            save_capture("find-files-zen")
            send("F11")
            wait_for(lambda s: ("WORKSPACE" in s or "EXPLORER" in s) and "Esc Close" not in s, "Zen toggle did not close picker and restore workspace")
            picker("find_files", "Find files")
            send("F1")
            wait_for(lambda s: "Commands / type to filter" in s and "Esc Close" not in s, "Command menu did not replace picker")
            send("Escape", "C-q")
        finally:
            subprocess.run(["tmux", "-S", socket, "kill-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("Picker UI integration passed: search, selection, mouse actions, preview, resize, escape, Normal/Zen")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--plugin-root", type=pathlib.Path, default=pathlib.Path.home() / ".local/share/tuim/lazy")
    parser.add_argument("--capture", type=pathlib.Path)
    args = parser.parse_args()
    run(args.plugin_root, args.capture)
