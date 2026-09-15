#!/usr/bin/env python3
"""Check first-run colors offline, saved choices, and an optional installed parser set."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
for saved_theme in (None, 'default'):
    with tempfile.TemporaryDirectory(prefix='tuim-default-runtime-') as temp:
        base = Path(temp)
        env = os.environ.copy()
        env.update(NVIM_APPNAME='tuim', TUIM_SKIP_ONBOARDING='1', TUIM_DISABLE_PLUGINS='1')
        env.pop('TUIM_TEST_SAVED_THEME', None)
        for kind in ('config', 'data', 'state', 'cache'):
            env[f'XDG_{kind.upper()}_HOME'] = str(base / kind)
        if saved_theme:
            env['TUIM_TEST_SAVED_THEME'] = saved_theme
        subprocess.run(['nvim', '--headless', '--clean', '-l', 'tests/default_runtime.lua'],
                       cwd=ROOT, env=env, check=True, timeout=20)

plugin_data = os.environ.get('TUIM_TEST_PLUGIN_DATA')
if plugin_data:
    with tempfile.TemporaryDirectory(prefix='tuim-installed-runtime-') as temp:
        base = Path(temp)
        for name in ('lazy', 'site'):
            shutil.copytree(Path(plugin_data) / name, base / 'data/tuim' / name)
        env = os.environ.copy()
        env.update(NVIM_APPNAME='tuim', TUIM_SKIP_ONBOARDING='1')
        env.pop('TUIM_DISABLE_PLUGINS', None)
        for kind in ('config', 'data', 'state', 'cache'):
            env[f'XDG_{kind.upper()}_HOME'] = str(base / kind)
        subprocess.run(['nvim', '--headless', '--clean', '-l', 'tests/default_runtime.lua'],
                       cwd=ROOT, env=env, check=True, timeout=40)
