#!/usr/bin/env python3
# Launches Tuim with the pty as its controlling terminal (pty.fork), the way a
# real shell does. tests/pty_integration.py uses start_new_session, which
# leaves /dev/tty unavailable and hides controlling-tty bugs.
import fcntl
import os
import pathlib
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = pathlib.Path(os.environ.get("TUIM_TEST_BINARY", ROOT / "zig-out/bin/tuim")).resolve()
ENTER_ALT = b"\x1b[?1049h"


def read_available(fd, deadline):
    output = bytearray()
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        output.extend(chunk)
    return bytes(output)


def diagnose(pid, data_dir, output):
    """Explain a stuck child: its last output, its log, and where it is stuck."""
    report = ["output tail: %r" % bytes(output[-2000:]).decode("utf-8", errors="replace")]
    try:  # the log may be missing, unreadable, or rotated away under us
        log = (data_dir / "tuim.log").read_text(encoding="utf-8", errors="replace")[-4000:]
    except OSError as exc:
        log = "<unreadable: %s>" % exc
    report.append("tuim.log tail:\n%s" % log)
    # /proc/<pid>/stack needs CAP_SYS_ADMIN, so read status on Linux instead.
    for cmd in (["ps", "-o", "pid,stat,wchan,%cpu,command", "-p", str(pid)],
                ["sample", str(pid), "1", "-mayDie"] if sys.platform == "darwin" else
                ["cat", "/proc/%d/status" % pid]):
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            report.append("$ %s\n%s%s" % (" ".join(cmd), out.stdout, out.stderr))
        except Exception as exc:  # diagnostics must never mask the real failure
            report.append("$ %s -> %s" % (" ".join(cmd), exc))
    return "\n\n".join(report)


def run_controlling_tty():
    with tempfile.TemporaryDirectory(prefix="tuim-ctty-") as temp:
        base = pathlib.Path(temp)
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
        pid, fd = pty.fork()
        if pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
            os.execve(str(BINARY), [str(BINARY)], env)

        waited = 0
        status = 0
        try:
            output = bytearray()
            deadline = time.monotonic() + 10.0
            while ENTER_ALT not in output and time.monotonic() < deadline:
                output.extend(read_available(fd, min(deadline, time.monotonic() + 0.2)))
            # Let the first frame finish drawing.
            output.extend(read_available(fd, time.monotonic() + 1.0))
            assert ENTER_ALT in output, "Tuim never drew its first frame"

            deadline = time.monotonic() + 10.0
            while time.monotonic() < deadline:
                try:
                    os.write(fd, b"\x11")  # Ctrl-Q
                except OSError as exc:  # EIO: the child closed the pty already
                    waited, status = os.waitpid(pid, os.WNOHANG)
                    if waited != 0:
                        break
                    raise AssertionError(
                        "pty master write failed (%s) while Tuim was still running\n" % exc
                        + diagnose(pid, base / "data/tuim", output))
                output.extend(read_available(fd, min(deadline, time.monotonic() + 0.4)))
                del output[:-8192]  # a redraw loop must not exhaust memory before we report
                waited, status = os.waitpid(pid, os.WNOHANG)
                if waited != 0:
                    break
            if waited == 0:
                raise AssertionError(
                    "Tuim did not exit within 10s of Ctrl-Q with a controlling tty\n"
                    + diagnose(pid, base / "data/tuim", output))
        finally:
            if waited == 0:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(fd)

        assert os.WIFEXITED(status), f"Tuim exited abnormally: {status}"
        assert os.WEXITSTATUS(status) == 0, f"Tuim exited with code {os.WEXITSTATUS(status)}"


if __name__ == "__main__":
    if not BINARY.exists():
        raise SystemExit("Build Tuim before running PTY tests: zig build")
    run_controlling_tty()
    print("Tuim controlling tty test passed")
