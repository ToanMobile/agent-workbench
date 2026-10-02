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

iOS: provider type `simctl` or a declared `udid`, or profile `ios`, screenshots the one
Booted simulator (`xcrun simctl list devices -j`) with `xcrun simctl io <udid> screenshot`;
none or several Booted is a failure, never an Android fallback. With no declared provider
(no serial/avd) and a profile that is not android/automotive, a single Booted simulator is
used before adb; several Booted ones leave it to adb.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import zlib
from pathlib import Path

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


def next_port(devices: list, start: int = 5554) -> int:
    port = int(start) if int(start) % 2 == 0 else int(start) + 1
    used = {d["serial"] for d in devices}
    for _ in range(16):
        if "emulator-%d" % port not in used:
            return port
        port += 2
    return port


def _host_port(serial: str) -> bool:
    return bool(re.match(r"^[^:\s]+:\d+$", serial or ""))


def plan_target(configured, devices, denied, avd, connect_tried: bool) -> dict:
    """Decide the next step. Never returns a serial that is offline or denied."""
    deny = set(denied or [])
    listed = list(devices or [])
    online = [d for d in listed if d["state"] == "device" and d["serial"] not in deny]
    if configured and configured in deny:
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
    plan = plan_target(configured, devices, denied, avd, False)
    if plan["action"] == "connect":
        try:
            run([adb, "connect", plan["serial"]], connect_timeout)
        except subprocess.TimeoutExpired:
            pass
        devices = adb_devices(adb)
        plan = plan_target(configured, devices, denied, avd, True)
    plan["devices"] = devices
    plan["denied"] = sorted(denied)
    return plan


def boot_avd(adb: str, emulator: str, avd: str, devices: list, port: int, boot_timeout: float) -> str:
    for dev in devices:
        if dev["state"] != "device" or not dev["serial"].startswith("emulator-"):
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


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Chup anh nghiem thu, mo may ao neu khong co device.")
    parser.add_argument("--project", default=".")
    parser.add_argument("--adb", default=os.environ.get("PROOF_ADB") or "adb")
    parser.add_argument("--emulator", default=os.environ.get("PROOF_EMULATOR") or "")
    parser.add_argument("--xcrun", default=os.environ.get("PROOF_XCRUN") or "xcrun")
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--connect-timeout", type=float, default=5)
    parser.add_argument("--boot-timeout", type=float, default=180)
    parser.add_argument("--port", type=int, default=5554)
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
    if plan["action"] == "boot":
        if not emulator:
            print("Khong tim thay binary emulator de mo AVD %s." % plan["avd"], file=sys.stderr)
            return 1
        serial = boot_avd(args.adb, emulator, plan["avd"], plan["devices"], next_port(plan["devices"], args.port), args.boot_timeout)
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


if __name__ == "__main__":
    sys.exit(main())
