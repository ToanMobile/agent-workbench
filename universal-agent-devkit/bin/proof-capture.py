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
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

PNG_SIG = b"\x89PNG\r\n\x1a\n"
MIN_BYTES = 8192
CAR_AVD = re.compile(r"car|auto", re.I)
PHONE_AVD = re.compile(r"phone|pixel", re.I)


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


def screencap(adb: str, serial: str, dest: Path, timeout_s: float) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    res = subprocess.run(
        [adb, "-s", serial, "exec-out", "screencap", "-p"],
        capture_output=True, timeout=timeout_s,
    )
    data = res.stdout or b""
    dest.write_bytes(data)
    if res.returncode != 0 or not data.startswith(PNG_SIG):
        tail = (res.stderr or b"").decode("utf-8", "replace")[:400]
        raise SystemExit("Chup anh that bai (exit %s) serial %s: %s" % (res.returncode, serial, tail))
    if dest.stat().st_size <= MIN_BYTES:
        raise SystemExit("Anh %s chi %d byte — man hinh trong hoac chua kip ve." % (dest, dest.stat().st_size))


def resolve(project: Path, adb: str, emulator: str | None, connect_timeout: float) -> dict:
    proof = load_proof(project)
    provider = proof["provider"]
    kind = provider.get("type")
    if kind not in (None, "adb"):
        return {
            "action": "fail",
            "message": "Provider %s co type %s, khong phai adb. Dung provider do de chup. Khong mo may ao Android." % (proof.get("name"), kind),
        }
    configured = provider.get("serial") or None
    declared_avd = provider.get("avd") or None
    avd = pick_avd(list_avds(emulator), declared_avd, read_profile(project))
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
    subprocess.Popen(
        [emulator, "-avd", avd, "-port", str(port), "-no-boot-anim"],
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
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--connect-timeout", type=float, default=5)
    parser.add_argument("--boot-timeout", type=float, default=180)
    parser.add_argument("--port", type=int, default=5554)
    args = parser.parse_args(argv)
    project = Path(args.project).resolve()
    emulator = args.emulator or find_emulator()
    plan = resolve(project, args.adb, emulator, args.connect_timeout)
    if args.plan_only:
        printable = {k: plan[k] for k in ("action", "serial", "avd", "message") if k in plan}
        print(json.dumps(printable, ensure_ascii=False))
        return 0 if plan["action"] != "fail" else 1
    if plan["action"] == "fail":
        print(plan["message"], file=sys.stderr)
        return 1
    serial = plan.get("serial")
    if plan["action"] == "boot":
        if not emulator:
            print("Khong tim thay binary emulator de mo AVD %s." % plan["avd"], file=sys.stderr)
            return 1
        serial = boot_avd(args.adb, emulator, plan["avd"], plan["devices"], next_port(plan["devices"], args.port), args.boot_timeout)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = project / "reports" / ("proof-%s.png" % stamp)
    screencap(args.adb, serial, dest, 60)
    print("serial: %s" % serial)
    print("file: %s" % dest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
