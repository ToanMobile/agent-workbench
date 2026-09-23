#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# hardware_safety_gate.sh — Physical Hardware & Embedded Device Brick Protection
#
# Intercepts dangerous shell commands that risk bricking physical test devices,
# automotive IVI head-units, or embedded Android/Linux boards.
#
# BLOCKS (exit 2) when detecting:
#   • adb [-s SERIAL|-d|-e|-t ID|-H|-P …] remount / disable-verity / root+remount
#   • adb shell mount … rw … /system|/vendor|/product  (any flag order)
#   • dd … of=/dev/…   (any raw block/char device)
#   • fastboot [-s SERIAL …] flash|flashall|erase|format|update|oem unlock|flashing unlock
#   • rm with recursive+force flags in any spelling (-rf, -fr, -r -f, --recursive
#     --force) on /system, /vendor, /boot, /product, /data or /
#   • adb shell pm uninstall|disable(-user)|hide of a system package (android,
#     com.android.*, com.google.android.*, vendor namespaces)
#   • iOS signing & simulators: fastlane match nuke, security delete-keychain|
#     identity|certificate, rm of provisioning profiles / keychains,
#     xcrun simctl erase|delete all
#   • any adb command that reaches a device outside the device policy — a
#     developer's personal phone plugged in next to the test rig. Denylist /
#     allowlist, one serial per line (# comments) or comma/space separated in env:
#       ADB_DENY_SERIALS   · ~/.config/universal-agent-devkit/adb-denylist · <repo>/.adb-denylist
#       ADB_ALLOW_SERIALS  · ~/.config/universal-agent-devkit/adb-allowlist · <repo>/.adb-allowlist
#     (non-empty allowlist = every other serial is refused). Personal serials go in
#     the per-user file, never in the repo. With no -s, the serial adb would pick
#     (-d/-e/-t/ANDROID_SERIAL/the only device) is asked from `adb get-serialno`;
#     an unresolvable target ($VAR serial, adb timeout) is refused. Host-only
#     subcommands (devices, version, connect, kill-server …) are never checked.
#
# FAIL-CLOSED: malformed JSON or missing python3 → exit 2 (the command is not
# allowed through unexamined). Empty stdin → exit 0 (no tool call to judge).
#
# Protocol: stdin JSON; exit 2 blocks (stderr -> Agent); exit 0 allows.
# Escape hatches: HARDWARE_SAFETY_GATE=0 (disable), HARDWARE_OVERRIDE=1 (one-off).
# ─────────────────────────────────────────────────────────────────────────────
set -u

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
if [ "${HARDWARE_SAFETY_GATE:-1}" = "0" ] || [ "${HARDWARE_OVERRIDE:-0}" = "1" ]; then
  if mkdir -p "${LOG_DIR}" 2>/dev/null; then
    [ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
    echo "[$(date +%Y-%m-%dT%H:%M:%S)] HARDWARE_SAFETY_GATE=${HARDWARE_SAFETY_GATE:-1} HARDWARE_OVERRIDE=${HARDWARE_OVERRIDE:-0} — gate bypassed" \
      >> "${LOG_DIR}/hardware_safety_gate.log" 2>/dev/null
  fi
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "🛑 [HARDWARE SAFETY GATE] cần python3 để phân tích lệnh — chặn để an toàn (HARDWARE_SAFETY_GATE=0 để tắt)." >&2
  exit 2
fi

REPO_ROOT="${REPO_ROOT}" python3 -c '
import sys, json, re, os, shlex, shutil, subprocess

raw = sys.stdin.read()
if not raw.strip():
    sys.exit(0)

try:
    data = json.loads(raw)
    inp = data.get("tool_input") or data.get("input") or {}
    cmd = inp.get("command") or inp.get("CommandLine") or ""
except Exception:
    sys.stderr.write("🛑 [HARDWARE SAFETY GATE] không đọc được JSON đầu vào — chặn để an toàn.\n")
    sys.exit(2)
if not isinstance(cmd, str):
    sys.stderr.write("🛑 [HARDWARE SAFETY GATE] tool_input.command không phải chuỗi — chặn để an toàn.\n")
    sys.exit(2)

# Options adb/fastboot accept before the subcommand (with or without a value).
ADB_OPTS = r"(?:\s+(?:-[sHPtL]\s+\S+|-[adeU]|--\S+(?:\s+\S+)?))*"
FB_OPTS = r"(?:\s+(?:-[sSciopn]\s+\S+|-w|-u|--\S+(?:=\S+)?))*"
SYS_PARTS = r"/(?:system|vendor|boot|product|odm|data|persist|efs)?(?:/|\s|$|[;&|])"

PATTERNS = [
    (r"\badb" + ADB_OPTS + r"\s+(?:remount|disable-verity|enable-verity)\b",
     "adb remount/disable-verity (nguy cơ phá dm-verity gây brick thiết bị)"),
    (r"\bmount\b[^;&|\n]*\brw\b[^;&|\n]*/(?:system|vendor|product|odm)\b",
     "mount phân vùng hệ thống ở chế độ rw"),
    (r"\bmount\b[^;&|\n]*/(?:system|vendor|product|odm)\b[^;&|\n]*\brw\b",
     "mount phân vùng hệ thống ở chế độ rw"),
    (r"\bdd\b[^;&|\n]*\bof=/dev/", "dd ghi thẳng vào thiết bị khối /dev/…"),
    (r"\bfastboot" + FB_OPTS + r"\s+(?:flash|flashall|erase|format|update)\b",
     "fastboot flash/erase/format (can thiệp bootloader thiết bị thật)"),
    (r"\bfastboot" + FB_OPTS + r"\s+(?:oem|flashing)\s+(?:unlock|lock)\b",
     "fastboot oem/flashing unlock (xoá sạch thiết bị)"),
    # Removing or disabling a system package (SystemUI, the launcher, GMS …) for the
    # user can leave the device unable to boot to a usable screen.
    (r"\badb" + ADB_OPTS + r"\s+shell\s+(?:[^;&|\n]*\s)?pm\s+(?:uninstall|disable-user|disable|hide)\b[^;&|\n]*"
     r"\s(?:android|com\.android\.[\w.]+|com\.google\.android\.[\w.]+|com\.sec\.[\w.]+|com\.samsung\.[\w.]+"
     r"|com\.qualcomm\.[\w.]+|com\.mediatek\.[\w.]+)(?=\s|$|[;&|])",
     "gỡ/tắt app hệ thống Android (pm uninstall/disable) — thiết bị có thể không vào được màn hình"),
    # iOS signing identity and device fleet: not recoverable from the repo.
    (r"\bfastlane\b[^;&|\n]*\bmatch\s+nuke\b", "fastlane match nuke — thu hồi TOÀN BỘ chứng chỉ ký của team"),
    (r"\bsecurity\s+delete-(?:keychain|identity|certificate)\b", "security delete-keychain/identity — xoá chứng chỉ/khoá ký"),
    (r"\brm\b[^;&|\n]*(?:MobileDevice/Provisioning|Library/Keychains)", "xoá provisioning profiles / keychain"),
    (r"\bxcrun\s+simctl\s+(?:erase|delete)\s+all\b", "xcrun simctl erase/delete all — xoá sạch mọi simulator"),
]

def rm_hits(text):
    """rm with both recursive and force flags on a system partition or /."""
    for seg in re.split(r"[;&|\n]+", text):
        toks = seg.split()
        for i, t in enumerate(toks):
            if t.rsplit("/", 1)[-1] != "rm":
                continue
            args = toks[i + 1:]
            flags = "".join(a[1:] for a in args if a.startswith("-") and not a.startswith("--"))
            longs = {a for a in args if a.startswith("--")}
            rec = "r" in flags or "R" in flags or "--recursive" in longs
            force = "f" in flags or "--force" in longs
            targets = [a for a in args if not a.startswith("-")]
            if rec and force and any(re.match(SYS_PARTS, a + " ") for a in targets):
                return True
    return False

label = None
for pat, lab in PATTERNS:
    if re.search(pat, cmd):
        label = lab
        break
if label is None and rm_hits(cmd):
    label = "rm -rf phân vùng hệ thống cốt lõi"


# ── Device policy: which serial may adb touch ─────────────────────────────────
def serial_set(env_name, file_name):
    out = {t for t in re.split(r"[\s,;]+", os.environ.get(env_name, "")) if t}
    cfg = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
                       "universal-agent-devkit", "adb-" + file_name)
    for path in (cfg, os.path.join(os.environ.get("REPO_ROOT", "."), ".adb-" + file_name)):
        try:
            with open(path, encoding="utf-8") as fh:
                for line in fh:
                    out.update(t for t in re.split(r"[\s,;]+", line.split("#", 1)[0]) if t)
        except OSError:
            pass
    return out

ADB_HOST_ONLY = {"devices", "version", "help", "start-server", "kill-server", "connect",
                 "disconnect", "pair", "mdns", "keygen", "host-features", "server", "nodaemon"}
ADB_VALUE_OPTS = {"-s", "-t", "-H", "-P", "-L"}
ADB_WRAPPERS = {"sudo", "env", "command", "exec", "nohup", "time", "timeout", "xargs"}

def adb_calls(text):
    """(adb executable token, selection options, subcommand, ANDROID_SERIAL) per adb call."""
    for seg in re.split(r"[;&|\n]+|\$\(|`", text):
        try:
            toks = shlex.split(seg)
        except ValueError:
            toks = seg.split()
        env_serial = os.environ.get("ANDROID_SERIAL", "")
        # Only the word in command position (after VAR=… and sudo/env/timeout N …):
        # `grep adb notes.txt` is not an adb call.
        i = 0
        while i < len(toks) and (re.match(r"^\w+=", toks[i]) or toks[i] in ADB_WRAPPERS
                                 or (i > 0 and toks[i - 1] in ADB_WRAPPERS and re.match(r"^(-\S*|\d+\w?)$", toks[i]))):
            if toks[i].startswith("ANDROID_SERIAL="):
                env_serial = toks[i].split("=", 1)[1]
            i += 1
        if i < len(toks) and os.path.basename(toks[i]) in ("bash", "sh", "zsh") and "-c" in toks[i:]:
            k = toks.index("-c", i)
            if k + 1 < len(toks):
                yield from adb_calls(toks[k + 1])
            continue
        if i >= len(toks) or os.path.basename(toks[i]) not in ("adb", "adb.exe"):
            continue
        opts, j = [], i + 1
        while j < len(toks) and toks[j].startswith("-"):
            if toks[j] in ADB_VALUE_OPTS and j + 1 < len(toks):
                opts += toks[j:j + 2]; j += 2
            else:
                opts.append(toks[j]); j += 1
        yield toks[i], opts, (toks[j] if j < len(toks) else ""), env_serial

def target_serial(exe, opts, env_serial):
    """(serial, None) · (None, None) when adb itself would find no single target
    (the command then fails on its own) · (None, why) when it cannot be resolved."""
    if "-s" in opts:
        s = os.path.expandvars(opts[opts.index("-s") + 1])
        return (None, "serial " + s + " không xác định được") if "$" in s else (s, None)
    if "$" in env_serial:
        return None, "ANDROID_SERIAL=" + env_serial + " không xác định được"
    adb = exe if "/" in exe and os.access(exe, os.X_OK) else shutil.which("adb")
    if not adb:
        return None, None
    env = dict(os.environ)
    if env_serial:
        env["ANDROID_SERIAL"] = env_serial
    try:
        r = subprocess.run([adb] + opts + ["get-serialno"], capture_output=True, text=True,
                           timeout=8, env=env)
    except (OSError, subprocess.SubprocessError):
        return None, "adb get-serialno không trả lời"
    s = r.stdout.strip()
    return (s, None) if r.returncode == 0 and s and s != "unknown" else (None, None)

def device_violation(text):
    deny, allow = serial_set("ADB_DENY_SERIALS", "denylist"), serial_set("ADB_ALLOW_SERIALS", "allowlist")
    if not deny and not allow:
        return None
    for exe, opts, sub, env_serial in adb_calls(text):
        if not sub or sub in ADB_HOST_ONLY:
            continue
        serial, why = target_serial(exe, opts, env_serial)
        if why:
            return "không xác định được thiết bị đích (" + why + ") — ghi rõ adb -s <SERIAL>"
        if serial and serial in deny:
            return "thiết bị " + serial + " nằm trong denylist (máy cá nhân / cấm đụng)"
        if serial and allow and serial not in allow:
            return "thiết bị " + serial + " không có trong allowlist"
    return None

if label is None:
    dev = device_violation(cmd)
    if dev:
        sys.stderr.write("\n🛑 [HARDWARE SAFETY GATE REJECTED]\n")
        sys.stderr.write("Lệnh adb bị chặn vì chạm thiết bị ngoài chính sách thiết bị:\n")
        sys.stderr.write(f"  • {dev}\n")
        sys.stderr.write(f"  • Lệnh: {cmd}\n\n")
        sys.stderr.write("Chính sách: ADB_DENY_SERIALS / ADB_ALLOW_SERIALS, ~/.config/universal-agent-devkit/adb-{denylist,allowlist}, <repo>/.adb-{denylist,allowlist}.\n")
        sys.exit(2)

if label:
    sys.stderr.write("\n🛑 [HARDWARE SAFETY GATE REJECTED]\n")
    sys.stderr.write("Lệnh bị chặn vì có nguy cơ làm hỏng phần cứng vật lý (device bricking):\n")
    sys.stderr.write(f"  • Mẫu vi phạm: {label}\n")
    sys.stderr.write(f"  • Lệnh: {cmd}\n\n")
    sys.stderr.write("Nếu chắc chắn đang ở môi trường giả lập an toàn, đặt HARDWARE_OVERRIDE=1 để bỏ qua.\n")
    sys.exit(2)
sys.exit(0)
'
