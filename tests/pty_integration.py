#!/usr/bin/env python3
import fcntl
import json
import os
import pathlib
import pty
import re
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = pathlib.Path(os.environ.get("TUIM_TEST_BINARY", ROOT / "zig-out/bin/tuim")).resolve()
ENTER_ALT = b"\x1b[?1049h"
LEAVE_ALT = b"\x1b[?1049l"
ENABLE_PASTE = b"\x1b[?2004h"
DISABLE_PASTE = b"\x1b[?2004l"


def disable_software_flow_control(fd):
    attrs = termios.tcgetattr(fd)
    attrs[0] &= ~termios.IXON
    attrs[0] &= ~getattr(termios, "IXOFF", 0)
    attrs[0] &= ~getattr(termios, "IXANY", 0)
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


def read_available(fd, deadline):
    output = bytearray()
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except BlockingIOError:
            continue
        except OSError:
            break
        if not chunk:
            break
        output.extend(chunk)
    return bytes(output)


def terminate_child(pid, grace=1.0):
    os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        waited, status = os.waitpid(pid, os.WNOHANG)
        if waited != 0:
            return status
        time.sleep(0.05)
    os.kill(pid, signal.SIGKILL)
    _, status = os.waitpid(pid, 0)
    return status


def run_mode(mode):
    with tempfile.TemporaryDirectory(prefix="tuim-pty-") as temp:
        base = pathlib.Path(temp)
        data = base / "data/tuim"
        data.mkdir(parents=True)
        (data / "settings.json").write_text(json.dumps({"mode": mode}), encoding="utf-8")

        env = os.environ.copy()
        env.update({
            "HOME": temp,
            "XDG_CONFIG_HOME": str(base / "config"),
            "XDG_DATA_HOME": str(base / "data"),
            "XDG_STATE_HOME": str(base / "state"),
            "XDG_CACHE_HOME": str(base / "cache"),
            "TUIM_DISABLE_PLUGINS": "1",
            "TUIM_SKIP_ONBOARDING": "1",
            "TERM": "xterm-256color",
        })
        fd, slave_fd = pty.openpty()
        disable_software_flow_control(slave_fd)
        child = subprocess.Popen(
            [str(BINARY)], stdin=slave_fd, stdout=slave_fd, stderr=slave_fd, env=env,
            start_new_session=True
        )
        os.close(slave_fd)
        pid = child.pid

        os.set_blocking(fd, False)
        original = termios.tcgetattr(fd)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        os.kill(pid, signal.SIGWINCH)
        output = bytearray(read_available(fd, time.monotonic() + 1.5))
        startup = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", bytes(output))
        for intro_text in (b"NVIM v", b"Nvim is open source", b":help nvim"):
            assert intro_text not in startup, f"{mode}: Neovim intro flashed during startup"

        if mode != "zen":
            selection_path = base / "terminal-selection.txt"
            os.write(fd, b"\x14")  # Ctrl-T opens and focuses the terminal panel.
            output.extend(read_available(fd, time.monotonic() + 0.5))
            os.write(fd, b"printf 'terminal-selection-marker\\n'\r")
            marker_deadline = time.monotonic() + 2.0
            marker_pattern = rb"\x1b\[\d+;\d+Hterminal-selection-marker"
            while re.search(marker_pattern, output) is None and time.monotonic() < marker_deadline:
                output.extend(read_available(fd, min(marker_deadline, time.monotonic() + 0.1)))
            assert re.search(marker_pattern, output) is not None, \
                f"{mode}: terminal selection marker was not rendered; output tail: {bytes(output[-1200:])!r}"
            os.write(fd, b"\x1c\x0e")  # Neovim terminal-normal: Ctrl-\\ Ctrl-N
            output.extend(read_available(fd, time.monotonic() + 0.2))
            os.write(fd, b"?terminal-selection-marker\r0v$\"ay")
            output.extend(read_available(fd, time.monotonic() + 0.2))
            command = f":call writefile([getreg('a')], '{selection_path}')\r\x1b"
            os.write(fd, command.encode("utf-8"))
            deadline = time.monotonic() + 2.0
            while not selection_path.exists() and time.monotonic() < deadline:
                output.extend(read_available(fd, min(deadline, time.monotonic() + 0.1)))
            assert selection_path.exists(), \
                f"{mode}: Ctrl-\\ Ctrl-N did not enter terminal-normal mode; output tail: {bytes(output[-1200:])!r}"
            selection_text = selection_path.read_text(encoding="utf-8")
            assert "terminal-selection-marker" in selection_text, \
                f"{mode}: terminal visual selection was not yanked: {selection_text!r}"
            os.write(fd, b"i")  # Return to the live shell after yanking.
            output.extend(read_available(fd, time.monotonic() + 0.1))

            os.write(fd, "integration 界 🙂".encode("utf-8"))
            output.extend(read_available(fd, time.monotonic() + 0.3))
            os.write(fd, b"\r")
            output.extend(read_available(fd, time.monotonic() + 0.3))
            os.write(fd, b"\x1b[200~pasted text\nsecond line\x1b[201~")
            output.extend(read_available(fd, time.monotonic() + 0.3))
            os.write(fd, b"\x1b[<0;50;5M\x1b[<0;50;5m")
            output.extend(read_available(fd, time.monotonic() + 0.3))
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
            os.kill(pid, signal.SIGWINCH)
        output.extend(read_available(fd, time.monotonic() + 1.0))
        waited = 0
        status = 0
        deadline = time.monotonic() + 8.0
        while time.monotonic() < deadline:
            os.write(fd, b"\x11")  # Ctrl-Q
            output.extend(read_available(fd, min(deadline, time.monotonic() + 0.4)))
            waited, status = os.waitpid(pid, os.WNOHANG)
            if waited != 0:
                break
            time.sleep(0.1)
        if waited == 0:
            status = terminate_child(pid)
            tail = bytes(output[-1000:]).decode("utf-8", errors="replace")
            log_path = data / "tuim.log"
            log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else "<missing>"
            os.close(fd)
            raise AssertionError(f"{mode}: Tuim did not exit after Ctrl-Q; output tail: {tail!r}; log: {log}")

        output.extend(read_available(fd, time.monotonic() + 0.25))
        restored = termios.tcgetattr(fd)
        os.close(fd)

        if os.WIFEXITED(status):
            if os.WEXITSTATUS(status) != 0:
                raise AssertionError(f"{mode}: Tuim exited with code {os.WEXITSTATUS(status)}")
        elif os.WIFSIGNALED(status):
            sig = os.WTERMSIG(status)
            if sig not in (signal.SIGTERM, signal.SIGHUP):
                raise AssertionError(f"{mode}: Tuim died from unexpected signal {sig}")
        else:
            raise AssertionError(f"{mode}: Tuim exited abnormally: {status}")

        assert restored == original, f"{mode}: terminal attributes were not restored"
        assert ENTER_ALT in output, f"{mode}: alternate screen was not enabled"
        assert ENABLE_PASTE in output, f"{mode}: bracketed paste was not enabled"
        assert DISABLE_PASTE in output, f"{mode}: bracketed paste was not disabled"
        assert LEAVE_ALT in output, f"{mode}: alternate screen was not disabled"


def run_startup_failure():
    with tempfile.TemporaryDirectory(prefix="tuim-pty-failure-") as temp:
        env = os.environ.copy()
        env.update({"HOME": temp, "PATH": "/nonexistent", "TUIM_DISABLE_PLUGINS": "1"})
        fd, slave_fd = pty.openpty()
        child = subprocess.Popen(
            [str(BINARY)], stdin=slave_fd, stdout=slave_fd, stderr=slave_fd, env=env,
            start_new_session=True
        )
        os.close(slave_fd)
        pid = child.pid
        os.set_blocking(fd, False)
        original = termios.tcgetattr(fd)
        output = read_available(fd, time.monotonic() + 3)
        _, status = os.waitpid(pid, 0)
        restored = termios.tcgetattr(fd)
        os.close(fd)
        assert status != 0, "missing Neovim should fail startup"
        assert restored == original, "startup failure left terminal attributes changed"
        assert LEAVE_ALT in output, "startup failure did not leave the alternate screen"
        assert b"Tuim could not start" in output, "startup failure was not actionable"


if __name__ == "__main__":
    if not BINARY.exists():
        raise SystemExit("Build Tuim before running PTY tests: zig build")
    for current_mode in ("normal", "ide", "zen"):
        run_mode(current_mode)
    if os.environ.get("TUIM_TEST_SKIP_STARTUP_FAILURE") != "1":
        run_startup_failure()
    print("Tuim PTY integration tests passed")
