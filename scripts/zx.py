#!/usr/bin/env python3
"""
Drive ZEsarUX via its ZRCP (ZEsarUX Remote Command Protocol) TCP interface,
so a ZX Spectrum program can be built, loaded, run, and screenshotted
without touching the emulator's GUI.

Usage:
    zx.py start                        launch ZEsarUX with ZRCP enabled
    zx.py stop                         ask the emulator to exit
    zx.py load <snapshot.sna>          load a snapshot and let it run
    zx.py screenshot <out.png>         save the current screen as PNG
    zx.py registers                    print CPU registers
    zx.py keys <ascii-codes...>        send ascii key codes (space separated)
    zx.py cmd <raw ZRCP command>       send a raw ZRCP command and print reply
"""
import socket
import subprocess
import sys
import time
from pathlib import Path

ZESARUX_BIN = "/Applications/zesarux.app/Contents/MacOS/zesarux"
HOST = "localhost"
PORT = 10000
PID_FILE = Path(__file__).resolve().parent.parent / "build" / "zesarux.pid"
LOG_FILE = Path(__file__).resolve().parent.parent / "build" / "zesarux.log"


class ZRCP:
    def __init__(self, host=HOST, port=PORT, timeout=5):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self._recv(1.0)  # discard banner

    def _recv(self, wait=1.0):
        self.sock.settimeout(wait)
        data = b""
        try:
            while True:
                chunk = self.sock.recv(65536)
                if not chunk:
                    break
                data += chunk
        except socket.timeout:
            pass
        return data.decode(errors="replace")

    def cmd(self, text, wait=1.0):
        self.sock.sendall((text.strip() + "\n").encode())
        reply = self._recv(wait)
        # strip the trailing "command> " prompt
        if reply.endswith("command> "):
            reply = reply[: -len("command> ")]
        return reply.strip()

    def close(self):
        self.sock.close()


def wait_for_port(host, port, attempts=30, delay=0.5):
    for _ in range(attempts):
        try:
            with socket.create_connection((host, port), timeout=1):
                return True
        except OSError:
            time.sleep(delay)
    return False


def start():
    build_dir = PID_FILE.parent
    build_dir.mkdir(exist_ok=True)
    if PID_FILE.exists():
        pid = int(PID_FILE.read_text().strip())
        if _pid_alive(pid):
            print(f"ZEsarUX already running (pid {pid})")
            return

    log = open(LOG_FILE, "w")
    proc = subprocess.Popen(
        [
            ZESARUX_BIN,
            "--no-saveconf-on-exit",  # don't let this headless run's --vo/--ao
                                      # null settings get persisted into the
                                      # user's ~/.zesaruxrc and break normal
                                      # (GUI) launches from Applications
            "--enable-remoteprotocol",
            "--remoteprotocol-port", str(PORT),
            "--machine", "48k",
            # Headless: cocoa video ties emulation to the real display's
            # render/vsync loop, which stalls the whole CPU core if the
            # screen is asleep or the app is backgrounded. null/null keeps
            # the Z80 core running independent of any window server.
            "--vo", "null",
            "--ao", "null",
        ],
        stdout=log,
        stderr=subprocess.STDOUT,
    )
    PID_FILE.write_text(str(proc.pid))
    print(f"Launched ZEsarUX (pid {proc.pid}), waiting for ZRCP port {PORT}...")
    if wait_for_port(HOST, PORT):
        print("ZRCP ready.")
    else:
        print("Timed out waiting for ZRCP port; check", LOG_FILE)
        sys.exit(1)


def _pid_alive(pid):
    try:
        import os
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def stop():
    try:
        z = ZRCP()
        print(z.cmd("exit-emulator"))
        z.close()
    except OSError:
        print("Could not connect to ZRCP; nothing to stop?")
    if PID_FILE.exists():
        PID_FILE.unlink()


def load(snapshot):
    z = ZRCP()
    z.cmd("close-all-menus")  # a fresh launch starts with a menu open, which
                              # blocks loading otherwise
    path = Path(snapshot).resolve()
    # snapshot-load with an absolute quoted path silently fails; cd + a bare
    # relative filename via smartload is what actually works.
    z.cmd(f'cd "{path.parent}"')
    print(z.cmd(f"smartload {path.name}"))
    z.close()


def screenshot(out):
    out = Path(out).resolve()
    tmp_bmp = out.with_suffix(".bmp")
    z = ZRCP()
    print(z.cmd(f'save-screen "{tmp_bmp}"'))
    z.close()
    if out.suffix.lower() == ".png" and tmp_bmp.exists():
        from PIL import Image
        Image.open(tmp_bmp).save(out, "PNG")
        tmp_bmp.unlink()
        print(f"Saved {out}")


def registers():
    z = ZRCP()
    print(z.cmd("get-registers"))
    z.close()


def keys(codes):
    z = ZRCP()
    print(z.cmd("send-keys-ascii " + " ".join(codes)))
    z.close()


def raw(text):
    z = ZRCP()
    print(z.cmd(text))
    z.close()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    action, args = sys.argv[1], sys.argv[2:]
    if action == "start":
        start()
    elif action == "stop":
        stop()
    elif action == "load":
        load(args[0])
    elif action == "screenshot":
        screenshot(args[0])
    elif action == "registers":
        registers()
    elif action == "keys":
        keys(args)
    elif action == "cmd":
        raw(" ".join(args))
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
