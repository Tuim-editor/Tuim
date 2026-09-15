#!/usr/bin/env python3
"""Resize a real terminal without keystrokes and verify the shell's PTY size."""
import os
import pathlib
import re
import shlex
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tuim-resize-') as directory:
    base = pathlib.Path(directory)
    env = {'TUIM_DISABLE_PLUGINS': '1', 'TUIM_SKIP_ONBOARDING': '1', 'SHELL': '/bin/sh', 'TERM': 'xterm-256color'}
    for name in ('config', 'data', 'state', 'cache'):
        (base / name).mkdir()
        env[f'XDG_{name.upper()}_HOME'] = str(base / name)
    (base / 'data/tuim').mkdir()
    (base / 'data/tuim/settings.json').write_text('{"mode":"normal","nerd_fonts":false}')
    sample = base / 'sample.txt'
    sample.write_text('editor stays visible\n')
    socket = str(base / 'tmux.sock')

    def tmux(*args):
        return subprocess.check_output(['tmux', '-S', socket, *args], text=True)

    def screen():
        return tmux('capture-pane', '-p', '-t', 'ui')

    def wait_for(predicate):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            grid = screen()
            if predicate(grid):
                return grid
            time.sleep(0.03)
        raise AssertionError(screen())

    command = shlex.join(['env', *(f'{k}={v}' for k, v in env.items()), str(ROOT / 'zig-out/bin/tuim'), str(sample)])
    try:
        tmux('new-session', '-d', '-s', 'ui', '-x', '120', '-y', '36', '-c', str(base), command)
        wait_for(lambda s: 'editor stays visible' in s)
        tmux('send-keys', '-t', 'ui', 'C-t')
        wait_for(lambda s: 'Debug console' in s)
        # Spaces can move Neovim's terminal cursor without a grid-line update.
        # Each old software cursor must be erased even in these cursor-only frames.
        tmux('send-keys', '-l', '-t', 'ui', "PS1='TUIM> '")
        time.sleep(0.15)
        tmux('send-keys', '-t', 'ui', 'Enter')
        wait_for(lambda s: any(line.split('│')[-1].lstrip().startswith('TUIM>') for line in s.splitlines()))
        tmux('send-keys', '-l', '-t', 'ui', 'echo')
        time.sleep(0.15)
        for _ in range(4):
            tmux('send-keys', '-l', '-t', 'ui', ' ')
            time.sleep(0.12)
        grid = wait_for(lambda s: 'TUIM> echo' in s)
        row, line = next((i, line) for i, line in enumerate(grid.splitlines()) if 'TUIM> echo' in line)
        command_x = line.index('TUIM> echo') + len('TUIM> ')
        ansi = tmux('capture-pane', '-p', '-e', '-t', 'ui').splitlines()[row]
        backgrounds = []
        background = None
        for chunk in re.split(r'(\x1b\[[0-9;]*m)', ansi):
            if chunk.startswith('\x1b['):
                codes = [int(c or 0) for c in chunk[2:-1].split(';')]
                i = 0
                while i < len(codes):
                    code = codes[i]
                    if code in (0, 49):
                        background = None
                    elif 40 <= code <= 47 or 100 <= code <= 107:
                        background = (code,)
                    elif code in (38, 48) and i + 1 < len(codes):
                        count = 4 if codes[i + 1] == 2 else 2
                        if code == 48:
                            background = tuple(codes[i + 1:i + count + 1])
                        i += count
                    i += 1
            else:
                backgrounds.extend([background] * len(chunk))
        expected = backgrounds[command_x]
        assert len(backgrounds) >= command_x + 8, repr(ansi)
        assert backgrounds[command_x + 4:command_x + 8] == [expected] * 4, ('Spaces retained cursor blocks', repr(ansi))
        tmux('send-keys', '-l', '-t', 'ui', 'ok')
        tmux('send-keys', '-t', 'ui', 'Enter')

        for width, height in ((90, 28), (150, 45), (45, 16), (120, 36)):
            tmux('resize-window', '-t', 'ui', '-x', str(width), '-y', str(height))
            # No keypress wakes Tuim: the footer must move by itself.
            grid = wait_for(lambda s: len(s.splitlines()) == height and 'Zen' in s.splitlines()[-1])
            wait_for(lambda s: '[Debug console]' in s or '[Debug]' in s)
            time.sleep(0.15)
            marker = base / f'size-{width}'
            tmux('send-keys', '-l', '-t', 'ui', 'stty size > ' + shlex.quote(str(marker)))
            tmux('send-keys', '-t', 'ui', 'Enter')
            wait_for(lambda _: marker.exists() and bool(marker.read_text().strip()))
            grid = screen()
            header_y, header = next((i, line) for i, line in enumerate(grid.splitlines()) if '[Debug console]' in line or '[Debug]' in line)
            panel_x = header.index('Terminal') - 3 if 'Terminal' in header else header.index('Term') - 2
            rows, cols = map(int, marker.read_text().split())
            assert (rows, cols) == (height - header_y - 2, width - panel_x), ((rows, cols), grid)
            terminal_lines = grid.splitlines()[header_y + 1:-1]
            assert not any(line.rstrip().endswith('All') for line in terminal_lines), grid
        pathlib.Path('/tmp/tuim-terminal-redesign.txt').write_text(screen())
        tmux('send-keys', '-t', 'ui', 'C-q')
    finally:
        subprocess.run(['tmux', '-S', socket, 'kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print('Terminal UI passed: spaces leave no cursor blocks, header, no ruler, idle resize and exact shell PTY dimensions at four sizes')
