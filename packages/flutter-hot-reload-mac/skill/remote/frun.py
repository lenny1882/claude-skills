#!/usr/bin/env python3
"""Run `flutter run` on the Mac under a pty, with commands fed from a fifo.

Why a pty at all: `flutter run` started from a non-interactive SSH command
ignores anything piped to its stdin. It launches and the app works, but `r`
never reloads — verified, no "Performing hot reload" ever appears in the log.
macOS `script(1)` cannot stand in for a terminal here either: it wants a tty on
its OWN stdin and dies with "tcgetattr/ioctl: Operation not supported on
socket".

So the app gets a real pty, its output is copied to a log file, and a fifo
carries keystrokes in from any later SSH call:

    printf 'r' > /tmp/frun.in     # hot reload
    printf 'R' > /tmp/frun.in     # hot restart

The fifo is opened O_RDWR so it never sees EOF when no writer is attached.

Environment (all set by bin/start.sh):
    FRUN_REPO    checkout on the Mac
    FRUN_DEV     simulator UDID
    FRUN_FLUTTER flutter binary, relative to FRUN_REPO or absolute
    FRUN_FLAVOR  --flavor value, empty for none
    FRUN_TARGET  -t value
"""
import os
import pty
import select
import subprocess
import sys

REPO = os.environ.get("FRUN_REPO") or sys.exit("FRUN_REPO is not set")
DEV = os.environ.get("FRUN_DEV") or sys.exit("FRUN_DEV is not set")
FLUTTER = os.environ.get("FRUN_FLUTTER", ".fvm/flutter/bin/flutter")
FLAVOR = os.environ.get("FRUN_FLAVOR", "")
TARGET = os.environ.get("FRUN_TARGET", "lib/main.dart")

FIFO = "/tmp/frun.in"
LOG = "/tmp/frun.log"

if os.path.exists(FIFO):
    os.remove(FIFO)
os.mkfifo(FIFO)

env = dict(os.environ)
# CocoaPods lives under a different Ruby. Without GEM_HOME the build stops with
# "CocoaPods is installed but broken", which reads as a broken install.
env["GEM_HOME"] = os.path.expanduser("~/.gem")
env["PATH"] = env["GEM_HOME"] + "/bin:" + env["PATH"]
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
    log.write(b"\n[frun] flutter run exited\n")
    log.close()
