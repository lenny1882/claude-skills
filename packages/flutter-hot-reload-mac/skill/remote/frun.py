#!/usr/bin/env python3
"""Run `flutter run` on the device's machine under a pty, with keys fed from a fifo.

Why a pty at all: `flutter run` started from a non-interactive SSH command
ignores anything piped to its stdin. It launches and the app works, but `r`
never reloads — verified, no "Performing hot reload" ever appears in the log.
macOS `script(1)` cannot stand in for a terminal here either: it wants a tty on
its OWN stdin and dies with "tcgetattr/ioctl: Operation not supported on
socket".

So the app gets a real pty, its output is copied to a log file, and a fifo
carries keystrokes in from any later call:

    printf 'r' > $FRUN_FIFO     # hot reload
    printf 'R' > $FRUN_FIFO     # hot restart

The fifo is opened O_RDWR so it never sees EOF when no writer is attached.

Every path is per device, so two runs on two simulators never share a fifo,
log or PID file, and a stop kills only its own run.

Environment (all set by bin/start.sh):
    FRUN_REPO      checkout the build reads
    FRUN_DEV       device UDID
    FRUN_FLUTTER   flutter binary, absolute or relative to FRUN_REPO
    FRUN_FLAVOR    --flavor value, empty for none
    FRUN_TARGET    -t value
    FRUN_GEM_HOME  CocoaPods' gem directory, only when pod is not on PATH
    FRUN_FIFO      keystroke fifo
    FRUN_LOG       flutter's output
    FRUN_PID       written as "<this pid> <flutter pid> <repo>"; removed on exit
"""
import os
import pty
import select
import signal
import subprocess
import sys

def need(name):
    return os.environ.get(name) or sys.exit(name + " is not set")

REPO = need("FRUN_REPO")
DEV = need("FRUN_DEV")
FLUTTER = need("FRUN_FLUTTER")
FLAVOR = os.environ.get("FRUN_FLAVOR", "")
TARGET = os.environ.get("FRUN_TARGET", "lib/main.dart")
GEM_HOME = os.environ.get("FRUN_GEM_HOME", "")
FIFO = need("FRUN_FIFO")
LOG = need("FRUN_LOG")
PIDFILE = need("FRUN_PID")

if os.path.exists(FIFO):
    os.remove(FIFO)
os.mkfifo(FIFO)

env = dict(os.environ)
# Only when maestro-drive's describe found pod missing from PATH: setting
# GEM_HOME when it is not needed breaks a working CocoaPods as easily.
if GEM_HOME:
    env["GEM_HOME"] = GEM_HOME
    env["PATH"] = GEM_HOME + "/bin:" + env["PATH"]
env["TERM"] = "xterm"

flutter = FLUTTER if os.path.isabs(FLUTTER) else os.path.join(REPO, FLUTTER)
cmd = [flutter, "run", "-d", DEV, "-t", TARGET]
if FLAVOR:
    cmd[2:2] = ["--flavor", FLAVOR]

master, slave = pty.openpty()
p = subprocess.Popen(cmd, cwd=REPO, env=env,
                     stdin=slave, stdout=slave, stderr=slave,
                     preexec_fn=os.setsid)
os.close(slave)

with open(PIDFILE, "w") as f:
    f.write("%d %d %s\n" % (os.getpid(), p.pid, REPO))

# A stop is a SIGTERM to this process. Without a handler Python dies on the
# spot, the finally below never runs, and flutter — in its own session — keeps
# running with nobody holding its pty.
def stop(signum, frame):
    raise SystemExit(0)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGHUP, stop)

log = open(LOG, "wb", 0)
log.write(("[frun] " + " ".join(cmd) + "\n").encode())
fifo = os.open(FIFO, os.O_RDWR | os.O_NONBLOCK)

try:
    while p.poll() is None:
        r, _, _ = select.select([master, fifo], [], [], 1.0)
        if master in r:
            try:
                data = os.read(master, 65536)
            except OSError:      # pty closes when the child exits
                break
            if not data:
                break
            log.write(data)
        if fifo in r:
            data = os.read(fifo, 4096)
            if data:
                os.write(master, data)
finally:
    if p.poll() is None:
        try:
            os.killpg(p.pid, signal.SIGTERM)
            p.wait(timeout=10)
        except Exception:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except Exception:
                pass
    log.write(b"\n[frun] flutter run exited\n")
    log.close()
    for path in (PIDFILE, FIFO):
        try:
            os.remove(path)
        except OSError:
            pass
