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
#   • (2026-09-23) the same recursive+force rm on the project root, a top-level folder
#     of the project, or any path outside it. Allowed: build outputs under the project
#     (build/ dist/ out/ target/ node_modules/ .gradle/ Library/ Temp/ obj/ bin/ …,
#     unless git tracks files there — then it is source), paths inside /tmp or $TMPDIR,
#     deeper project paths (src/main/old), and a single existing file. Relative paths
#     start at the payload's cwd and follow `cd` (a `cd` that may not run keeps the old
#     directory in play too); an unresolvable $VAR / $(…) target is refused.
#   • adb shell pm uninstall|disable(-user)|hide of a system package (android,
#     com.android.*, com.google.android.*, vendor namespaces)
#   • iOS signing & simulators: fastlane match nuke, security delete-keychain|
#     identity|certificate, rm of provisioning profiles / keychains,
#     xcrun simctl erase|delete all
#   • irreversible release / infra / data (AGENTS.md §5.1 Gate 2 c): npm|pnpm|yarn
#     publish, vercel|netlify --prod, firebase deploy, prisma migrate reset, rails
#     db:drop, DROP DATABASE|TABLE / TRUNCATE via a database CLI, MongoDB drop,
#     redis-cli FLUSHALL, kubectl delete namespace|pv|pvc|--all, terraform|pulumi
#     destroy, helm uninstall, docker volume removal, aws s3 rm --recursive
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
#   • the same device checks through replicant-mcp (PreToolUse `mcp__replicant-mcp__.*`;
#     tool names and schemas from replicant-mcp 1.6.7 dist/tools/*.js). Each call is
#     turned into the adb command it runs: adb-shell {command} → `adb shell <command>`,
#     adb-app uninstall|clear-data|stop|launch|install|list → `adb shell pm …` / `adb
#     install`, adb-device select|wait|properties {deviceId} → `adb -s <deviceId> …`,
#     adb-logcat / ui-* → a device call. adb-shell and adb-app carry no device field:
#     they run on the server's selected device or the only online one — the device
#     `adb get-serialno` names, as for a bare `adb`. `adb-device list` auto-selects the
#     only online device, so it is checked too. gradle-*, emulator-device, cache, rtfm
#     never reach a device and are allowed. A replicant tool this map does not know
#     is checked through its command-like string fields and serial/deviceId field.
#     replicant's own process-runner blocks `rm -rf /system`, dd, su and format, but
#     not `mount … rw /system`, `pm uninstall <system package>` or the device policy.
#
# FAIL-CLOSED: malformed JSON or missing python3 → exit 2 (the command is not
# allowed through unexamined). Empty stdin → exit 0 (no tool call to judge).
#
# Protocol: stdin JSON; exit 2 blocks (stderr -> Agent); exit 0 allows.
# Escape hatches: HARDWARE_SAFETY_GATE=0 (disable), HARDWARE_OVERRIDE=1 (one-off).
# ─────────────────────────────────────────────────────────────────────────────
set -u

INPUT="$(cat)"

# ── Fast path (2026-09-23): most Bash calls (ls, cat, npm test, ./gradlew …) contain
# nothing this gate reacts to, and starting python3 for them cost ~70–90 ms each.
# Bash-only: take the command value from the JSON with a builtin regex and allow it
# at once when it has NO backslash / quote / $ / backtick / glob char (anything that
# could hide a word from this check) and none of the trigger words (case-insensitive).
# Everything else — and any payload the regex cannot read — goes to the full parser.
# An MCP payload never takes it: its "command" is a DEVICE shell command (adb-shell).
fast_allow() { # $1 = trigger ERE
  local re='"command"[[:space:]]*:[[:space:]]*"([^"\\]*)"' c bash_re='"tool_name"[[:space:]]*:[[:space:]]*"Bash"'
  [[ $INPUT =~ $bash_re ]] || return 1
  [[ $INPUT =~ $re ]] || return 1
  c="${BASH_REMATCH[1]}"
  case "$c" in ""|*[\'\$\`\*\?\[\]]*) return 1 ;; esac
  shopt -s nocasematch
  if [[ $c =~ $1 ]]; then shopt -u nocasematch; return 1; fi
  shopt -u nocasematch
  return 0
}
fast_allow 'adb|fastboot|dd|mount|rm|fastlane|security|xcrun|simctl|eval|flash|publish|vercel|netlify|firebase|prisma|db:|drop|truncate|flush|kubectl|terraform|tofu|pulumi|helm|docker|s3' && exit 0

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

printf '%s' "$INPUT" | REPO_ROOT="${REPO_ROOT}" python3 -c '
import sys, json, re, os, fnmatch, shlex, shutil, subprocess

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

# ── replicant-mcp: the adb command each tool runs (replicant-mcp 1.6.7 dist/tools) ──
tool = str(data.get("tool_name") or "")
MCP = tool.startswith("mcp__")
REPLICANT_HOST_ONLY = {"gradle-build", "gradle-test", "gradle-list", "gradle-get-details",
                       "emulator-device", "cache", "rtfm"}
REPLICANT_APP = {"uninstall": "shell pm uninstall", "clear-data": "shell pm clear",
                 "stop": "shell am force-stop", "launch": "shell monkey -p", "list": "shell pm list packages"}

def mcp_as_adb(tool, inp):
    """The adb command line a replicant-mcp call amounts to ("" = no device touched)."""
    if not tool.startswith("mcp__replicant-mcp__") or not isinstance(inp, dict):
        return ""
    name = tool[len("mcp__replicant-mcp__"):]
    serial = next((v for k, v in inp.items() if isinstance(v, str) and v
                   and re.search(r"serial|device_?id", k, re.I)), "")
    adb = "adb -s " + shlex.quote(serial) if serial else "adb"
    op = inp.get("operation") or ""
    q = lambda v: shlex.quote(v) if isinstance(v, str) and v else ""
    if name in REPLICANT_HOST_ONLY:
        return ""
    if name == "adb-shell":
        return adb + " shell " + str(inp.get("command") or "")
    if name == "adb-app":
        if op == "install":
            return adb + " install " + q(inp.get("apkPath"))
        return " ".join((adb, REPLICANT_APP.get(op, "shell pm"), q(inp.get("packageName"))))
    if name == "adb-device":
        # list auto-selects the only online device; health-check only asks the adb server
        return "" if op == "health-check" else f"{adb} get-state"
    if name in ("adb-logcat", "ui-action", "ui-capture", "ui-query", "ui-find"):
        return f"{adb} get-state"
    # A tool this version does not have: its command-like strings run on the device.
    shells = [v for k, v in inp.items() if isinstance(v, str)
              and k.lower() in ("command", "cmd", "shellcommand", "shell_command", "args")]
    return "; ".join(f"{adb} shell {c}" for c in shells) or f"{adb} get-state"

shown = cmd
if MCP:
    shown = tool + " " + json.dumps(inp, ensure_ascii=False)
    cmd = mcp_as_adb(tool, inp)
    if not cmd:
        sys.exit(0)
# Where a relative path in the command starts: the session cwd Claude (and the bridge)
# send in the payload, else the project root.
CWD = data.get("cwd") if isinstance(data.get("cwd"), str) and os.path.isdir(data.get("cwd")) \
    else os.environ.get("REPO_ROOT", ".")

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
    # Irreversible release / infrastructure / data operations (AGENTS.md §5.1 Gate 2 c):
    # the user runs them, via the `!` prefix, never the agent on its own.
    (r"\b(?:npm|pnpm|yarn|bun)\s+(?:publish|unpublish)\b", "phát hành package lên registry (npm publish)"),
    (r"\b(?:vercel|netlify)\b[^;&|\n]*\s--prod\b", "deploy production (vercel/netlify --prod)"),
    (r"\bfirebase\s+deploy\b", "firebase deploy (lên production)"),
    (r"\bprisma\s+(?:migrate\s+reset|db\s+push\s+[^;&|\n]*--force-reset)\b", "prisma migrate reset — xoá sạch database"),
    (r"\b(?:rails|rake)\s+db:(?:drop|reset|schema:load)\b", "rails db:drop/reset — xoá database"),
    (r"\b(?:psql|mysql|mariadb|sqlite3|cockroach|clickhouse-client|cqlsh)\b[^;&|\n]*\b(?:drop\s+(?:database|schema|table)|truncate\s+(?:table\s+)?\w)",
     "DROP DATABASE/TABLE hoặc TRUNCATE qua CLI database"),
    (r"\bdropDatabase\s*\(|\bdb\.[\w$]+\.drop\s*\(", "MongoDB dropDatabase()/drop()"),
    (r"\bredis-cli\b[^;&|\n]*\bflush(?:all|db)\b", "redis-cli FLUSHALL/FLUSHDB — xoá toàn bộ dữ liệu Redis"),
    (r"\bkubectl\b[^;&|\n]*\bdelete\b[^;&|\n]*(?:\s(?:namespace|namespaces|ns|pv|pvc|persistentvolumes?|persistentvolumeclaims?|crds?|customresourcedefinitions?|nodes?)\b|\s--all\b)",
     "kubectl delete namespace/volume/--all"),
    (r"\b(?:terraform|tofu)\s+(?:destroy\b|apply\b[^;&|\n]*\s-destroy\b)|\bpulumi\s+destroy\b", "terraform/pulumi destroy — xoá hạ tầng"),
    (r"\bhelm\s+(?:uninstall|delete)\b", "helm uninstall — gỡ release khỏi cluster"),
    (r"\bdocker\b[^;&|\n]*(?:\bsystem\s+prune\b[^;&|\n]*--volumes|\bvolume\s+(?:rm|prune)\b|\bcompose\s+down\b[^;&|\n]*\s(?:-v|--volumes)\b)",
     "xoá docker volume (mất dữ liệu)"),
    (r"\baws\s+s3\s+(?:rm\b[^;&|\n]*--recursive|rb\b[^;&|\n]*--force)", "aws s3 rm --recursive / rb --force"),
]

def rm_hits(text):
    """rm with both recursive and force flags on a system partition or /."""
    for seg in re.split(r"[;&|\n]+", text):
        toks = seg.split()
        for i, t in enumerate(toks):
            if t.rsplit("/", 1)[-1].lower() != "rm":
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

# The same command as the shell will run it: quotes removed (a""db → adb) and a globbed
# program name resolved (a?b, /opt/*/fastboot → adb, fastboot). Matched case-insensitively
# too: macOS resolves ADB / Fastboot to the real tools.
TOOLS = ("adb", "fastboot", "dd", "rm", "mount", "fastlane", "security", "xcrun")
def unglob(tok):
    base = tok.rsplit("/", 1)[-1]
    if re.search(r"[*?\[]", base):
        for t in TOOLS:
            if fnmatch.fnmatch(t, base.lower()):
                return t
    return tok
try:
    norm = " ".join(unglob(t) for t in shlex.split(cmd, comments=False, posix=True))
except ValueError:
    norm = cmd
variants = [cmd, norm]

label = None
for pat, lab in PATTERNS:
    if any(re.search(pat, v, re.I) for v in variants):
        label = lab
        break
if label is None and any(rm_hits(v) for v in variants):
    label = "rm -rf phân vùng hệ thống cốt lõi"


# ── Destructive rm in / around the project (Bash only: an MCP adb-shell rm is on the device) ──
BUILD_OUTPUTS = {"build", "dist", "out", "target", "node_modules", ".gradle", ".cxx", ".externalNativeBuild",
                 "Library", "Temp", "Logs", "obj", "bin", ".next", ".nuxt", ".turbo", ".parcel-cache",
                 ".cache", "coverage", ".pytest_cache", "__pycache__", ".dart_tool", "DerivedData", "Pods"}
RM_WRAPPERS = {"sudo", "doas", "env", "command", "builtin", "exec", "nohup", "time", "timeout", "nice",
               "ionice", "stdbuf", "caffeinate", "xargs", "then", "do", "else", "!", "{"}
ROOT = os.path.realpath(os.environ.get("REPO_ROOT", "."))
TMP_ROOTS = {os.path.realpath(t) for t in ("/tmp", os.environ.get("TMPDIR") or "/tmp")}
GLOB = re.compile(r"[*?\[]")

def under(p, d):
    return p != d and p.startswith(d.rstrip(os.sep) + os.sep)

def git_tracks(p):
    try:
        r = subprocess.run(["git", "-C", ROOT, "ls-files", "--", os.path.relpath(p, ROOT)],
                           capture_output=True, text=True, timeout=5)
        return r.returncode == 0 and bool(r.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        return False

def rm_target_problem(t, cwds, env):
    """Why removing target t recursively is refused, or None."""
    orig = t
    if t.startswith("~"):
        t = os.path.expanduser(t)
    t = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), t)
    if "$" in t or "`" in t:
        return f"{orig}: không xác định được đường dẫn ($VAR / lệnh con)"
    glob = bool(GLOB.search(t))
    if glob:  # judged as its directory: rm -rf src/* empties src
        parts = t.split("/")
        k = next(i for i, x in enumerate(parts) if GLOB.search(x))
        t = "/".join(parts[:k]) or ("/" if t.startswith("/") else ".")
    for cwd in ([None] if os.path.isabs(t) else cwds):
        if cwd is None and not os.path.isabs(t):
            return f"{orig}: không biết thư mục hiện tại (cd tới $VAR / lệnh con / popd)"
        p = os.path.normpath(os.path.join(cwd or "/", t))
        # the parent resolved, the last name kept: rm removes a symlink, not its target
        p = os.path.realpath(p) if p == os.sep else os.path.join(os.path.realpath(os.path.dirname(p)), os.path.basename(p))
        if not glob and os.path.lexists(p) and (os.path.islink(p) or not os.path.isdir(p)):
            continue  # a single file
        if p == ROOT:
            return f"{orig}: là thư mục gốc project"
        if under(p, ROOT):
            rel = os.path.relpath(p, ROOT).split(os.sep)
            if any(x in BUILD_OUTPUTS for x in rel):
                if git_tracks(p):
                    return f"{orig}: là build output nhưng git đang track file trong đó (là source)"
                continue
            if len(rel) == 1:
                return f"{orig}: là thư mục cấp 1 của project"
            continue
        if any(under(p, d) for d in TMP_ROOTS):
            continue
        return f"{orig}: nằm ngoài project ({p})"
    return None

def rm_segment_problem(toks, cwds, env, depth):
    """Problem of one simple command, or None."""
    i = 0
    while i < len(toks):
        tk = toks[i]
        if re.match(r"^[A-Za-z_]\w*=", tk):
            k, v = tk.split("=", 1)
            env[k] = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), v)
            i += 1
        elif os.path.basename(tk) in RM_WRAPPERS:
            i += 1
            while i < len(toks) and (toks[i].startswith("-") or re.match(r"^\d+\w?$", toks[i])):
                i += 1
        else:
            break
    if i >= len(toks):
        return None
    prog, rest = os.path.basename(toks[i]), toks[i + 1:]
    if GLOB.search(prog) and fnmatch.fnmatch("rm", prog.lower()):
        prog = "rm"
    if prog in ("bash", "sh", "zsh", "dash", "ksh") and "-c" in rest:
        k = rest.index("-c")
        return rm_problem(rest[k + 1], cwds, depth + 1) if k + 1 < len(rest) else None
    if prog == "eval":
        return rm_problem(" ".join(rest), cwds, depth + 1)
    if prog == "find":
        for j, a in enumerate(rest):
            if a in ("-exec", "-execdir", "-ok", "-okdir"):
                sub = []
                for x in rest[j + 1:]:
                    if x in (";", "+"):
                        break
                    sub.append(x)
                why = rm_segment_problem(sub, cwds, env, depth + 1)
                if why:
                    return why
        return None
    if prog.lower() != "rm":
        return None
    flags, targets, opts_done = "", [], False
    longs = set()
    for a in rest:
        if not opts_done and a == "--":
            opts_done = True
        elif not opts_done and a.startswith("--"):
            longs.add(a)
        elif not opts_done and a.startswith("-") and len(a) > 1:
            flags += a[1:]
        elif a not in ("{}", ""):
            targets.append(a)
    if not (("r" in flags or "R" in flags or "--recursive" in longs) and ("f" in flags or "--force" in longs)):
        return None
    for t in targets:
        why = rm_target_problem(t, cwds, env)
        if why:
            return why
    return None

def rm_problem(text, cwds, depth=0):
    """Walk the command like the shell: `cd` moves the cwd (after `&&` for sure; after
    ; || | & both the old and the new directory stay possible), ( ) restores it."""
    if depth > 5:
        return "lồng lệnh quá sâu để phân tích"
    env = {"HOME": os.path.expanduser("~"), "TMPDIR": os.environ.get("TMPDIR") or "/tmp"}
    # `…` is $(…): the lexer splits "$" from "(", so a target built from one stays "$…"
    # (unresolvable, refused) while the inner command is walked as its own segment.
    text = re.sub(r"`([^`]*)`?", r"$(\1)", text.replace("\\\n", " ").replace("\n", " ; "))
    try:
        lex = shlex.shlex(text, posix=True, punctuation_chars=";&|()")
        lex.whitespace = " \t\r"
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        toks = [x.strip("\"\x27") for x in re.split(r"\s+|([;&|()]+)", text) if x and x.strip()]
    stack, seg, pending = [], [], None
    for tk in toks + [";"]:
        if not set(tk) <= set(";&|()"):
            seg.append(tk)
            continue
        if seg:
            i = 0
            while i < len(seg) and (re.match(r"^[A-Za-z_]\w*=", seg[i]) or seg[i] in RM_WRAPPERS):
                i += 1
            head = os.path.basename(seg[i]) if i < len(seg) else ""
            if head in ("cd", "pushd", "popd"):
                arg = next((a for a in seg[i + 1:] if not a.startswith("-")), "~")
                if head == "popd" or arg == "-" or "$" in arg or GLOB.search(arg):
                    pending = [None]
                else:
                    arg = os.path.expanduser(arg)
                    pending = [os.path.normpath(os.path.join(c, arg)) if c or os.path.isabs(arg) else None
                               for c in cwds]
            else:
                why = rm_segment_problem(seg, cwds, env, depth)
                if why:
                    return why
            for tok_seg in seg:  # "$(…)" / `…` inside a quoted word runs too
                if "(" in tok_seg and depth < 5:
                    why = rm_problem(tok_seg.split("(", 1)[1].rstrip(")"), cwds, depth + 1)
                    if why:
                        return why
        if pending is not None:
            cwds = list(dict.fromkeys(pending if tk == "&&" else cwds + pending))
            pending = None
        if "(" in tk:
            stack.append(cwds)
        if ")" in tk and stack:
            cwds = stack.pop()
        seg = []
    return None

rm_why = None if (label or MCP) else rm_problem(cmd, [CWD])


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

def sdk_adb():
    """adb the way replicant-mcp finds it: ANDROID_HOME / ANDROID_SDK_ROOT, also from the
    replicant-mcp env in <repo>/.mcp.json, then the default SDK folders. MCP calls only."""
    if not MCP:
        return None
    homes = [os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT")]
    try:
        with open(os.path.join(os.environ.get("REPO_ROOT", "."), ".mcp.json"), encoding="utf-8") as fh:
            srv_env = (json.load(fh).get("mcpServers", {}).get("replicant-mcp", {}).get("env") or {})
        homes += [srv_env.get("ANDROID_HOME"), srv_env.get("ANDROID_SDK_ROOT")]
    except (OSError, ValueError, AttributeError):
        pass
    homes += [os.path.expanduser("~/Library/Android/sdk"), os.path.expanduser("~/Android/Sdk")]
    for h in homes:
        if isinstance(h, str) and h and os.access(os.path.join(h, "platform-tools", "adb"), os.X_OK):
            return os.path.join(h, "platform-tools", "adb")
    return None

def target_serial(exe, opts, env_serial):
    """(serial, None) · (None, None) when adb itself would find no single target
    (the command then fails on its own) · (None, why) when it cannot be resolved."""
    if "-s" in opts:
        s = os.path.expandvars(opts[opts.index("-s") + 1])
        return (None, "serial " + s + " không xác định được") if "$" in s else (s, None)
    if "$" in env_serial:
        return None, "ANDROID_SERIAL=" + env_serial + " không xác định được"
    adb = exe if "/" in exe and os.access(exe, os.X_OK) else (shutil.which("adb") or sdk_adb())
    if not adb:
        # A Bash adb call then fails on its own; replicant-mcp finds its adb elsewhere.
        return (None, "không tìm thấy adb để biết replicant-mcp dùng thiết bị nào — đặt ANDROID_HOME") if MCP else (None, None)
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
            return "không xác định được thiết bị đích (" + why + ") — " + (
                "chọn thiết bị bằng adb-device select" if MCP else "ghi rõ adb -s <SERIAL>")
        if serial and serial in deny:
            return "thiết bị " + serial + " nằm trong denylist (máy cá nhân / cấm đụng)"
        if serial and allow and serial not in allow:
            return "thiết bị " + serial + " không có trong allowlist"
    return None

if rm_why:
    sys.stderr.write("\n🛑 [HARDWARE SAFETY GATE REJECTED]\n")
    sys.stderr.write("rm đệ quy + force (-rf, -fr, -r -f, --recursive --force) bị chặn — xoá không đảo ngược được:\n")
    sys.stderr.write(f"  • {rm_why}\n")
    sys.stderr.write(f"  • Lệnh: {cmd}\n\n")
    sys.stderr.write("Được phép: build output trong project (build/, dist/, node_modules/, .gradle/, Library/, Temp/, obj/, bin/ …\n"
                     "không bị git track), đường dẫn trong /tmp hoặc $TMPDIR, thư mục từ cấp 2 trong project, một file đơn.\n"
                     "Nếu thật sự cần, người dùng tự chạy lệnh qua prefix `!` (hoặc HARDWARE_OVERRIDE=1).\n")
    sys.exit(2)

if label is None:
    dev = device_violation(cmd)
    if dev:
        sys.stderr.write("\n🛑 [HARDWARE SAFETY GATE REJECTED]\n")
        sys.stderr.write("Lệnh adb bị chặn vì chạm thiết bị ngoài chính sách thiết bị:\n")
        sys.stderr.write(f"  • {dev}\n")
        sys.stderr.write(f"  • Lệnh: {shown}\n\n")
        sys.stderr.write("Chính sách: ADB_DENY_SERIALS / ADB_ALLOW_SERIALS, ~/.config/universal-agent-devkit/adb-{denylist,allowlist}, <repo>/.adb-{denylist,allowlist}.\n")
        sys.exit(2)

if label:
    sys.stderr.write("\n🛑 [HARDWARE SAFETY GATE REJECTED]\n")
    sys.stderr.write("Lệnh bị chặn: thao tác không đảo ngược được (thiết bị thật, chứng chỉ ký, hạ tầng, dữ liệu hoặc phát hành).\n"
                     "Nếu thật sự cần, người dùng tự chạy lệnh qua prefix `!`:\n")
    sys.stderr.write(f"  • Mẫu vi phạm: {label}\n")
    sys.stderr.write(f"  • Lệnh: {shown}\n\n")
    sys.stderr.write("Nếu chắc chắn đang ở môi trường giả lập an toàn, đặt HARDWARE_OVERRIDE=1 để bỏ qua.\n")
    sys.exit(2)
sys.exit(0)
'
