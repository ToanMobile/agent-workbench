#!/usr/bin/env python3
"""Capture reports/proof-<stamp>.png from a device that is actually online.

Declared serial (`.antigravity-pm.json` proof provider) is used only when
`adb devices` reports state `device` and the serial is not denied.
If that serial is offline, or no allowed device is online, this starts the
AVD named on that provider (`avd`), or the single phone AVD on the machine,
waits until `sys.boot_completed=1`, then screencaps that emulator.

It does not screencap a dead ip:port and it does not substitute another
plugged-in phone. Denylist: ADB_DENY_SERIALS, ~/.config/universal-agent-devkit/adb-denylist,
<project>/.adb-denylist.

A provider of type shell runs its own command ({{out}} is the png path, {{project}}
is this checkout). That path does not boot an Android emulator.

iOS: provider type `simctl` or a declared `udid`, or profile `ios`, screenshots the one
Booted simulator (`xcrun simctl list devices -j`) with `xcrun simctl io <udid> screenshot`;
none or several Booted is a failure, never an Android fallback. With no declared provider
(no serial/avd) and a profile that is not android/automotive, a single Booted simulator is
used before adb; several Booted ones leave it to adb.

Device lock (adb only): several agents share one phone, so the capture holds a per-SERIAL flock around its
device commands (AVD boot, wakefulness, screencap; the `adb devices`/`connect` that pick the device run
before it). A second capture for the same serial waits (PROOF_DEVICE_LOCK_WAIT seconds in total, default
300, capped at 3600) and then exits 75 saying who holds it and since when; other serials, and an AVD versus
a phone, never wait for each other. Installing a build is not part of this tool and is not covered. The lock is taken
AFTER the device was chosen and the denylist applied, so a denied serial never reaches it. It lives in
$PROOF_DEVICE_LOCK_DIR (tests only) or ~/.config/universal-agent-devkit/device-locks (0700, one file per
sha256(kind:name)); the kernel drops it when the holder dies. An unusable lock dir is a warning, not a
failure (the old unlocked behaviour). Off: --no-device-lock or PROOF_DEVICE_LOCK=0.
Exit codes: 0 captured, 1 refused/failed, 2 usage, 75 device lock not obtained in time.
"""
from __future__ import annotations

import argparse
import contextlib
import errno
import hashlib
import json
import os
import re
import shlex
import stat
import subprocess
import sys
import time
import zlib
from pathlib import Path

try:
    import fcntl
except ImportError:  # no flock on this platform: the device lock degrades to a warning
    fcntl = None

PNG_SIG = b"\x89PNG\r\n\x1a\n"
MIN_BYTES = 8192
CAR_AVD = re.compile(r"car|auto", re.I)
PHONE_AVD = re.compile(r"phone|pixel", re.I)
# A proof shows a screen: under this share of distinct rows the image is one colour (screen
# off, black or blank), which is what the car gave while asleep (GeelyEx2 2026-09-26).
# ponytail: counts FILTERED rows ("Up" makes a smooth gradient one row), so the bar is low
# (real proofs measured ≥ 10.6 %, black ones 0.1-0.2 %); unfilter the rows if a real screen is refused.
MIN_DISTINCT_ROWS = 0.01
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


def parse_devices(text: str) -> list:
    out = []
    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line or line.startswith("List of devices") or line.startswith("*"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        serial, state = parts[0], parts[1]
        if state == "no" and len(parts) > 2 and parts[2] == "permissions":
            state = "no-permissions"
        if re.match(r"^[\w.:-]+$", serial):
            out.append({"serial": serial, "state": state})
    return out


def parse_deny(text: str) -> set:
    denied = set()
    for raw in (text or "").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        for piece in re.split(r"[\s,]+", line):
            if piece:
                denied.add(piece)
    return denied


def load_deny(project: Path) -> set:
    chunks = []
    env = os.environ.get("ADB_DENY_SERIALS")
    if env:
        chunks.append(env.replace(",", "\n"))
    files = [Path.home() / ".config" / "universal-agent-devkit" / "adb-denylist"]
    if project:
        files.append(project / ".adb-denylist")
    for path in files:
        try:
            chunks.append(path.read_text(encoding="utf-8"))
        except OSError:
            continue
    return parse_deny("\n".join(chunks))


def load_proof(project: Path) -> dict:
    path = project / ".antigravity-pm.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"name": None, "provider": {}, "providers": {}}
    proof = data.get("proof") or {}
    providers = proof.get("providers") or {}
    name = proof.get("defaultProvider")
    if not name and len(providers) == 1:
        name = next(iter(providers))
    provider = providers.get(name) if name else {}
    if not isinstance(provider, dict):
        provider = {}
    return {"name": name, "provider": provider, "providers": providers}


def read_profile(project: Path) -> str | None:
    path = project / ".agents" / "active-profile.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    profile = data.get("profile")
    return profile if isinstance(profile, str) else None


def pick_avd(avds: list, declared: str | None, profile: str | None = None) -> str | None:
    if declared:
        return declared
    names = [a.strip() for a in avds if a and a.strip()]
    if profile == "automotive":
        # Máy ảo đầu xe có sẵn trên máy này. CarAuto33 không phải bản dùng để chụp.
        if "CarConnect" in names:
            return "CarConnect"
        cars = [a for a in names if CAR_AVD.search(a) and a != "CarAuto33"]
        if len(cars) == 1:
            return cars[0]
        return None
    phones = [a for a in names if not CAR_AVD.search(a)]
    if len(phones) == 1:
        return phones[0]
    preferred = [a for a in phones if PHONE_AVD.search(a)]
    if len(preferred) == 1:
        return preferred[0]
    if len(names) == 1:
        return names[0]
    return None


def next_port(devices: list, start: int = 5554, denied=()) -> int:
    port = int(start) if int(start) % 2 == 0 else int(start) + 1
    used = {d["serial"] for d in devices} | set(denied)  # a denied serial is never booted onto either
    for _ in range(16):
        if "emulator-%d" % port not in used:
            return port
        port += 2
    return port


def _host_port(serial: str) -> bool:
    return bool(re.match(r"^[^:\s]+:\d+$", serial or ""))


def plan_target(configured, devices, denied, avd, connect_tried: bool, declared_avd: str | None = None) -> dict:
    """Decide the next step. Never returns a serial that is offline or denied."""
    deny = set(denied or [])
    listed = list(devices or [])
    online = [d for d in listed if d["state"] == "device" and d["serial"] not in deny]
    if configured and configured in deny:
        # Never screencap a denied serial. A declared AVD is the same fallback as an offline serial.
        if avd:
            return {
                "action": "boot",
                "avd": avd,
                "message": "Serial %s nam trong denylist — mo AVD %s." % (configured, avd),
            }
        return {"action": "fail", "message": "Serial %s nam trong denylist — khong chup." % configured}
    if configured:
        hit = next((d for d in listed if d["serial"] == configured), None)
        if hit and hit["state"] == "device":
            return {"action": "screencap", "serial": configured}
        if not connect_tried and _host_port(configured):
            return {"action": "connect", "serial": configured}
        if avd:
            return {
                "action": "boot",
                "avd": avd,
                "message": "Serial %s khong online (%s)." % (configured, hit["state"] if hit else "khong co trong adb devices"),
            }
        shown = ", ".join("%s=%s%s" % (d["serial"], d["state"], " denylist" if d["serial"] in deny else "") for d in listed) or "(khong co)"
        return {
            "action": "fail",
            "message": "Serial %s khong online. adb devices: %s. Khong co AVD de mo. Khong chup dia chi chet va khong lay may khac." % (configured, shown),
        }
    if len(online) == 1:
        return {"action": "screencap", "serial": online[0]["serial"]}
    if len(online) > 1:
        # One online device still wins over a declared AVD. An AVD inferred from
        # the SDK image list is not a choice: several devices still refuse.
        if declared_avd:
            return {
                "action": "boot",
                "avd": declared_avd,
                "message": "Nhieu may online (%s) — mo AVD %s." % (", ".join(d["serial"] for d in online), declared_avd),
            }
        return {"action": "fail", "message": "Nhieu may online (%s), khai serial." % ", ".join(d["serial"] for d in online)}
    if avd:
        return {"action": "boot", "avd": avd, "message": "Khong co may online."}
    return {"action": "fail", "message": "Khong co may online va khong co AVD de mo."}


def run(cmd, timeout):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def adb_devices(adb: str) -> list:
    res = run([adb, "devices", "-l"], 8)
    return parse_devices((res.stdout or "") + "\n" + (res.stderr or ""))


def list_avds(emulator: str | None) -> list:
    if not emulator:
        return []
    try:
        res = run([emulator, "-list-avds"], 15)
    except (OSError, subprocess.SubprocessError):
        return []
    return [ln.strip() for ln in (res.stdout or "").splitlines() if ln.strip()]


def find_emulator() -> str | None:
    roots = [
        os.environ.get("ANDROID_HOME"),
        os.environ.get("ANDROID_SDK_ROOT"),
        "/Volumes/Data/AndroidSDK",
        str(Path.home() / "Library" / "Android" / "sdk"),
    ]
    for root in roots:
        if not root:
            continue
        bin_path = Path(root) / "emulator" / "emulator"
        if bin_path.is_file():
            return str(bin_path)
    return None


def avd_name(adb: str, serial: str) -> str | None:
    if not serial.startswith("emulator-"):
        return None
    try:
        res = run([adb, "-s", serial, "emu", "avd", "name"], 5)
    except (OSError, subprocess.SubprocessError):
        return None
    for line in ((res.stdout or "") + "\n" + (res.stderr or "")).splitlines():
        line = line.strip()
        if line and line != "OK" and not line.startswith("Android") and not line.lower().startswith("error"):
            return line
    return None


def wait_boot(adb: str, serial: str, timeout_s: float) -> bool:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        listed = adb_devices(adb)
        hit = next((d for d in listed if d["serial"] == serial and d["state"] == "device"), None)
        if hit:
            try:
                prop = run([adb, "-s", serial, "shell", "getprop", "sys.boot_completed"], 8)
            except (OSError, subprocess.SubprocessError):
                prop = None
            if prop and (prop.stdout or "").strip() == "1":
                return True
        time.sleep(0.4)
    return False


def wakefulness(adb: str, serial: str) -> str | None:
    """mWakefulness from `dumpsys power` (Awake, Asleep, Dozing, Dreaming); None when unknown."""
    try:
        res = subprocess.run([adb, "-s", serial, "shell", "dumpsys", "power"], capture_output=True, timeout=10)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None
    m = re.search(r"mWakefulness=(\w+)", (res.stdout or b"").decode("utf-8", "replace"))
    return m.group(1) if m else None


def distinct_row_share(data: bytes) -> float | None:
    """Share of distinct (filtered) pixel rows in a PNG; None when it cannot be read.
    A one-colour screen repeats one row; a real screen has many different rows."""
    try:
        pos, idat, width, height, bpp = 8, [], 0, 0, 0
        while pos + 8 <= len(data):
            length = int.from_bytes(data[pos:pos + 4], "big")
            kind, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + length]
            if kind == b"IHDR":
                width, height = int.from_bytes(body[0:4], "big"), int.from_bytes(body[4:8], "big")
                bpp = body[8] * CHANNELS[body[9]]
            elif kind == b"IDAT":
                idat.append(body)
            elif kind == b"IEND":
                break
            pos += 12 + length
        stride = (width * bpp + 7) // 8 + 1
        raw = zlib.decompress(b"".join(idat))
        rows = {raw[i:i + stride] for i in range(0, stride * height, stride)}
        return len(rows) / height if height else None
    except (KeyError, IndexError, zlib.error):
        return None


def screencap(adb: str, serial: str, dest: Path, timeout_s: float) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        res = subprocess.run(
            [adb, "-s", serial, "exec-out", "screencap", "-p"],
            capture_output=True, timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        raise SystemExit("Chup anh serial %s qua %ss khong xong." % (serial, int(timeout_s)))
    data = res.stdout or b""
    dest.write_bytes(data)
    check_png(dest, data, serial, res)


def simctl_capture(xcrun: str, udid: str, dest: Path, timeout_s: float) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        res = subprocess.run([xcrun, "simctl", "io", udid, "screenshot", str(dest)], capture_output=True, timeout=timeout_s)
    except subprocess.TimeoutExpired:
        dest.unlink(missing_ok=True)
        raise SystemExit("Chup anh simulator %s qua %ss khong xong." % (udid, int(timeout_s)))
    data = dest.read_bytes() if dest.is_file() else b""
    check_png(dest, data, udid, res)


def shell_plan(proof: dict, provider: dict) -> dict:
    """Run the project's own capture command. Never an Android emulator."""
    command = provider.get("command")
    if not isinstance(command, str) or not command.strip():
        return {"action": "fail", "message": "Provider %s type shell nhung khong co command." % proof.get("name")}
    raw = provider.get("timeoutMs")
    try:
        timeout_s = float(raw) / 1000.0 if raw is not None else 60.0
    except (TypeError, ValueError):
        timeout_s = 60.0
    if timeout_s < 1:
        timeout_s = 1.0
    if timeout_s > 180:
        timeout_s = 180.0
    return {"action": "shell", "command": command, "timeout": timeout_s, "serial": proof.get("name") or "shell"}


def run_shell_proof(project: Path, command: str, dest: Path, timeout_s: float) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    rendered = command.replace("{{out}}", shlex.quote(str(dest))).replace("{{project}}", shlex.quote(str(project)))
    try:
        res = subprocess.run(rendered, shell=True, cwd=str(project), timeout=timeout_s, capture_output=True)
    except subprocess.TimeoutExpired:
        dest.unlink(missing_ok=True)
        raise SystemExit("Provider shell qua %ss." % int(timeout_s))
    if res.returncode != 0:
        dest.unlink(missing_ok=True)
        tail = (res.stderr or res.stdout or b"").decode("utf-8", "replace")[:400]
        raise SystemExit("Provider shell thoat %s: %s" % (res.returncode, tail))
    data = dest.read_bytes() if dest.is_file() else b""

    class Done:
        returncode = 0
        stderr = b""

    check_png(dest, data, "shell", Done())


def check_png(dest: Path, data: bytes, serial: str, res) -> None:
    """Refuse a failed capture, a non-PNG, a file <= MIN_BYTES and a one-colour screen."""
    if res.returncode != 0 or not data.startswith(PNG_SIG):
        tail = (res.stderr or b"").decode("utf-8", "replace")[:400]
        dest.unlink(missing_ok=True)
        raise SystemExit("Chup anh that bai (exit %s) serial %s: %s" % (res.returncode, serial, tail))
    if len(data) <= MIN_BYTES:
        dest.unlink()
        raise SystemExit("Anh %s chi %d byte — man hinh trong hoac chua kip ve." % (dest, len(data)))
    share = distinct_row_share(data)
    if share is not None and share < MIN_DISTINCT_ROWS:
        dest.unlink()
        raise SystemExit("Anh serial %s gan nhu mot mau (%.1f%% dong khac nhau) — man hinh tat, den hoac trong; "
                         "da xoa anh. Mo dung man hinh can chung minh roi chup lai." % (serial, share * 100))


def booted_sims(xcrun: str) -> list:
    """Booted iOS simulators from `xcrun simctl list devices -j`; [] when xcrun is missing or fails."""
    try:
        res = run([xcrun, "simctl", "list", "devices", "-j"], 15)
        runtimes = json.loads(res.stdout or "{}").get("devices") or {}
    except (OSError, ValueError, subprocess.SubprocessError, AttributeError):
        return []
    if not isinstance(runtimes, dict):
        return []
    return [{"udid": d["udid"], "name": d.get("name", "")}
            for devs in runtimes.values() if isinstance(devs, list)
            for d in devs if isinstance(d, dict) and d.get("state") == "Booted" and d.get("udid")
            and d.get("isAvailable", True) is not False]


def plan_sim(sims: list, udid: str | None) -> dict:
    shown = ", ".join("%s (%s)" % (s["udid"], s["name"]) for s in sims)
    if udid:
        if any(s["udid"] == udid for s in sims):
            return {"action": "simctl", "serial": udid}
        return {"action": "fail", "message": "Simulator %s khong Booted. Dang Booted: %s." % (udid, shown or "(khong co)")}
    if len(sims) == 1:
        return {"action": "simctl", "serial": sims[0]["udid"]}
    if sims:
        return {"action": "fail", "message": "Nhieu iOS Simulator dang Booted (%s), khai udid trong provider simctl." % shown}
    return {"action": "fail", "message": "Khong co iOS Simulator nao dang Booted (xcrun simctl list devices). "
            "Mo simulator (xcrun simctl boot <udid>), mo man can chung minh roi chay lai. Khong chup may Android thay the."}


def resolve(project: Path, adb: str, emulator: str | None, connect_timeout: float, xcrun: str = "xcrun") -> dict:
    proof = load_proof(project)
    provider = proof["provider"]
    kind = provider.get("type")
    profile = read_profile(project)
    adb_declared = bool(provider.get("serial") or provider.get("avd"))
    if kind == "simctl" or (kind is None and not adb_declared and (profile == "ios" or provider.get("udid"))):
        return plan_sim(booted_sims(xcrun), provider.get("udid") or None)
    if kind is None and not adb_declared and profile not in ("android", "automotive"):
        sims = booted_sims(xcrun)
        if len(sims) == 1:
            return plan_sim(sims, None)
    if kind in ("3d", "blender"):
        return {"action": "3d", "serial": "blender-3d"}
    if kind == "shell":
        return shell_plan(proof, provider)
    if kind not in (None, "adb"):
        return {
            "action": "fail",
            "message": "Provider %s co type %s, khong phai adb. Dung provider do de chup. Khong mo may ao Android." % (proof.get("name"), kind),
        }
    configured = provider.get("serial") or None
    declared_avd = provider.get("avd") or None
    avd = pick_avd(list_avds(emulator), declared_avd, profile)
    denied = load_deny(project)
    devices = adb_devices(adb)
    plan = plan_target(configured, devices, denied, avd, False, declared_avd)
    if plan["action"] == "connect":
        try:
            run([adb, "connect", plan["serial"]], connect_timeout)
        except subprocess.TimeoutExpired:
            pass
        devices = adb_devices(adb)
        plan = plan_target(configured, devices, denied, avd, True, declared_avd)
    plan["devices"] = devices
    plan["denied"] = sorted(denied)
    return plan


def boot_avd(adb: str, emulator: str, avd: str, devices: list, port: int, boot_timeout: float, denied=()) -> str:
    for dev in devices:
        if dev["state"] != "device" or not dev["serial"].startswith("emulator-"):
            continue
        if dev["serial"] in denied:  # never reuse (nor even ask) an emulator the denylist forbids
            continue
        if avd_name(adb, dev["serial"]) == avd:
            print("AVD %s da mo tai %s" % (avd, dev["serial"]), file=sys.stderr)
            return dev["serial"]
    serial = "emulator-%d" % port
    cmd = [emulator, "-avd", avd, "-port", str(port), "-no-boot-anim"]
    if avd == "CarConnect":
        cmd.extend(["-writable-system", "-gpu", "auto", "-allow-host-audio"])
    subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
    )
    if not wait_boot(adb, serial, boot_timeout):
        raise SystemExit("Mo AVD %s tai %s nhung khong boot xong trong %ss." % (avd, serial, int(boot_timeout)))
    print("Da mo AVD %s tai %s" % (avd, serial), file=sys.stderr)
    return serial


# ---- device lock -------------------------------------------------------------------------------------
LOCK_BUSY_EXIT = 75  # EX_TEMPFAIL: the device lock was not obtained in time; retry later
LOCK_WAIT_DEFAULT = 300.0
LOCK_WAIT_MAX = 3600.0
LOCK_POLL_S = 0.2


class DeviceLockBusy(Exception):
    """Another capture still holds the device after the whole wait."""


def lock_wait_seconds() -> float:
    """PROOF_DEVICE_LOCK_WAIT: seconds to wait for a busy device. Garbage, nan, inf and negatives mean the default."""
    try:
        value = float(os.environ.get("PROOF_DEVICE_LOCK_WAIT"))
    except (TypeError, ValueError):
        return LOCK_WAIT_DEFAULT
    if value != value or value < 0 or value == float("inf"):
        return LOCK_WAIT_DEFAULT
    return min(value, LOCK_WAIT_MAX)


def device_lock_enabled(flag_off: bool = False) -> bool:
    if flag_off:
        return False
    return os.environ.get("PROOF_DEVICE_LOCK", "1").strip().lower() not in ("0", "off", "false", "no")


def device_lock_dir() -> Path:
    # Not TMPDIR: that differs per user session/sandbox, and the lock only works when every agent on the
    # machine agrees on one path. PROOF_DEVICE_LOCK_DIR is for tests; nothing else reads it.
    override = os.environ.get("PROOF_DEVICE_LOCK_DIR")
    if override:
        return Path(override)
    return Path.home() / ".config" / "universal-agent-devkit" / "device-locks"


def lock_path(directory: Path, kind: str, name: str) -> Path:
    digest = hashlib.sha256(("%s:%s" % (kind, name)).encode("utf-8", "backslashreplace")).hexdigest()[:32]
    return Path(directory) / (digest + ".lock")


def _clean(value, limit: int = 120) -> str:
    """Text from another process, safe to print: control characters and escapes become '?'."""
    return "".join(ch if ch.isprintable() else "?" for ch in str(value))[:limit]


def _label(kind: str, name: str) -> str:
    return ("AVD %s" if kind == "avd" else "serial %s") % _clean(name, 80)


def _open_lock(directory: Path, path: Path) -> int:
    """Open the lock file (created if missing) in a private directory; OSError when it cannot be trusted. The
    holder later writes its identity INTO this file, so it must be a regular file with no other name."""
    os.makedirs(str(directory), mode=0o700, exist_ok=True)  # a symlinked dir is followed; two creators may race
    st = os.stat(str(directory))
    if st.st_uid != os.geteuid() or st.st_mode & 0o022:
        raise OSError(errno.EACCES, "lock dir %s is not private (owner or mode %o)" % (directory, stat.S_IMODE(st.st_mode)))
    # O_NOFOLLOW: a planted symlink must not be written through. O_NONBLOCK: a planted FIFO must not hang us.
    fd = os.open(str(path), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:  # a hardlink would let the identity write truncate another file
        os.close(fd)
        raise OSError(errno.EINVAL, "%s is not a regular file with a single name" % path)
    return fd


def _holder_text(fd: int) -> str:
    """Who holds the lock, from the identity the holder wrote. For the message only, never for a decision."""
    try:
        info = json.loads(os.pread(fd, 4096, 0).decode("utf-8", "replace"))
    except (OSError, ValueError):
        info = None
    if not isinstance(info, dict):
        return "khong doc duoc nguoi giu khoa"
    since = ""
    try:
        started = float(info.get("started"))
        since = ", tu %s (%d giay truoc)" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(started)), max(0, int(time.time() - started)))
    except (TypeError, ValueError, OverflowError, OSError):
        pass
    return "pid %s, session %s, cwd %s%s" % (_clean(info.get("pid"), 12), _clean(info.get("session") or "-", 60),
                                              _clean(info.get("cwd") or "?", 240), since)


def _write_identity(fd: int, kind: str, name: str) -> None:
    try:
        cwd = os.getcwd()
    except OSError:
        cwd = "?"
    session = os.environ.get("DEVKIT_SESSION_ID") or os.environ.get("CLAUDE_CODE_SESSION_ID") or os.environ.get("CLAUDE_SESSION_ID") or ""
    data = json.dumps({"pid": os.getpid(), "session": session, "cwd": cwd, "started": time.time(),
                       "key": "%s:%s" % (kind, name)}).encode("utf-8")
    try:
        os.ftruncate(fd, 0)
        os.pwrite(fd, data, 0)
    except OSError as exc:  # the lock is held either way; only the message loses its detail
        print("Canh bao: khong ghi duoc nguoi giu khoa thiet bi: %s" % _clean(exc), file=sys.stderr)


def _unlocked(kind: str, name: str, why) -> tuple:
    print("Canh bao: khong dung duoc khoa thiet bi cho %s (%s) — chup khong khoa nhu truoc; "
          "hai phien cung may co the chup de len nhau." % (_label(kind, name), _clean(why, 200)), file=sys.stderr)
    return None, 0.0


def _acquire_lock(kind: str, name: str, wait_s: float) -> tuple:
    """(fd, seconds waited) with the flock held; (None, 0.0) after a warning when the lock cannot be used at all."""
    if fcntl is None:
        return _unlocked(kind, name, "fcntl.flock khong co tren he nay")
    try:
        directory = device_lock_dir()
        fd = _open_lock(directory, lock_path(directory, kind, name))
    except (OSError, RuntimeError, ValueError) as exc:
        return _unlocked(kind, name, exc)
    announced = False
    start = time.monotonic()
    deadline = start + wait_s
    try:
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as exc:
                if exc.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):
                    os.close(fd)
                    return _unlocked(kind, name, exc)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise DeviceLockBusy(
                    "Thiet bi (%s) dang duoc phien khac dung de chup (%s). Da cho %d giay. Chay lai sau, hoac tang "
                    "PROOF_DEVICE_LOCK_WAIT (giay, mac dinh 300), hoac tat khoa bang --no-device-lock / "
                    "PROOF_DEVICE_LOCK=0 (khi do hai phien co the chup de len nhau)."
                    % (_label(kind, name), _holder_text(fd), int(time.monotonic() - start)))
            if not announced:
                announced = True
                print("Cho khoa thiet bi cho %s: %s. Cho toi da %d giay (PROOF_DEVICE_LOCK_WAIT)." % (
                    _label(kind, name), _holder_text(fd), int(remaining)), file=sys.stderr)
            time.sleep(min(LOCK_POLL_S, remaining))
        _write_identity(fd, kind, name)
        return fd, time.monotonic() - start
    except BaseException:  # DeviceLockBusy, Ctrl-C, anything: never leave the fd (and the lock) behind
        os.close(fd)
        raise


@contextlib.contextmanager
def device_lock(kind: str, name: str, wait_s: float):
    """Hold the flock for (kind, name) until the block ends, whatever ends it. Yields the seconds spent waiting
    for it (0.0 when free). Not re-entrant: a second hold of the same key in one process waits, then fails (75)."""
    fd, spent = _acquire_lock(kind, name, wait_s)
    try:
        yield spent
    finally:
        if fd is not None:
            os.close(fd)  # closing the descriptor drops the flock; a killed process loses it the same way


def locked_device(locks, args, plan: dict, emulator, use_lock: bool) -> str:
    """Boot the planned AVD if need be, take the serial lock (in `locks`) and return the serial.
    One wait budget covers both locks; a boot plan locks the AVD first and re-reads adb devices after."""
    budget = lock_wait_seconds()
    serial = plan.get("serial")
    if plan["action"] == "boot":
        denied = set(plan.get("denied") or [])
        if use_lock:
            budget -= locks.enter_context(device_lock("avd", plan["avd"], budget))
            plan["devices"] = adb_devices(args.adb)  # whoever held the AVD before us may have booted it
        serial = boot_avd(args.adb, emulator, plan["avd"], plan["devices"], next_port(plan["devices"], args.port, denied),
                          args.boot_timeout, denied)
        if serial in denied:  # the denylist outranks the AVD fallback: refuse before any lock or capture on it
            raise SystemExit("Serial %s nam trong denylist — khong chup." % serial)
    if use_lock:
        locks.enter_context(device_lock("serial", serial, max(budget, 0.0)))
    return serial


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Chup anh nghiem thu, mo may ao neu khong co device.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Khoa thiet bi (adb): moi serial mot khoa, giu quanh cac lenh chup (mo AVD, kiem tra man hinh, screencap;\n"
               "khong gom cai build); phien thu hai cung serial cho toi da PROOF_DEVICE_LOCK_WAIT giay (tong, mac dinh 300,\n"
               "toi da 3600) roi thoat 75.\n"
               "Tat: --no-device-lock hoac PROOF_DEVICE_LOCK=0. Thu muc khoa: ~/.config/universal-agent-devkit/device-locks\n"
               "(PROOF_DEVICE_LOCK_DIR chi dung cho test). Exit: 0 chup xong, 1 that bai/tu choi, 2 sai tham so, 75 khong lay duoc khoa.")
    parser.add_argument("--project", default=".")
    parser.add_argument("--adb", default=os.environ.get("PROOF_ADB") or "adb")
    parser.add_argument("--emulator", default=os.environ.get("PROOF_EMULATOR") or "")
    parser.add_argument("--xcrun", default=os.environ.get("PROOF_XCRUN") or "xcrun")
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--connect-timeout", type=float, default=5)
    parser.add_argument("--boot-timeout", type=float, default=180)
    parser.add_argument("--port", type=int, default=5554)
    parser.add_argument("--no-device-lock", action="store_true", help="do not serialise captures of the same device")
    args = parser.parse_args(argv)
    project = Path(args.project).resolve()
    emulator = args.emulator or find_emulator()
    plan = resolve(project, args.adb, emulator, args.connect_timeout, args.xcrun)
    if args.plan_only:
        printable = {k: plan[k] for k in ("action", "serial", "avd", "message") if k in plan}
        print(json.dumps(printable, ensure_ascii=False))
        return 0 if plan["action"] != "fail" else 1
    if plan["action"] == "fail":
        print(plan["message"], file=sys.stderr)
        return 1
    serial = plan.get("serial")
    if plan["action"] == "3d":
        dest = project / "reports" / ("proof-%s.png" % time.strftime("%Y%m%d-%H%M%S"))
        _base = Path(__file__).resolve().parent.parent
        script = _base / "scripts" / "testing" / "capture_3d_proof.py"
        if not script.is_file():
            script = _base / "scripts" / "capture_3d_proof.py"
        res = subprocess.run([sys.executable, str(script), "--project", str(project), "--output", str(dest)],
                             capture_output=True, text=True)
        if res.returncode == 0 and dest.is_file():
            print("serial: %s" % serial)
            print("file: %s" % dest)
            return 0
        else:
            print("Chup anh 3D proof that bai: %s" % res.stderr, file=sys.stderr)
            return 1
    if plan["action"] == "simctl":
        dest = project / "reports" / ("proof-%s.png" % time.strftime("%Y%m%d-%H%M%S"))
        simctl_capture(args.xcrun, serial, dest, 60)
        print("serial: %s" % serial)
        print("file: %s" % dest)
        return 0
    if plan["action"] == "shell":
        dest = project / "reports" / ("proof-%s.png" % time.strftime("%Y%m%d-%H%M%S"))
        run_shell_proof(project, plan["command"], dest, float(plan.get("timeout") or 60))
        print("serial: %s" % (plan.get("serial") or "shell"))
        print("file: %s" % dest)
        return 0
    if plan["action"] == "boot" and not emulator:
        print("Khong tim thay binary emulator de mo AVD %s." % plan["avd"], file=sys.stderr)
        return 1
    # The device is chosen and the denylist applied (resolve): only now is a lock taken. A boot plan has no
    # serial yet, so it locks the AVD first and the serial it ends up with after.
    try:
        with contextlib.ExitStack() as locks:
            serial = locked_device(locks, args, plan, emulator, device_lock_enabled(args.no_device_lock))
            wake = wakefulness(args.adb, serial)
            if wake and wake != "Awake":
                print("Man hinh serial %s dang %s (dumpsys power: mWakefulness) — khong chup. "
                      "Bat man hinh, mo man can chung minh roi chay lai." % (serial, wake), file=sys.stderr)
                return 1
            stamp = time.strftime("%Y%m%d-%H%M%S")
            dest = project / "reports" / ("proof-%s.png" % stamp)
            screencap(args.adb, serial, dest, 60)
            print("serial: %s" % serial)
            print("file: %s" % dest)
            return 0
    except DeviceLockBusy as exc:
        print(exc, file=sys.stderr)
        return LOCK_BUSY_EXIT


if __name__ == "__main__":
    sys.exit(main())
