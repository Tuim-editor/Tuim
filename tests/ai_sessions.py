#!/usr/bin/env python3
"""Exercise real agent terminal lifecycle using local echo processes."""
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="tuim-ai-") as directory:
    base = pathlib.Path(directory)
    env = os.environ.copy()
    env.update(TUIM_DISABLE_PLUGINS="1", TUIM_SKIP_ONBOARDING="1", NVIM_APPNAME="tuim")
    for name in ("config", "data", "state", "cache", "bin"):
        (base / name).mkdir()
        if name != "bin":
            env[f"XDG_{name.upper()}_HOME"] = str(base / name)
    for command in ("codex", "claude"):
        path = base / "bin" / command
        path.write_text("#!/bin/sh\nexec cat\n")
        path.chmod(0o755)
    env["PATH"] = str(base / "bin") + os.pathsep + env["PATH"]
    subprocess.run(["nvim", "--headless", "--clean", "-l", "tests/ai_sessions.lua"], cwd=ROOT, env=env, check=True, timeout=20)
