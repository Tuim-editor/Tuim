#!/usr/bin/env python3
"""Capture real Tuim terminal grids as WebP images (no fabricated UI).

Run after zig build:
  uv run --with pillow --with pyte python scripts/capture_screenshots.py
Requires tmux and a monospace font discoverable through fontconfig.
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import time

import pyte
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'docs/screenshots'
COLS, ROWS = 132, 38
CELL_W, CELL_H = 12, 25
FONT = subprocess.check_output(['fc-match', '-f', '%{file}', 'monospace'], text=True)
font = ImageFont.truetype(FONT, 19)
bold_path = subprocess.check_output(['fc-match', '-f', '%{file}', 'monospace:style=Bold'], text=True)
bold_font = ImageFont.truetype(bold_path, 19)
COLORS = dict(zip(('black', 'red', 'green', 'brown', 'blue', 'magenta', 'cyan', 'white'),
                 ('16161d', 'c34043', '76946a', 'c0a36e', '7e9cd8', '957fb8', '6a9589', 'dcd7ba')))


def render(ansi, target):
    screen = pyte.Screen(COLS, ROWS)
    pyte.Stream(screen).feed(ansi.rstrip('\n').replace('\n', '\r\n'))
    image = Image.new('RGB', (COLS * CELL_W, ROWS * CELL_H), '#1f1f1f')
    draw = ImageDraw.Draw(image)

    def color(value, fallback):
        return '#' + (fallback if value == 'default' else COLORS.get(value, value))

    for y in range(ROWS):
        for x in range(COLS):
            cell = screen.buffer[y][x]
            fg, bg = color(cell.fg, 'cccccc'), color(cell.bg, '1f1f1f')
            if cell.reverse:
                fg, bg = bg, fg
            px, py = x * CELL_W, y * CELL_H
            draw.rectangle((px, py, px + CELL_W - 1, py + CELL_H - 1), fill=bg)
            if cell.data.strip():
                draw.text((px, py + 1), cell.data, font=bold_font if cell.bold else font, fill=fg)
            if cell.underscore:
                draw.line((px, py + CELL_H - 3, px + CELL_W, py + CELL_H - 3), fill=fg)
    image.save(target, 'WEBP', lossless=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path, default=Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'tuim', help='Tuim data directory populated by setup.sh')
    args = parser.parse_args()
    for name in ('lazy', 'site'):
        if not (args.data_dir / name).is_dir():
            parser.error('Run setup.sh first: missing ' + str(args.data_dir / name))
    OUTPUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='tuim-screenshots-') as temp:
        base = Path(temp)
        project = base / 'tuim'
        (project / 'src').mkdir(parents=True)
        for name in ('build.zig', 'build.zig.zon', 'README.md', 'LICENSE', 'src/main.zig'):
            shutil.copyfile(ROOT / name, project / name)
        subprocess.run(['git', 'init', '-q', '-b', 'main', str(project)], check=True)
        subprocess.run(['git', '-C', str(project), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(project), '-c', 'user.name=Tuim demo', '-c', 'user.email=demo@example.com', 'commit', '-qm', 'Add Tuim project files'], check=True)
        with (project / 'build.zig').open('a') as file:
            file.write('\n// Build locally with zig build.\n')
        socket = str(base / 'tmux.sock')

        def tmux(*args):
            return subprocess.check_output(['tmux', '-S', socket, *args], text=True)

        def wait_for(phrase):
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                grid = tmux('capture-pane', '-p', '-t', 'capture')
                if phrase in grid:
                    return grid
                time.sleep(.1)
            raise RuntimeError(f'Missing {phrase}:\n{grid}')

        def send(*keys):
            for key in keys:
                tmux('send-keys', '-t', 'capture', key)
                time.sleep(.15)

        def capture(name):
            time.sleep(.3)
            ansi = tmux('capture-pane', '-p', '-e', '-t', 'capture')
            if any(error in ansi for error in ('stack traceback', 'Press ENTER', 'Cannot make changes')):
                raise RuntimeError(f'Application error in {name}')
            render(ansi, OUTPUT / f'{name}.webp')
            print(f'Captured {name}', flush=True)

        def start(mode):
            data = base / mode / 'data/tuim'
            data.mkdir(parents=True)
            (data / 'settings.json').write_text(json.dumps({'mode': mode, 'nerd_fonts': False, 'theme': 'vscode'}))
            for name in ('lazy', 'site'):
                shutil.copytree(args.data_dir / name, data / name)
            env = dict(HOME=str(base / mode), XDG_CONFIG_HOME=str(base / mode / 'config'),
                       XDG_DATA_HOME=str(base / mode / 'data'), XDG_CACHE_HOME=str(base / mode / 'cache'),
                       XDG_STATE_HOME=str(base / mode / 'state'), TUIM_DISABLE_PLUGINS='0',
                       TUIM_SKIP_ONBOARDING='1', TERM='xterm-256color', COLORTERM='truecolor')
            command = shlex.join(['env', *(f'{key}={value}' for key, value in env.items()), str(ROOT / 'zig-out/bin/tuim'), 'build.zig'])
            tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'capture', '-x', str(COLS), '-y', str(ROWS), '-c', str(project), command)
            wait_for('build.zig')
            time.sleep(6)
            tmux('resize-window', '-t', 'capture', '-x', str(COLS + 1))
            tmux('resize-window', '-t', 'capture', '-x', str(COLS))
            time.sleep(.3)

        try:
            start('normal')
            capture('explorer')
            tmux('send-keys', '-l', '-t', 'capture', '\x1b[<0;4;2M\x1b[<0;4;2m')
            wait_for('OPEN FILES')
            capture('normal')
            send('C-t')
            wait_for('Terminal')
            tmux('send-keys', '-l', '-t', 'capture', "export PS1='tuim $ '; clear")
            send('Enter')
            wait_for('tuim $')
            capture('terminal')
            send('C-t', 'F1')
            tmux('send-keys', '-l', '-t', 'capture', 'Settings')
            send('Enter')
            wait_for('Tuim Settings')
            send('Down')
            wait_for('VS Code Dark Modern')
            capture('settings')
            send('Escape', 'F1')
            tmux('send-keys', '-l', '-t', 'capture', 'Git')
            send('Enter')
            wait_for('build.zig')
            capture('source-control')
            send('F1')
            tmux('send-keys', '-l', '-t', 'capture', 'Extensions')
            send('Enter')
            wait_for('Your plugins')
            capture('extensions')
            send('Escape', 'F11')
            capture('zen')
            tmux('kill-session', '-t', 'capture')
            start('ide')
            capture('ide-mode')
        finally:
            subprocess.run(['tmux', '-S', socket, 'kill-server'], capture_output=True)


if __name__ == '__main__':
    main()
