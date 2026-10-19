#!/usr/bin/env python3
"""proof-capture --run-before holds the device lock, and qemu signals are injected."""
from __future__ import annotations

import fcntl
import importlib.util
import json
import os
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROOF = ROOT / "bin" / "proof-capture.py"
SERIAL = "emulator-5610"
AVD = "TestAVD"


def load_proof():
    spec = importlib.util.spec_from_file_location("proof_capture_under_test", PROOF)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def noisy_png(path: Path) -> None:
    width, height = 32, 40
    raw = b"".join(bytes([0]) + bytes((y * 17 + x * 3) & 255 for x in range(width * 3)) for y in range(height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    blob = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"tEXt", b"Comment\x00" + (b"\x5a" * 9000))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(blob)


def write_adb(path: Path) -> None:
    path.write_text(
        "#!/usr/bin/env python3\n"
        "import os, sys\n"
        "args = sys.argv[1:]\n"
        "if 'screencap' in args:\n"
        "    sys.stdout.buffer.write(open(os.environ['FAKE_PNG'], 'rb').read())\n"
        "elif 'dumpsys' in args:\n"
        "    sys.stdout.buffer.write(b'mWakefulness=Awake\\n')\n"
        "elif args and args[0] == 'devices':\n"
        "    sys.stdout.buffer.write(b'List of devices attached\\n%s device\\n' % os.environ['FAKE_SERIAL'].encode())\n"
        "else:\n"
        "    sys.stdout.buffer.write(b'')\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


def project(tmp: Path) -> None:
    (tmp / ".antigravity-pm.json").write_text(json.dumps({
        "proof": {"defaultProvider": "phone", "providers": {"phone": {
            "type": "adb", "serial": SERIAL, "avd": AVD,
        }}}
    }), encoding="utf-8")
    (tmp / "fake-emulator").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    (tmp / "fake-emulator").chmod(0o755)


def nb_locked(mod, lock_dir: Path) -> bool:
    os.environ["PROOF_DEVICE_LOCK_DIR"] = str(lock_dir)
    fd = mod._open_lock(lock_dir, mod.lock_path(lock_dir, "serial", SERIAL))
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return True
    else:
        return False
    finally:
        os.close(fd)


def capture(tmp: Path, lock_dir: Path, sink: Path, ps: Path, png: Path, adb: Path, extra_env, args) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env.pop("PROOF_KEEP_EMULATOR", None)
    env.update({
        "PROOF_DEVICE_LOCK": "1",
        "PROOF_DEVICE_LOCK_DIR": str(lock_dir),
        "PROOF_QEMU_PS": str(ps),
        "PROOF_QEMU_SIGNAL_SINK": str(sink),
        "FAKE_PNG": str(png),
        "FAKE_SERIAL": SERIAL,
        "PROOF_DEVICE_LOCK_WAIT": "2",
    })
    env.pop("PROOF_KEEP_EMULATOR", None)
    env.update(extra_env)
    cmd = [
        sys.executable, str(PROOF),
        "--project", str(tmp),
        "--adb", str(adb),
        "--emulator", str(tmp / "fake-emulator"),
        "--xcrun", str(tmp / "fake-emulator"),
        *args,
    ]
    return subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=30)


def main() -> int:
    import tempfile
    fails = 0

    def check(cond, label, detail=""):
        nonlocal fails
        if cond:
            print("✔", label)
        else:
            print("✖", label, detail)
            fails += 1

    mod = load_proof()
    with tempfile.TemporaryDirectory() as raw:
        tmp = Path(raw)
        project(tmp)
        png = tmp / "screen.png"
        noisy_png(png)
        adb = tmp / "adb"
        write_adb(adb)
        ps = tmp / "qemu.ps"
        ps.write_text("4242\tqemu-system-aarch64 -avd %s\n4243\tnot-qemu %s\n" % (AVD, AVD), encoding="utf-8")
        lock_dir = tmp / "locks"
        lock_dir.mkdir(mode=0o700)

        marker = tmp / "during"
        import shlex
        hold = shlex.join([sys.executable, "-c",
                           "import pathlib,sys,time; pathlib.Path(sys.argv[1]).write_text('in'); time.sleep(2)",
                           str(marker)])
        sink = tmp / "signals.txt"
        base_env = {k: v for k, v in os.environ.items() if k not in ("PROOF_KEEP_EMULATOR", "PROOF_QEMU_PS", "PROOF_QEMU_SIGNAL_SINK")}
        proc = subprocess.Popen(
            [sys.executable, str(PROOF), "--project", str(tmp), "--adb", str(adb),
             "--emulator", str(tmp / "fake-emulator"), "--run-before", hold],
            env={
                **base_env,
                "PROOF_DEVICE_LOCK": "1",
                "PROOF_DEVICE_LOCK_DIR": str(lock_dir),
                "PROOF_QEMU_PS": str(ps),
                "PROOF_QEMU_SIGNAL_SINK": str(sink),
                "FAKE_PNG": str(png),
                "FAKE_SERIAL": SERIAL,
                "PROOF_DEVICE_LOCK_WAIT": "2",
            },
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        deadline = time.time() + 10
        while not marker.exists() and time.time() < deadline:
            time.sleep(0.05)
        busy = marker.exists() and nb_locked(mod, lock_dir)
        out, err = proc.communicate(timeout=20)
        shots = list((tmp / "reports").glob("proof-*.png")) if (tmp / "reports").exists() else []
        lines = sink.read_text(encoding="utf-8").splitlines() if sink.exists() else []
        check(busy, "run-before runs while the device lock is held", err[-300:])
        check(proc.returncode == 0 and len(shots) == 1, "successful capture writes one PNG", "rc=%s %s" % (proc.returncode, err[-300:]))
        check(lines == ["CONT 4242 %s" % AVD, "STOP 4242 %s" % AVD], "continue then stop only the matching qemu", str(lines))

        sink.write_text("", encoding="utf-8")
        for old in shots:
            old.unlink()
        kept = capture(tmp, lock_dir, sink, ps, png, adb, {"PROOF_KEEP_EMULATOR": "1"}, ["--run-before", shlex.join([sys.executable, "-c", "import sys; sys.exit(0)"])])
        lines = sink.read_text(encoding="utf-8").splitlines() if sink.exists() else []
        check(kept.returncode == 0 and lines == ["CONT 4242 %s" % AVD], "keep-emulator continues and does not stop", str(lines) + kept.stderr[-200:])

        sink.write_text("", encoding="utf-8")
        os.environ["PROOF_DEVICE_LOCK_DIR"] = str(lock_dir)
        fd = mod._open_lock(lock_dir, mod.lock_path(lock_dir, "serial", SERIAL))
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            held = capture(tmp, lock_dir, sink, ps, png, adb, {}, ["--no-device-lock", "--run-before", shlex.join([sys.executable, "-c", "import sys; sys.exit(0)"])])
        finally:
            os.close(fd)
        lines = sink.read_text(encoding="utf-8").splitlines() if sink.exists() else []
        check(held.returncode == 0 and lines == ["CONT 4242 %s" % AVD], "another holder skips stop", str(lines) + held.stderr[-200:])

        sink.write_text("", encoding="utf-8")
        before_shots = set((tmp / "reports").glob("proof-*.png")) if (tmp / "reports").exists() else set()
        failed = capture(tmp, lock_dir, sink, ps, png, adb, {}, ["--run-before", shlex.join([sys.executable, "-c", "import sys; sys.exit(3)"])])
        after = set((tmp / "reports").glob("proof-*.png")) if (tmp / "reports").exists() else set()
        released = not nb_locked(mod, lock_dir)
        check(failed.returncode != 0 and after == before_shots and released, "failed run-before writes no PNG and releases the lock", "rc=%s %s" % (failed.returncode, failed.stderr[-200:]))

    if fails:
        print("test_proof_run_before: FAIL (%s)" % fails)
        return 1
    print("test_proof_run_before: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
