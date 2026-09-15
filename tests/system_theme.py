#!/usr/bin/env python3
"""Exercise System theme with isolated desktop palettes and no plugin downloads."""
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="tuim-system-theme-") as directory:
    base = pathlib.Path(directory)
    env = os.environ.copy()
    env.update(TUIM_DISABLE_PLUGINS="1", TUIM_SKIP_ONBOARDING="1", NVIM_APPNAME="tuim")
    for name in ("config", "data", "state", "cache"):
        (base / name).mkdir()
        env[f"XDG_{name.upper()}_HOME"] = str(base / name)
    subprocess.run(["nvim", "--headless", "--clean", "-l", "tests/system_theme.lua"], cwd=ROOT, env=env, check=True, timeout=20)
