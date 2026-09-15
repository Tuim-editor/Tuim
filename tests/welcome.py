import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
alpha = pathlib.Path(os.environ.get('XDG_DATA_HOME', pathlib.Path.home() / '.local/share')) / 'tuim/lazy/alpha-nvim'
if not alpha.is_dir():
    raise SystemExit('This test needs an installed alpha-nvim in Tuim.')
with tempfile.TemporaryDirectory(prefix='tuim-welcome-') as directory:
    base = pathlib.Path(directory)
    env = os.environ.copy()
    env.update(NVIM_APPNAME='tuim', TUIM_DISABLE_PLUGINS='0', TUIM_SKIP_ONBOARDING='1', TUIM_TEST_ALPHA=str(alpha), TUIM_TEST_ROOT=str(ROOT))
    for name in ('config', 'data', 'state', 'cache'):
        (base / name).mkdir()
        env[f'XDG_{name.upper()}_HOME'] = str(base / name)
    subprocess.run(['nvim', '--headless', '--clean', '-l', str(ROOT / 'tests/welcome.lua')], env=env, cwd=base, check=True, timeout=15)
