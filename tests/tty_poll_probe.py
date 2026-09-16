#!/usr/bin/env python3
"""Standalone probe: inside a pty.fork child (so /dev/tty is the controlling
pty slave), report poll()/select() readiness for /dev/tty and stdin, idle and
with a byte pending. Prints everything the child says, then kills it."""
import os, pty, select, signal, sys, termios, time, tty

NAMES = [("POLLIN", select.POLLIN), ("POLLPRI", select.POLLPRI),
         ("POLLOUT", select.POLLOUT), ("POLLERR", select.POLLERR),
         ("POLLHUP", select.POLLHUP), ("POLLNVAL", select.POLLNVAL)]


def decode(r):
    return "|".join(n for n, b in NAMES if r & b) or "0"


def child():
    def say(s):
        os.write(1, (s + "\n").encode())

    try:
        tty_fd = os.open("/dev/tty", os.O_RDWR)
    except OSError as e:
        tty_fd = -1
        say("open(/dev/tty) failed: %s" % e)
    fds = [("stdin(0)", 0)] + ([("/dev/tty", tty_fd)] if tty_fd >= 0 else [])
    if tty_fd >= 0:
        a, b = os.fstat(0), os.fstat(tty_fd)
        say("same-device-inode(stdin,/dev/tty)=%s" % ((a.st_dev, a.st_ino) == (b.st_dev, b.st_ino)))

    def probe(tag):
        for label, fd in fds:
            p = select.poll()
            p.register(fd, select.POLLIN)
            res = p.poll(0)
            r = res[0][1] if res else 0
            try:
                rr, _, _ = select.select([fd], [], [], 0)
                sel = "readable" if rr else "not-readable"
            except OSError as e:
                sel = "error=%s" % e
            say("%s %-9s poll revents=%-8s (raw=%d) select=%s" % (tag, label, decode(r), r, sel))

    tty.setraw(0)  # the app runs in raw mode; canonical mode hides bytes
    probe("idle ")
    say("READY")
    time.sleep(1.5)  # parent sends a byte during this window
    probe("armed")
    for label, f in fds:
        os.set_blocking(f, False)
        try:
            got = os.read(f, 16)
        except BlockingIOError:
            got = "EAGAIN"
        except OSError as e:
            got = "error=%s" % e
        os.set_blocking(f, True)
        say("armed %-9s nonblocking read -> %r" % (label, got))
    say("DONE")
    os._exit(0)


def main():
    pid, fd = pty.fork()
    if pid == 0:
        child()
    buf = b""
    deadline = time.time() + 8
    sent = False
    while time.time() < deadline and b"DONE" not in buf:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
        if not sent and b"READY" in buf:
            sent = True
            os.write(fd, b"a")
    sys.stdout.write(buf.decode(errors="replace").replace("\r\n", "\n"))
    sys.stdout.flush()
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    os.waitpid(pid, 0)
    os.close(fd)


main()
