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
#   • (2026-10-09) a recursive rm WITHOUT -f (rm -r, -R, --recursive: run without a terminal it does not ask) whose target
#     is or holds the project root, the home folder, / or a system partition. Any other target stays allowed (rm -r src).
#   • (2026-10-13, tests/gates/test_guard_shell_norm.sh) one reading of each command for every rm rule: wrapper option values
#     (sudo -u X, timeout -s SIG N, env -u NAME), gtimeout, arch, a redirect before the command, -c inside a shell flag cluster
#     (bash -lc); the command string of adb shell / exec-out, ssh host and su -c is walked as a command that runs on the far
#     side, where only / and the system partitions count: brace expansion, //, /./ and .. resolved, cd followed (adb shell starts
#     at /), find -delete / -exec rm, and a $VAR / `…` target refused when it starts the path or follows / or a system partition
#     (also rm -r there without -f). rm without -r reached through find's recursion (find -exec rm {} +, find | xargs rm) is
#     judged as rm -r; rsync --delete into /, home or the project root; rimraf (npx rimraf X) as rm -rf; fastboot -w; mount -o rw
#     of /; dd of=$VAR; pm uninstall|disable of a package glob. Partitions added: /cache /system_root /product_services
#     /mnt/vendor/persist /dev/block. Allowed now: npm publish --dry-run, terraform destroy -help, kubectl delete
#     --dry-run=client|server, rm -rf "$PWD/build" ($PWD is the cwd).
#   • (2026-10-14, workflow-improvements.md I.0 W3) that reading is hooks/shell_norm.py, shared with block-dangerous-git.sh. A
#     heredoc body is cut (no rm walk, pattern or device check reads it) only when the whole command is made of constructs
#     shell_norm models AND the body is the message of a known option (git commit -m, gh pr create --body, each with a quoted $(cat
#     <<'EOF' …)) or the one statement of the command (cat > notes.md <<'EOF', git commit -F -); an unquoted body with a $ or a backtick is never cut;
#     every other body stays, as before 14/10 (policy of 15/10). ~ as an rm target on a device is refused (its HOME is not known
#     here); bash -lc / su -c scripts reach the device policy; xargs -i takes no separate value.
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
#   • (2026-09-26, automotive profile only — <repo>/.agents/active-profile.json) an adb
#     logcat that streams to this computer: `adb logcat`, `adb shell logcat`, piped or
#     redirected to a host file. The ADB Wi-Fi link to the car drops and the log of the
#     measurement dies with it (GeelyEx2 INSTINCT-099). Allowed: a dump that exits
#     (-d -c -g -t -L -G -S), or a logcat detached on the car that writes there
#     (`adb shell "nohup logcat -f /data/local/tmp/x.txt &"`, `… > /sdcard/x.log &"`).
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
# FAIL-CLOSED: malformed JSON, missing python3 or an uncaught internal error → exit 2 (the command is not
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
  local re='"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)"' c bash_re='"tool(_n|N)ame"[[:space:]]*:[[:space:]]*"Bash"'
  [[ $INPUT =~ $bash_re ]] || return 1
  [[ $INPUT =~ $re ]] || return 1
  c="${BASH_REMATCH[1]}"
  # A REAL backslash (JSON \\: printf '\x67it' | sh, a gi\<newline>t continuation) or a \u escape can spell a word: parser.
  case "$c" in ""|*[\$\`\*\?\[\]]*|*'\\'*|*'\u'*) return 1 ;; esac
  # Quotes only hide a word by splitting it (g'i't, "gi"t): dropped before the check, with the JSON escape marks (\" \n), so a
  # quoted argument no longer sends every grep -n "x" to python (2026-10-09, tests/gates/test_hook_fast_path_quotes.sh: ~55 ms a call).
  # ${c//\\/} is quadratic on macOS /bin/bash 3.2: a 20 KB multi-line command (a \n per line) took 14-18 s, the hook timeout is 10 s
  # (tests/gates/test_hook_big_command_fast_path.sh). A long one goes through one linear tr; tr failing leaves the decision to the parser.
  if (( ${#c} > 256 )); then c="$(printf '%s' "$c" | LC_ALL=C tr -d '\\\047\042')" || return 1
  else c="${c//\\/}"; c="${c//\'/}"; c="${c//\"/}"; fi
  shopt -s nocasematch
  if [[ $c =~ $1 ]]; then shopt -u nocasematch; return 1; fi
  shopt -u nocasematch
  return 0
}
# delete: `find . -delete` removes a tree with no rm in it (2026-10-09, tests/gates/test_hardware_rm_containment.sh).
# rimraf / rsync: rm -rf and rsync --del(ete) spelled without rm or delete (2026-10-13, tests/gates/test_guard_shell_norm.sh).
# <( : a shell that runs a process substitution (bash <(…)) is refused by the parser whatever it says, like the git guard does (15/10)
fast_allow 'adb|emulator|-avd|fastboot|dd|mount|rm|delete|rimraf|rsync|fastlane|security|xcrun|simctl|eval|flash|publish|vercel|netlify|firebase|prisma|db:|drop|truncate|flush|kubectl|terraform|tofu|pulumi|helm|docker|s3|<[(]' && exit 0

# The project (2026-10-09): CLAUDE_PROJECT_DIR, else the git tree of the payload cwd (of the process cwd when the payload has
# none); outside a git tree the rm guard measures from the process cwd as before, and nothing is logged
# (tests/gates/test_hook_log_dir.sh: a run at / created /.claude/audit-gate/).
REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "${REPO_ROOT}" ]; then   # the regex costs ~10 ms on a 1 MB payload: only when it is needed
  RX_CWD='"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'   # a JSON-escaped cwd too (é sent escaped, \", \\): tests/gates/test_hook_payload_cwd_escaped.sh
  [[ ${INPUT} =~ ${RX_CWD} ]] && _PCWD="${BASH_REMATCH[1]}" || _PCWD="."
  case "${_PCWD}" in *\\*) _PCWD="$(python3 -I -c 'import json,sys; sys.stdout.buffer.write(json.loads("\"%s\"" % sys.argv[1]).encode())' "${_PCWD}" 2>/dev/null)" || _PCWD="." ;; esac
  REPO_ROOT="$(git -C "${_PCWD}" rev-parse --show-toplevel 2>/dev/null)"
fi
LOG_DIR="${REPO_ROOT:+${REPO_ROOT}/.claude/audit-gate}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"
if [ "${HARDWARE_SAFETY_GATE:-1}" = "0" ] || [ "${HARDWARE_OVERRIDE:-0}" = "1" ]; then
  if [ -n "${LOG_DIR}" ] && mkdir -p "${LOG_DIR}" 2>/dev/null; then
    for _fifo in "${LOG_DIR}"/* "${LOG_DIR}"/.[!.]*; do [ ! -p "${_fifo}" ] || rm -f -- "${_fifo}"; done   # a FIFO here (never one of ours) would hang the next open of a log or lock: drop it
    [ -e "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
    echo "[$(date +%Y-%m-%dT%H:%M:%S)] HARDWARE_SAFETY_GATE=${HARDWARE_SAFETY_GATE:-1} HARDWARE_OVERRIDE=${HARDWARE_OVERRIDE:-0} — gate bypassed" \
      >> "${LOG_DIR}/hardware_safety_gate.log" 2>/dev/null
  fi
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "🛑 [HARDWARE SAFETY GATE] cần python3 để phân tích lệnh — chặn để an toàn (HARDWARE_SAFETY_GATE=0 để tắt)." >&2
  exit 2
fi

printf '%s' "$INPUT" | REPO_ROOT="${REPO_ROOT}" python3 -I -c '
import sys, os
# FAIL-CLOSED on a crash (2026-10-04): an uncaught exception exits 1, which Claude Code lets through. Installed before any other
# import. -I (above) keeps the cwd off sys.path: a json.py / shlex.py in the project root would otherwise replace the stdlib module.
def _fail_closed(etype, value, tb):
    try:
        why = (str(value).splitlines() or [""])[0][:100]
        sys.stderr.write("🛑 [HARDWARE SAFETY GATE] lỗi nội bộ (" + etype.__name__ + ": " + why + ") — chặn để an toàn. Nếu đây là lỗi của cổng: người dùng tự chạy lệnh qua prefix `!` (hoặc HARDWARE_OVERRIDE=1).\n")
        sys.stderr.flush()
    finally:
        os._exit(2)
sys.excepthook = _fail_closed
import json, re, fnmatch, shlex, shutil, subprocess, signal
# Watchdog: the hook limit is 10 s (.claude/settings.json) and a hook killed there is no verdict. A command the parser cannot judge in 7 s
# (a pattern word[^;&|\n]*rare re-scans the line for every word: 15 s for 60 KB of `dd dd dd …`) is refused with a reason. SIGALRM also
# interrupts a regex search in the middle (checked on Python 3.9 and 3.14). tests/gates/test_hook_big_command_fast_path.sh
def _too_slow(_sig, _frame):
    try:
        sys.stderr.write("🛑 [HARDWARE SAFETY GATE] lệnh quá lớn / quá phức tạp để phân tích trong thời hạn của hook (7 s của 10 s) — chặn để an toàn. "
                         "Chia thành lệnh nhỏ hơn, hoặc ghi vào file rồi chạy file.\n")
        sys.stderr.flush()
    finally:
        os._exit(2)
if hasattr(signal, "setitimer"):
    signal.signal(signal.SIGALRM, _too_slow)
    signal.setitimer(signal.ITIMER_REAL, 7)

def _fnm(name, pat):
    # Python 3.9 raises re.error for a reversed range ([z-a], the s[:-1] of a script); bash reads such a bracket as "no match"
    try:
        return fnmatch.fnmatch(name, pat)
    except re.error:
        return False

raw = sys.stdin.read()
if not raw.strip():
    sys.exit(0)

try:
    data = json.loads(raw)
    # toolInput / toolName: the camelCase envelope (Grok, hooks/devkit_harness.py; 2026-10-09 it found no command and passed)
    inp = data.get("tool_input") or data.get("toolInput") or data.get("input") or {}
    cmd = inp.get("command") or inp.get("CommandLine") or ""
except Exception:
    sys.stderr.write("🛑 [HARDWARE SAFETY GATE] không đọc được JSON đầu vào — chặn để an toàn.\n")
    sys.exit(2)
if not isinstance(cmd, str):
    sys.stderr.write("🛑 [HARDWARE SAFETY GATE] tool_input.command không phải chuỗi — chặn để an toàn.\n")
    sys.exit(2)

# ── replicant-mcp: the adb command each tool runs (replicant-mcp 1.6.7 dist/tools) ──
tool = str(data.get("tool_name") or data.get("toolName") or "")
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

# hooks/shell_norm.py: the one reading of a command line that this gate and block-dangerous-git.sh share (W3, 14/10): wrappers,
# sh -c / su -c / ssh / adb shell, brace expansion, paths, heredocs. Loaded from this hook own directory ($0, a linked install
# resolved), never from the project (python3 -I). Missing: the call is blocked, with the reason (fail closed).
try:
    _HOOK_DIR = os.path.dirname(os.path.realpath(sys.argv[1])) if len(sys.argv) > 1 else ""
    if not os.path.isabs(_HOOK_DIR):
        raise ImportError("hook path ($0) is not known")
    sys.dont_write_bytecode = True
    sys.path.append(_HOOK_DIR)   # after the stdlib
    import shell_norm
except Exception as e:
    sys.stderr.write("🛑 [HARDWARE SAFETY GATE] không nạp được hooks/shell_norm.py cạnh hook (" + str(e)[:120] + ") — chặn để an "
                     "toàn. Cài lại DevKit (agent-kit init); lệnh cần chạy ngay thì người dùng tự chạy qua prefix `!` (hoặc HARDWARE_OVERRIDE=1).\n")
    sys.exit(2)
# What the patterns, the device policy and the logcat rule read: the command without the heredoc bodies that are data by the policy of
# 15/10 (the message of a known option, the one file statement of a modeled command: shell_norm). Every other body stays. The rm walk
# also cuts the program body of an interpreter that cannot start a process (rm_problem).
_DOCS = shell_norm.heredocs(cmd) if "<<" in cmd else []
CMD_NOJOIN = shell_norm.strip_heredocs(cmd, lambda h: h.kind == "data", _DOCS) if _DOCS else cmd
# A backslash-newline continues the line: the words on both sides are one command (15/10) — except in a comment, which ends at the newline whatever
# precedes it (#c\<nl>adb remount RUNS: the join glued the c to adb, 15/10 r4), and an escaped backslash joins nothing (shell_norm.join_continuations).
# So every check reads the text joined AND as typed: TEXTS.
CMD_LIVE = shell_norm.join_continuations(CMD_NOJOIN)
TEXTS = [CMD_LIVE] + ([CMD_NOJOIN] if CMD_NOJOIN != CMD_LIVE else [])

# Options adb/fastboot accept before the subcommand (with or without a value).
ADB_OPTS = r"(?:\s+(?:-[sHPtL]\s+\S+|-[adeU]|--\S+(?:\s+\S+)?|wait-for-[\w-]+))*"   # wait-for-device remount (15/10)
FB_OPTS = r"(?:\s+(?:-[sSciopn]\s+\S+|-w|-u|--\S+(?:=\S+)?))*"
# first alternative: / or a system partition, then / whitespace end ; & |; second: a glob in the FIRST path component (/*, /data*,
# /sys*, /s*, /dat?, /syste[m], /?ystem) can reach a system partition, while /sdcard/* and /tmp/x* cannot
# (2026-10-13) cache, system_root, product_services, mnt/vendor/persist (calibration data) and dev/block (the raw partitions) added
SYS_PARTS = (r"/(?:system|system_ext|system_dlkm|vendor|vendor_dlkm|boot|product|odm|odm_dlkm|apex|metadata|data|persist|efs"
             r"|cache|system_root|product_services|mnt/vendor/persist|dev/block)?(?:/|\s|$|[;&|])|/[^/\s]*[*?\[][^/\s]*(?:/|\s|$|[;&|])")

PATTERNS = [
    (r"\badb" + ADB_OPTS + r"\s+(?:remount|disable-verity|enable-verity)\b",
     "adb remount/disable-verity (nguy cơ phá dm-verity gây brick thiết bị)"),
    (r"\bmount\b[^;&|\n]*\brw\b[^;&|\n]*/(?:system|vendor|product|odm)\b",
     "mount phân vùng hệ thống ở chế độ rw"),
    (r"\bmount\b[^;&|\n]*/(?:system|vendor|product|odm)\b[^;&|\n]*\brw\b",
     "mount phân vùng hệ thống ở chế độ rw"),
    # (2026-10-13) / itself: a system-as-root device mounts the system image at / (adb shell mount -o remount,rw /)
    (r"\bmount\b[^;&|\n]*\brw\b[^;&|\n]*\s/(?:system_root)?(?=\s|$|[;&|\x22\x27])", "mount / (system-as-root) ở chế độ rw"),
    (r"\bmount\b[^;&|\n]*\s/(?:system_root)?(?=\s|$|[;&|])[^;&|\n]*\brw\b", "mount / (system-as-root) ở chế độ rw"),
    (r"\bdd\b[^;&|\n]*\bof=/dev/", "dd ghi thẳng vào thiết bị khối /dev/…"),
    # (2026-10-13) of= that the shell fills in at run time ($DISK, $(…), `…`): it may be a raw device
    (r"\bdd\b[^;&|\n]*\bof=[\x22\x27]?(?:\$|\x60)", "dd ghi vào đích chưa biết lúc chạy ($VAR / lệnh con) — có thể là thiết bị khối"),
    (r"\bfastboot" + FB_OPTS + r"\s+(?:flash|flashall|erase|format|update)\b",
     "fastboot flash/erase/format (can thiệp bootloader thiết bị thật)"),
    (r"\bfastboot" + FB_OPTS + r"\s+(?:oem|flashing)\s+(?:unlock|lock)\b",
     "fastboot oem/flashing unlock (xoá sạch thiết bị)"),
    # (2026-10-13) -w wipes userdata (and cache) wherever it stands: FB_OPTS skips it as an option before the verb. Not before a
    # pipe: `grep "fastboot -w\|…"` with its backslash dropped (norm_strip) is a search pattern, not a wipe
    (r"\bfastboot\b[^;&|\n]*\s-w(?=\s|$|[;&\x22\x27])", "fastboot -w (xoá userdata/cache của thiết bị)"),
    # Removing or disabling a system package (SystemUI, the launcher, GMS …) for the
    # user can leave the device unable to boot to a usable screen. (2026-10-13) A package glob (com.ecarx.*) may name any of them.
    (r"\badb" + ADB_OPTS + r"\s+shell\s+(?:[^;&|\n]*\s)?pm\s+(?:uninstall|disable-user|disable|hide)\b[^;&|\n]*"
     r"\s(?:android|com\.android\.[\w.]+|com\.google\.android\.[\w.]+|com\.sec\.[\w.]+|com\.samsung\.[\w.]+"
     r"|com\.qualcomm\.[\w.]+|com\.mediatek\.[\w.]+|[\w.]*[*?][\w.*?]*)(?=\s|$|[;&|])",
     "gỡ/tắt app hệ thống Android (pm uninstall/disable) — thiết bị có thể không vào được màn hình"),
    # iOS signing identity and device fleet: not recoverable from the repo.
    (r"\bfastlane\b[^;&|\n]*\bmatch\s+nuke\b", "fastlane match nuke — thu hồi TOÀN BỘ chứng chỉ ký của team"),
    (r"\bsecurity\s+delete-(?:keychain|identity|certificate)\b", "security delete-keychain/identity — xoá chứng chỉ/khoá ký"),
    (r"\brm\b[^;&|\n]*(?:MobileDevice/Provisioning|Library/Keychains)", "xoá provisioning profiles / keychain"),
    (r"\bxcrun\s+simctl\s+(?:erase|delete)\s+all\b", "xcrun simctl erase/delete all — xoá sạch mọi simulator"),
    # Irreversible release / infrastructure / data operations (AGENTS.md §5.1 Gate 2 c):
    # the user runs them, via the `!` prefix, never the agent on its own.
    # (2026-10-13) --dry-run (bare or =true) uploads nothing; --dry-run=false is the real thing
    (r"\b(?:npm|pnpm|yarn|bun)\s+(?:publish|unpublish)\b(?![^;&|\n]*\s--dry-run(?:=true)?(?=\s|$|[;&|]))",
     "phát hành package lên registry (npm publish)"),
    (r"\b(?:vercel|netlify)\b[^;&|\n]*\s--prod\b", "deploy production (vercel/netlify --prod)"),
    (r"\bfirebase\s+deploy\b", "firebase deploy (lên production)"),
    (r"\bprisma\s+(?:migrate\s+reset|db\s+push\s+[^;&|\n]*--force-reset)\b", "prisma migrate reset — xoá sạch database"),
    (r"\b(?:rails|rake)\s+db:(?:drop|reset|schema:load)\b", "rails db:drop/reset — xoá database"),
    (r"\b(?:psql|mysql|mariadb|sqlite3|cockroach|clickhouse-client|cqlsh)\b[^;&|\n]*\b(?:drop\s+(?:database|schema|table)|truncate\s+(?:table\s+)?\w)",
     "DROP DATABASE/TABLE hoặc TRUNCATE qua CLI database"),
    (r"\bdropDatabase\s*\(|\bdb\.[\w$]+\.drop\s*\(", "MongoDB dropDatabase()/drop()"),
    (r"\bredis-cli\b[^;&|\n]*\bflush(?:all|db)\b", "redis-cli FLUSHALL/FLUSHDB — xoá toàn bộ dữ liệu Redis"),
    # (2026-10-13) --dry-run (bare, =client or =server) deletes nothing; --dry-run=none deletes
    (r"\bkubectl\b(?![^;&|\n]*\s--dry-run(?:=(?:client|server))?(?=\s|$|[;&|]))[^;&|\n]*\bdelete\b[^;&|\n]*(?:\s(?:namespace|namespaces|ns|pv|pvc|persistentvolumes?|persistentvolumeclaims?|crds?|customresourcedefinitions?|nodes?)\b|\s--all\b)",
     "kubectl delete namespace/volume/--all"),
    # (2026-10-13) terraform destroy -help / --help / -h prints the usage
    (r"\b(?:terraform|tofu)\s+(?:destroy\b(?![^;&|\n]*\s-{1,2}h(?:elp)?(?=\s|$|[;&|]))|apply\b[^;&|\n]*\s-destroy\b)|\bpulumi\s+destroy\b",
     "terraform/pulumi destroy — xoá hạ tầng"),
    (r"\bhelm\s+(?:uninstall|delete)\b", "helm uninstall — gỡ release khỏi cluster"),
    (r"\bdocker\b[^;&|\n]*(?:\bsystem\s+prune\b[^;&|\n]*--volumes|\bvolume\s+(?:rm|prune)\b|\bcompose\s+down\b[^;&|\n]*\s(?:-v|--volumes)\b)",
     "xoá docker volume (mất dữ liệu)"),
    (r"\baws\s+s3\s+(?:rm\b[^;&|\n]*--recursive|rb\b[^;&|\n]*--force)", "aws s3 rm --recursive / rb --force"),
    # a shell that runs the text a process substitution makes (bash <(echo …), bash < <(…)): the text cannot be read here, and the git guard
    # refuses it too (15/10, review: bash <(echo rm -rf /) was allowed by this gate)
    (r"(?:^|[\s;&|(])(?:ba|z|da|k)?sh(?:\s+-\S+)*\s+(?:<\s*)?<\(", "shell chạy văn bản do process substitution sinh ra (bash <(…)): cổng không đọc được nội dung"),
]

# /data/local/tmp is adb scratch space (pushed APKs, logcat dumps): clearing it cannot brick a device (user, 2026-10-12: allow).
# Only the folder itself or a path under it, with no `..` leaving it and nothing the shell expands at run time ($, backtick).
SCRATCH_OK = re.compile(r"^/data/local/tmp(?:/[^$\x60]*)?[\x22\x27]?$")
def _sys_target(a):
    if SCRATCH_OK.match(a) and not re.search(r"(?:^|/)\.\.(?:/|$|[\x22\x27])", a):
        return False
    return bool(re.match(SYS_PARTS, a + " "))

def rm_hits(text):
    """rm with both recursive and force flags on a system partition or /."""
    for seg in re.split(r"[;&|\n]+", text):
        toks = seg.split()
        # What the words AFTER each position hold (-r / -R / --recursive, -f / --force, a system-partition target), one pass from the
        # right: the words after an rm used to be re-read for every rm, quadratic in a long script (50 KB of rm lines took > 10 s).
        n = len(toks)
        rec, force, sysop = [False] * (n + 1), [False] * (n + 1), [False] * (n + 1)
        for i in range(n - 1, -1, -1):
            a = toks[i]
            short = a[1:] if a.startswith("-") and not a.startswith("--") else ""
            rec[i] = rec[i + 1] or "r" in short or "R" in short or a == "--recursive"
            force[i] = force[i + 1] or "f" in short or a == "--force"
            sysop[i] = sysop[i + 1] or (not a.startswith("-") and _sys_target(a))
        for i, t in enumerate(toks):
            if t.rsplit("/", 1)[-1].lower() == "rm" and rec[i + 1] and force[i + 1] and sysop[i + 1]:
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
            if _fnm(t, base.lower()):
                return t
    return tok
def readings(text):
    """text, text with every quote and backslash character dropped, and text as shlex words (a globbed program name resolved)."""
    try:
        norm = " ".join(unglob(t) for t in shlex.split(text, comments=False, posix=True))
    except ValueError:
        norm = text      # an unbalanced quote (a lone apostrophe in a comment is enough): the shell still runs the line
    # Every quote and backslash character dropped, no tokenising. unglob() rewrites any ARGUMENT whose last path component holds a
    # glob (adb shell "rm -rf /system/*", rm -rf "/system/*" -> adb), which drops the rm and its target from norm; this variant keeps
    # them. It also survives an unbalanced quote, nested quotes (sh -c with quotes inside quotes), \rm and r""m, which shlex either
    # rejects or unwraps only one level.
    norm_strip = re.sub(r"[\\\x27\x22]", "", re.sub(r"\$(?=[\x27\x22])", "", text))   # ANSI-C and locale quoting (dollar then a quote) lose the dollar too
    return [text, norm_strip, norm]
variants = [v for t in TEXTS for v in readings(t)]

# A pattern of the shape word[^;&|\n]*rare re-scans the rest of the line for every word: quadratic on a long one-line variant (50 KB of rm
# lines cost 1+ s here). It can only match where its rare part is, so it is tried on the variants that hold one (tests/gates/test_hook_big_command_fast_path.sh).
RARE = {r"\brm\b[^;&|\n]*(?:MobileDevice/Provisioning|Library/Keychains)": ("mobiledevice/provisioning", "library/keychains")}
label = None
for pat, lab in PATTERNS:
    need = RARE.get(pat)
    if any(re.search(pat, v, re.I) for v in variants if not need or any(x in v.lower() for x in need)):
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

HOME = os.path.realpath(os.path.expanduser("~"))
SYS_PART_DIRS = {"/" + d for d in ("system", "vendor", "boot", "product", "odm", "data", "persist", "efs")}
PWD_VAR = re.compile(r"\$(?:PWD\b|\{PWD\})")
# The agent own scratch folder (audit 2026-10-25 A7). A path there is allowed like any /tmp path, but one that is IN it must also END in
# it: `rm -rf /private/tmp/claude-501/../x` and `rm -rf <scratch>/link/` (a trailing slash makes BSD rm delete what the link points at:
# measured on macOS 25/10, the target folder went, the link stayed). Review of A7 (25/10): judged on the spelling, it missed the same folder
# written another way (`//`, `/./`, another case on APFS, `~/..`, relative after a `cd`): membership is now by inode of the resolved folder.
SCRATCH_ROOTS = tuple(r + "/claude-" + str(os.getuid()) for r in ("/private/tmp", "/tmp"))

def rm_reach(path):
    """What rm -rf of the absolute path removes, resolved as the kernel does (links, `..` after a link, `//`, `/./`), never by spelling.
    A trailing / (or a last name . / ..) resolves the whole path: rm follows a link then. Otherwise the parent is resolved and the last name
    kept: rm removes a link itself, not its target."""
    q = path.rstrip("/") or "/"
    base = os.path.basename(q)
    if q == "/" or path.endswith("/") or base in (".", ".."):
        return os.path.realpath(q)
    return os.path.join(os.path.realpath(os.path.dirname(q)), base)

def scratch_root(path, roots):
    """The entry of roots ([(name, stat)]) that is the resolved path or holds it, compared by inode (APFS: /private/tmp/CLAUDE-501 is the
    same folder), else None. A name that does not exist yet is judged by its nearest existing parent."""
    d = path
    while roots:
        try:
            st = os.lstat(d)
            hit = next((r for r, s in roots if os.path.samestat(st, s)), None)
            if hit:
                return hit
        except OSError:
            pass
        up = os.path.dirname(d)
        if up == d:
            break
        d = up
    return None

def scratch_escape(base, t):
    """Why rm -rf of t, run in the folder base (/ for an absolute t), reaches outside the agent scratch folder although it is in it;
    None when it stays or is not in it. In it = the folder rm works in (the resolved parent) is the scratch folder or under it. A `..` is
    refused, checked before anything resolves it: when the path is in the scratch folder before the `..`, or ends there. A glob is judged
    on what it matches now (at most 2000) and on the folder before it."""
    roots = []
    for r in SCRATCH_ROOTS:
        try:
            roots.append((r, os.stat(r)))
        except OSError:
            pass
    if not roots:
        return None
    raw = os.path.join(base, t)
    parts = raw.split("/")
    root = scratch_root(os.path.realpath(os.path.dirname(raw.rstrip("/") or "/")), roots)
    if ".." in parts:
        root = root or next((h for h in (scratch_root(os.path.realpath("/".join(parts[:i]) or "/"), roots)
                                         for i, x in enumerate(parts) if x == "..") if h), None)
        return f"đường dẫn trong thư mục scratch có `..` (ra khỏi {root})" if root else None
    if root is None:
        return None
    if GLOB.search(t):
        import glob as _glob, itertools as _it
        tp = t.split("/")
        k = next(i for i, x in enumerate(tp) if GLOB.search(x))
        hits = [rm_reach(m) for m in _it.islice(_glob.iglob(os.path.join(_glob.escape(base), t)), 2000)]
        hits.append(os.path.realpath(os.path.join(base, "/".join(tp[:k]) or ("/" if t.startswith("/") else "."))))
    else:
        hits = [rm_reach(raw)]
    out = next((p for p in hits if scratch_root(p, roots) is None), None)
    return f"ra khỏi thư mục scratch {root} (tới {out})" if out else None

def rm_target_problem(t, cwds, env, forced=True):
    """Why removing target t recursively is refused, or None. Without -f (forced=False; 2026-10-09,
    tests/gates/test_hardware_rm_unforced.sh) only a target that is or holds the project root, the home folder, / or a
    system partition: rm -r with no terminal to ask on deletes all the same. A target it cannot resolve is not refused then."""
    orig = t
    if PWD_VAR.search(t):   # $PWD is the directory the command runs in (2026-10-13: rm -rf "$PWD/build" was refused as unknown)
        for cwd in cwds:
            if cwd is None:
                if forced:
                    return f"{orig}: không biết thư mục hiện tại ($PWD sau cd tới $VAR / lệnh con / popd)"
                continue
            why = rm_target_problem(PWD_VAR.sub(lambda m: cwd, t), [cwd], env, forced)
            if why:
                return why
        return None
    if t.startswith("~"):
        t = os.path.expanduser(t)
    t = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), t)
    if "$" in t or "`" in t:
        return f"{orig}: không xác định được đường dẫn ($VAR / lệnh con)" if forced else None
    glob = bool(GLOB.search(t))
    for cwd in ([None] if os.path.isabs(t) else cwds):
        if cwd is None and not os.path.isabs(t):
            if not forced:
                continue
            return f"{orig}: không biết thư mục hiện tại (cd tới $VAR / lệnh con / popd)"
        if forced:   # A7: a path in the scratch folder must stay in it (scratch_escape), whatever its spelling
            esc = scratch_escape(cwd or "/", t)
            if esc:
                return f"{orig}: {esc}"
        outs = []
        if glob:  # judged as its directory: rm -rf src/* empties src; the shell expands the glob inside it, through a link too
            parts = t.split("/")
            k = next(i for i, x in enumerate(parts) if GLOB.search(x))
            p = os.path.realpath(os.path.join(cwd or "/", "/".join(parts[:k]) or ("/" if t.startswith("/") else ".")))
            # …and each match it expands to now (at most 2000) that lands outside that folder, through a link (`build/*/`, `build/*/x`):
            # judged where it lands (review of A7, 25/10)
            import glob as _glob, itertools as _it
            reach = (rm_reach(m) for m in _it.islice(_glob.iglob(os.path.join(_glob.escape(cwd or "/"), t)), 2000))
            outs = list(dict.fromkeys(r for r in reach if r != p and not r.startswith(p.rstrip(os.sep) + os.sep)))
        else:   # where the kernel resolves it (review of A7, 25/10): `link/` deletes what the link points at, `link` the link alone
            p = rm_reach(os.path.join(cwd or "/", t))
        for q, g in [(p, glob)] + [(r, False) for r in outs]:
            why = rm_path_problem(q, orig, forced, g)
            if why:
                return why
    return None

def rm_path_problem(p, orig, forced, glob):
    """The verdict of rm_target_problem on one resolved path p (glob: p is the folder a glob expands in). None when allowed."""
    if not glob and os.path.lexists(p) and (os.path.islink(p) or not os.path.isdir(p)):
        return None  # a single file
    if not forced:   # / holds the project root, so it is caught by the first test
        hit = next((d for d in (ROOT, HOME) if p == d or under(d, p)), None) or (p if p in SYS_PART_DIRS else None)
        return f"{orig}: là hoặc chứa {hit} (gốc project / home / phân vùng hệ thống)" if hit else None
    if p == ROOT:
        return f"{orig}: là thư mục gốc project"
    if under(p, ROOT):
        rel = os.path.relpath(p, ROOT).split(os.sep)
        if any(x in BUILD_OUTPUTS for x in rel):
            return f"{orig}: là build output nhưng git đang track file trong đó (là source)" if git_tracks(p) else None
        return f"{orig}: là thư mục cấp 1 của project" if len(rel) == 1 else None
    # Before the /tmp exemption (2026-10-09): a project under /tmp or $TMPDIR is inside its parent, and
    # `rm -rf ..` from it passed while `rm -rf <project>` was blocked.
    if under(ROOT, p):
        return f"{orig}: chứa thư mục gốc project ({ROOT})"
    if any(under(p, d) for d in TMP_ROOTS):
        return None
    return f"{orig}: nằm ngoài project ({p})"

# find and xargs delete paths that are not on the rm command line (2026-10-09, tests/gates/test_hardware_rm_containment.sh):
# `find P -delete`, `find P -exec rm -rf {} +` and `find P | xargs rm -rf` are judged as rm -rf of the start points P —
# unless a -name/-path/-regex filter narrows what find matches (`-name *`, `-path */*` narrow nothing: find_narrowed) (then the verdict is unchanged: the pinned contract case
# `find . -name __pycache__ -exec rm -rf {} +` stays allowed). `echo a b | xargs rm -rf` is rm -rf a b; any other text
# piped into `xargs rm -r…` (cat list, git ls-files, ls) cannot be read and is refused.
FIND_NAME_FILTERS = {"-name", "-iname", "-path", "-ipath", "-wholename", "-iwholename", "-regex", "-iregex"}
FIND_ESC = {"__ESC_SEMI__": ";", "__ESC_LP__": "(", "__ESC_RP__": ")"}
FIND_ARG1 = {"-printf", "-fprint", "-fprint0", "-fls", "-type", "-xtype", "-newer", "-anewer", "-cnewer", "-user", "-group", "-perm", "-size",
             "-atime", "-ctime", "-mtime", "-amin", "-cmin", "-mmin", "-maxdepth", "-mindepth", "-inum", "-links", "-samefile", "-regextype",
             "-uid", "-gid", "-lname", "-ilname", "-fstype", "-context", "-xattrname", "-Bnewer", "-mnewer", "-Bmin", "-Btime", "-flags", "-used",
             "-files0-from"}   # primaries with ONE argument that is no operator, whatever it looks like
XARGS_OPTS_WITH_ARG = {"-I", "-J", "-R", "-S", "-n", "-P", "-L", "-d", "-E", "-s", "-a"}   # -i: GNU, its value is glued (shell_norm too)

def find_starts(args):
    """The start points of find: the operands before its expression (BSD -f PATH too); "." when there is none."""
    i, starts = 0, []
    while i < len(args):
        a = args[i]
        if a in ("-H", "-L", "-P", "-E", "-X", "-d", "-s", "-x") or re.match(r"^-O\d$", a):
            i += 1
        elif a == "-D":
            i += 2
        elif a == "-f" and i + 1 < len(args):
            starts.append(args[i + 1])
            i += 2
        else:
            break
    while i < len(args) and not args[i].startswith("-") and args[i] not in ("!", "(", ")", ","):
        starts.append(args[i])
        i += 1
    return starts or ["."]

def find_narrowed(args, starts):
    """Whether a -name/-path/-regex filter narrows what find matches. One whose pattern matches every entry under a start
    point (`*`, `*/*`, `./*`, regex `.*`) narrows nothing and counts as no filter (2026-10-09, tests/gates/test_hardware_find_match_all.sh);
    a regex python cannot read counts as none too. Probe entries: names no real filter matches all of.
    A filter after ! / -not narrows nothing (it keeps everything else), `! ( … )` is read as no filter at all, and every -o
    alternative needs a filter of its own (`find . -name x -o -type f -delete`) (2026-10-09 follow-up,
    tests/gates/test_hardware_find_not_or.sh)."""
    live = set()   # positions of the filters that narrow on their own
    for k, a in enumerate(args[:-1]):
        if a not in FIND_NAME_FILTERS:
            continue
        pat, fold = args[k + 1], a.startswith("-i")
        groups = ([("0", ".Q", "Zz-9.x")] if a in ("-name", "-iname")
                  else [[s.rstrip("/") + "/" + n for n in ("0", ".Q/Zz-9.x")] for s in starts])
        if a.endswith("regex"):
            try:
                rx = re.compile(pat, re.I if fold else 0)
            except re.error:
                continue
            hit = lambda x: rx.fullmatch(x) is not None
        else:
            hit = lambda x: _fnm(x.lower(), pat.lower()) if fold else _fnm(x, pat)
        if not any(all(hit(x) for x in g) for g in groups):
            live.add(k)
    def seq(i, in_group):
        """(narrows, next index) of the expression from args[i] to the ")" that closes its group (or the end). It narrows when EVERY
        alternative (split at -o / -or / a comma) holds a positive filter of its own; a nested group is one term that counts when it
        narrows by itself; a negated filter or group, and the arguments of -exec / -execdir / -ok / -okdir, narrow nothing."""
        alts, cur = [], False
        while i < len(args):
            a = args[i]
            if a == ")":
                if in_group:
                    break
                i += 1
            elif a in ("-o", "-or", ","):
                alts.append(cur)
                cur, i = False, i + 1
            elif a in ("!", "-not"):
                nxt = args[i + 1] if i + 1 < len(args) else ""
                if nxt == "(":   # a negated group only restricts further (AND NOT): skip it whole
                    i = seq(i + 2, True)[1] + 1
                else:
                    i += 3 if nxt in FIND_NAME_FILTERS else 1
            elif a == "(":
                sub, i = seq(i + 1, True)
                if i >= len(args):   # never closed: nothing is known about what it covers
                    return False, i
                cur, i = cur or sub, i + 1
            elif a in FIND_NAME_FILTERS:   # the pattern is an argument, whatever it looks like (-name "(")
                cur, i = cur or i in live, i + 2
            elif a == "-fprintf":
                i += 3
            elif a in FIND_ARG1 or re.fullmatch(r"-newer[aBcmt][aBcmt]", a):
                i += 2
            elif a in ("-exec", "-execdir", "-ok", "-okdir"):
                while i < len(args) and args[i] not in (";", "+"):
                    i += 1
                i += 1
            else:
                cur, i = cur or i in live, i + 1
        alts.append(cur)
        return all(alts), i
    return seq(0, False)[0]

def feed_paths(feed):
    """(paths, from find) of a command piped into `xargs rm`: find start points ([] when a name filter narrows them), the
    words of a literal echo / printf; None when they cannot be read. from find: find recursed into the paths (2026-10-13)."""
    if not feed:
        return None, False
    i = 0
    while i < len(feed) and (re.match(r"^[A-Za-z_]\w*=", feed[i]) or os.path.basename(feed[i]) in RM_WRAPPERS):
        i += 1
    if i >= len(feed):
        return None, False
    prog, args = os.path.basename(feed[i]), [FIND_ESC.get(x, x) for x in feed[i + 1:]]
    if prog == "find":
        starts = find_starts(args)
        return ([] if find_narrowed(args, starts) else starts), True
    if prog in ("echo", "printf") and not any(c in a for a in args for c in "$`("):
        words = re.split(r"(?:\s|\\[nt0])+", " ".join(a for a in args if not re.fullmatch(r"-[neE]+", a)))
        return [w for w in words if w and "%" not in w], False
    return None, False

# ── One reading of a simple command for every rm rule (2026-10-13, tests/gates/test_guard_shell_norm.sh; the reading itself is
# hooks/shell_norm.py since 14/10, shared with block-dangerous-git.sh) ───────────────────────────────────────────────────────
# The aware reading is shell_norm.prefix_end (`sudo -u root rm`, `timeout -s KILL 5 rm`, `env -u HOME rm`, gtimeout, arch and a
# redirect before the command hid the rm: the old reading stopped at the option value), with xargs as one more prefix (the command
# it runs gets the paths). The reading before 2026-10-13 (every word after a wrapper that starts with - or is a number) is judged
# as well, so the new reading only ever adds a verdict.

def prefix_end(toks, aware):
    """Index of the program word of toks for the aware reading or the one before 2026-10-13 (aware False)."""
    i = 0
    while i < len(toks):
        if aware:
            j = shell_norm.prefix_end(toks, i)
            if j < len(toks) and os.path.basename(toks[j]) == "xargs":
                i = j + 1 + shell_norm.xargs_command(toks[j + 1:])
                continue
            return j
        tk, w = toks[i], os.path.basename(toks[i])
        if re.match(r"^[A-Za-z_]\w*=", tk):
            i += 1
        elif w in RM_WRAPPERS:
            i += 1
            while i < len(toks) and (toks[i].startswith("-") or re.match(r"^\d+\w?$", toks[i])):
                i += 2 if w == "xargs" and toks[i] in XARGS_OPTS_WITH_ARG else 1
        else:
            break
    return min(i, len(toks))   # a redirect or wrapper word at the very end: no program

def shell_scripts(rest):
    """The scripts a shell (or su) runs with -c (shell_norm.shell_script: -c alone or in a flag cluster, bash -lc, sh -ec, options
    after it); plus the word right after a lone -c, the reading before 2026-10-13."""
    out = set()
    if "-c" in rest and rest.index("-c") + 1 < len(rest):
        out.add(rest[rest.index("-c") + 1])
    script = shell_norm.shell_script(rest)
    if script is not None:
        out.add(script)
    return out

def device_script(prog, rest):
    """(script, cwds it starts in, where) of a command that runs on another machine (shell_norm.far_command): adb shell /
    exec-out ("device": its shell starts at /), ssh host ("ssh": the remote home, unknown). None otherwise."""
    far = shell_norm.far_command(prog, rest)
    if not far:
        return None
    return far[0], (["/"] if far[1] == "device" else [None]), far[1]

braces = shell_norm.braces

def remote_target_problem(t, cwds, env, where="device"):
    """Why removing t recursively on a DEVICE / remote host is refused, or None. Only / and the system partitions count there
    (_sys_target). The raw word and each brace expansion are judged; //, /./ and .. are resolved; a glob is judged as its
    directory; a relative path starts at the far cwd (adb shell: /, then each cd; ssh: unknown, not judged). A target the far
    shell fills in at run time ($VAR, `…`) is refused when it starts with it or when what stays fixed before it is / or inside a
    system partition: $ANDROID_ROOT is /system. On a device ~ is such a target too (14/10): the HOME of the device shell is not
    known here and may be / (ssh: the remote user home, no system partition)."""
    t = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), t)
    for x in [t] + braces(t):
        if x.startswith("~"):
            if where == "device":
                return f"{t}: ~ trên thiết bị (HOME của shell thiết bị không biết trước, có thể là /) — có thể là / hoặc phân vùng hệ thống"
            continue
        if x[:1] in ("$", "`"):
            return f"{t}: đường dẫn trên thiết bị chỉ biết lúc chạy, có thể là / hoặc phân vùng hệ thống"
        for cwd in ([None] if x.startswith("/") else cwds):
            if cwd is None and not x.startswith("/"):
                continue
            full = x if x.startswith("/") else cwd.rstrip("/") + "/" + x
            if "$" in full or "`" in full:
                p = shell_norm.norm_path(re.split(r"[$`]", full, 1)[0])
                if _sys_target(p):
                    return f"{t}: đường dẫn trên thiết bị chỉ biết lúc chạy, nằm trong {p} (gốc / phân vùng hệ thống)"
                continue
            p = shell_norm.norm_path(full)
            if GLOB.search(p):
                parts = p.split("/")
                k = next(i for i, y in enumerate(parts) if GLOB.search(y))
                p = "/".join(parts[:k]) or "/"
            if _sys_target(p) or _sys_target(full):
                return f"{t}: trên thiết bị là {p} (gốc / phân vùng hệ thống)"
    return None

def rimraf_args(prog, rest):
    """The paths rimraf removes (rm -rf in a package: rimraf X, npx [-y] rimraf[@v] X, pnpm|yarn|npm|bun dlx|exec|x rimraf X,
    yarn rimraf X), or None when the command is no rimraf."""
    words, j = [prog] + rest, 0
    if prog in ("npx", "bunx", "pnpx"):
        j = 1
    elif prog in ("pnpm", "yarn", "npm", "bun") and len(words) > 1 and words[1] in ("dlx", "exec", "x"):
        j = 2
    elif prog == "yarn":
        j = 1
    while 0 < j < len(words) and words[j].startswith("-"):
        j += 2 if words[j] in ("-p", "--package") else 1
    if j < len(words) and os.path.basename(words[j]).split("@")[0] == "rimraf":
        return [a for a in words[j + 1:] if not a.startswith("-")]
    return None

def rm_segment_problem(toks, cwds, env, depth, feed=None, remote=False, implied=False):
    """Problem of one simple command, or None. feed: the command piped into this one (`find . | xargs rm -rf`). remote: it runs on
    a device or remote host (adb shell, ssh host): only / and system partitions count (remote_target_problem). implied: an rm
    that find runs on everything under its start points (find -exec rm {} +), judged as rm -r. Both readings of the prefix are
    judged (prefix_end). sudo -s STR / env -S STR are words first (shell_norm.inline_script)."""
    toks = shell_norm.inline_script(toks)
    for i in sorted({prefix_end(toks, True), prefix_end(toks, False)}):
        why = rm_command_problem(toks, i, cwds, env, depth, feed, remote, implied)
        if why:
            return why
    return None

def rm_command_problem(toks, i, cwds, env, depth, feed, remote, implied):
    """rm_segment_problem for the program at toks[i]; toks[:i] is its prefix (NAME=VAL words for this command, xargs and its
    options)."""
    xargs, xargs_file, repl, k = False, False, {"{}"}, 0
    while k < i:
        tk = toks[k]
        if re.match(r"^[A-Za-z_]\w*=", tk):
            name, v = tk.split("=", 1)
            env[name] = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), v)
        elif os.path.basename(tk) == "xargs":
            xargs = True
            while k + 1 < i and (toks[k + 1].startswith("-") or re.match(r"^\d+\w?$", toks[k + 1])):
                o = toks[k + 1]
                xargs_file = xargs_file or o == "-a" or o.startswith("--arg-file")
                if o in ("-I", "-J") and k + 2 < len(toks):
                    repl.add(toks[k + 2])
                elif o[:2] in ("-I", "-J") and len(o) > 2:
                    repl.add(o[2:])
                k += 2 if o in XARGS_OPTS_WITH_ARG else 1
        k += 1
    if i >= len(toks):
        return None
    prog, rest = os.path.basename(toks[i]), toks[i + 1:]
    if GLOB.search(prog) and _fnm("rm", prog.lower()):
        prog = "rm"
    if prog == "git":   # git -c alias.x=!CMD x runs CMD through a shell (15/10 r4: git -c alias.x=!rm -rf ~ x was allowed; the git guard reads it)
        for j, a in enumerate(rest):
            spec = rest[j + 1] if a == "-c" and j + 1 < len(rest) else a[2:] if a.startswith("-c") else ""
            key, _eq, val = spec.partition("=")
            if key.lower().startswith("alias.") and val.startswith("!"):
                why = rm_problem(val[1:], cwds, depth + 1, remote)
                if why:
                    return why
        return None
    if prog in shell_norm.SHELLS or prog == "su":
        scripts = shell_scripts(rest)
        for s in scripts:
            why = rm_problem(s, cwds, depth + 1, remote)
            if why:
                return why
        if prog == "su" and not scripts:   # su [OPTIONS] USER COMMAND…: the words after the user (shell_norm.su_command)
            ran = shell_norm.su_command(rest)
            if ran and ran[0] == "script":   # --command=STR / --session-command STR: a command line (string API), not a word list
                return rm_problem(ran[1], cwds, depth + 1, remote)
            return rm_segment_problem(ran[1], cwds, env, depth + 1, None, remote) if ran else None
        return None
    dev = device_script(prog, rest)
    if dev:
        return rm_problem(dev[0], dev[1], depth + 1, dev[2])
    if prog == "eval":
        return rm_problem(" ".join(rest), cwds, depth + 1, remote)
    if prog == "find":
        rest = [FIND_ESC.get(x, x) for x in rest]
        starts = find_starts(rest)
        named = find_narrowed(rest, starts)
        if "-delete" in rest and not named:
            why = rm_segment_problem(["rm", "-rf", "--"] + starts, cwds, env, depth + 1, None, remote)
            if why:
                return why + " (find -delete)"
        for j, a in enumerate(rest):
            if a in ("-exec", "-execdir", "-ok", "-okdir"):
                sub = []
                for x in rest[j + 1:]:
                    if x in (";", "+"):
                        break
                    sub.append(x)
                if not named:   # {} stands for everything under the start points
                    sub = [y for x in sub for y in (starts if x == "{}" else [x])]
                why = rm_segment_problem(sub, cwds, env, depth + 1, None, remote, not named)
                if why:
                    return why
        return None
    if not remote:
        # rsync --delete / --del removes what the source lacks: judged like rm -r of the destination (2026-10-13)
        if prog == "rsync" and any(a == "--del" or a.startswith("--delete") for a in rest):
            ops = [a for a in rest if not a.startswith("-")]
            if len(ops) >= 2 and not re.match(r"^[^/]*:", ops[-1]):   # host:path / rsync:// is another machine
                why = rm_target_problem(ops[-1], cwds, env, False)
                if why:
                    return why + " (rsync --delete)"
            return None
        rim = rimraf_args(prog, rest)
        if rim is not None:
            return rm_segment_problem(["rm", "-rf", "--"] + rim, cwds, env, depth + 1)
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
        elif a not in repl and a != "":
            targets.append(a)
    rec = "r" in flags or "R" in flags or "--recursive" in longs
    force = rec and ("f" in flags or "--force" in longs)   # an rm that find makes recursive is judged as rm -r (no -f)
    if xargs:
        fed, from_find = (None, False) if xargs_file else feed_paths(feed)
        if not rec and not from_find:
            return None
        if fed is None and force:
            return "xargs rm: đường dẫn lấy từ lệnh trước, không đọc được (chỉ find / echo / printf literal được phân tích)"
        targets += fed or []
    elif not rec and not implied:
        return None
    for t in targets:
        if remote:
            why = remote_target_problem(t, cwds, env, remote)
            if why:
                return why
            continue
        for x in [t] + [b for b in braces(t) if b != t]:   # the raw word, then each brace expansion (rm -rf ~/{a,b})
            why = rm_target_problem(x, cwds, env, force)
            if why:
                return why
    return None

# find operators written escaped or quoted (\; \( \) and their quoted forms) are words of find, not shell separators
# (2026-10-09): split there, `find . \( … \) -delete` and `find . -exec … \; -delete` lost their -delete. An escaped
# backslash before them (`\\;`) is not an escape of the operator.
FIND_OP = re.compile(r"(?<!\\)((?:\\\\)*)\\([;()])|\x27([;()])\x27|\x22([;()])\x22")
FIND_OP_WORD = {";": " __ESC_SEMI__ ", "(": " __ESC_LP__ ", ")": " __ESC_RP__ "}

drop_comments = shell_norm.drop_comments   # one copy for both guards (issue #7)

def rm_problem(text, cwds, depth=0, remote=""):
    """Walk the command like the shell: `cd` moves the cwd (after `&&` for sure; after
    ; || | & both the old and the new directory stay possible), ( ) restores it. remote: the text runs on a device ("device")
    or a remote host ("ssh") (2026-10-13): no host variable or ~ applies there. A heredoc body is cut only for a message of a
    known option, the one file statement of a modeled command, or an interpreter program that cannot start a process and whose output nothing
    takes (shell_norm.heredocs, policy of 15/10); an unquoted body with a $ or a backtick is never cut (the shell runs its $( )).
    The text is walked once per reading (shell_norm.readings: continuations joined, and as typed): blocked when either reading is."""
    if depth > 5:
        return "lồng lệnh quá sâu để phân tích"
    if "<<" in text:   # an interpreter program that can start a process (backticks, qx, %x, system …) stays: its text is a command line
        # a body that stays is not quote-scoped (15/10 r6): the quote characters of its lines that do not close them are dropped, or they pair with a quote of another
        # body and hide the command between them from drop_comments and the lexer
        text, _open = shell_norm.scan_text(text, lambda h: h.kind == "data" or shell_norm.program_cut(h, text))
    env = {} if remote else {"HOME": os.path.expanduser("~"), "TMPDIR": os.environ.get("TMPDIR") or "/tmp"}
    for reading in shell_norm.readings(drop_comments(text)):
        why = rm_walk(reading, cwds, depth, remote, env)
        if why:
            return why
    return None

SEP_CHARS = set(";&|()\n")   # the characters of a separator word of shell_norm.lex_words (a newline is one)

def rm_walk(text, cwds, depth, remote, env):
    """rm_problem of one reading of the text (comments already cut, continuations already decided)."""
    # `…` is $(…): the lexer splits "$" from "(", so a target built from one stays "$…"
    # (unresolvable, refused) while the inner command is walked as its own segment.
    text = re.sub(r"`([^`]*)`?", r"$(\1)", text)
    text = FIND_OP.sub(lambda m: (m.group(1) or "") + FIND_OP_WORD[m.group(2) or m.group(3) or m.group(4)], text)
    try:
        if shell_norm.dq_nested_quote(text):   # "$(echo "a b"; rm -rf ~)": the lexer pairs the quotes across the substitution (15/10 r6): read it as text that does not parse
            raise ValueError("a double quote inside a command substitution inside double quotes")
        toks = shell_norm.lex_words(text)
    except ValueError:   # a quote left open: split at blanks, a newline is a separator of its own (it is no blank here)
        toks = [x.strip("\"\x27") for x in re.split(r"\s+|([;&|()]+)", text.replace("\n", " ; ")) if x and x.strip()]
    stack, seg, pending, feed = [], [], None, None
    for tk in toks + [";"]:
        if shell_norm.join_fd_dup(seg, tk):   # 2>&1 rm …: the & belongs to the redirect
            continue
        if not set(tk) <= SEP_CHARS:
            seg.append(tk)
            continue
        if seg:
            i = 0
            while i < len(seg) and (re.match(r"^[A-Za-z_]\w*=", seg[i]) or seg[i] in RM_WRAPPERS):
                i += 1
            head = os.path.basename(seg[i]) if i < len(seg) else ""
            if head in ("cd", "pushd", "popd"):
                # raw words: options (-L -P -e -@ --, pushd -n) are skipped, but "-" (cd -) and +N / -N (pushd +1) are not options
                args, k, opts = seg[i + 1:], 0, []
                while k < len(args) and args[k].startswith("-") and len(args[k]) > 1 and not re.fullmatch(r"-\d+", args[k]):
                    opts.append(args[k]); k += 1
                    if args[k - 1] == "--":
                        break
                arg = args[k] if k < len(args) else ("~" if head == "cd" else None)
                if head == "pushd" and "-n" in opts:
                    pass   # pushd -n only edits the directory stack: the shell stays where it is
                elif (head == "popd" or arg is None or arg == "-" or re.fullmatch(r"[+-]\d+", arg) or "$" in arg or GLOB.search(arg)
                      or (CDPATH_SET and not arg.startswith(("/", "~"))) or (remote and arg.startswith("~"))):
                    # popd / bare pushd / cd - / pushd +N come back to a directory this walk never saw; with CDPATH a relative
                    # name may resolve anywhere ("CDPATH=/opt cd data" enters /opt/data); the far home is unknown
                    pending = [None]
                else:
                    arg = arg if remote else os.path.expanduser(arg)
                    # c is None after `cd $VAR`: an absolute arg ignores it (join(None, arg) raised TypeError, rc 1, command ran)
                    pending = [os.path.normpath(os.path.join(c or "/", arg)) if c or os.path.isabs(arg) else None
                               for c in cwds]
            else:
                why = rm_segment_problem(seg, cwds, env, depth, feed, remote)
                if why:
                    return why
            for tok_seg in seg:  # "$(…)" / `…` inside a quoted word runs too
                if "(" in tok_seg and depth < 5:
                    why = rm_problem(tok_seg.split("(", 1)[1].rstrip(")"), cwds, depth + 1, remote)
                    if why:
                        return why
        if pending is not None:
            cwds = list(dict.fromkeys(pending if tk.strip("\n") == "&&" else cwds + pending))   # && then a newline is still &&
            pending = None
        if "(" in tk:
            stack.append(cwds)
        if ")" in tk and stack:
            cwds = stack.pop()
        feed = seg if ("|" in tk and "||" not in tk and not tk.startswith(")")) else None   # what `| xargs rm` reads
        seg = []
    return None

CDPATH_SET = bool(os.environ.get("CDPATH")) or "CDPATH" in cmd   # set in the environment or anywhere in the command
rm_why = None if (label or MCP) else rm_problem(cmd, [CWD])
if MCP and not label:   # (2026-10-13) the command of replicant adb-shell runs on the device: walked like adb shell "<command>"
    _dev = inp.get("command") if tool == "mcp__replicant-mcp__adb-shell" and isinstance(inp, dict) else None
    rm_why = rm_problem(_dev, ["/"], 0, "device") if isinstance(_dev, str) and _dev.strip() else None


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
# Shell words that open a command inside a compound one: "if …; then adb -s X reboot; fi" and
# "for …; do adb …; done" reached the device unseen (review 2026-09-27).
SHELL_LEAD = {"if", "then", "else", "elif", "while", "until", "do", "!", "{", "("}

def adb_calls(text):
    """(adb executable token, selection options, subcommand, ANDROID_SERIAL, words after
    the subcommand) per adb call."""
    for seg in re.split(r"[;&|\n]+|\$\(|`", text):
        try:
            toks = shlex.split(seg)
        except ValueError:
            toks = seg.split()
        toks = shell_norm.inline_script(toks)   # sudo -s STR, env -S STR
        env_serial = os.environ.get("ANDROID_SERIAL", "")
        # Only the word in command position (after VAR=… and sudo/env/timeout N …):
        # `grep adb notes.txt` is not an adb call.
        i = 0
        while i < len(toks) and (re.match(r"^\w+=", toks[i]) or toks[i] in ADB_WRAPPERS or toks[i] in SHELL_LEAD
                                 or (i > 0 and toks[i - 1] in ADB_WRAPPERS and re.match(r"^(-\S*|\d+\w?)$", toks[i]))):
            if toks[i].startswith("ANDROID_SERIAL="):
                env_serial = toks[i].split("=", 1)[1]
            i += 1
        i = max(i, prefix_end(toks, True))   # (15/10, OCR) a wrapper option VALUE before a shell / su: sudo -u me bash -lc "adb …"
        if i < len(toks) and os.path.basename(toks[i]) in ("bash", "sh", "zsh") and "-c" in toks[i:]:
            k = toks.index("-c", i)
            if k + 1 < len(toks):
                yield from adb_calls(toks[k + 1])
            continue
        # (14/10, W3) the script of a shell or su in any spelling (bash -lc, su -c, su USER CMD …): shell_norm
        prog0 = os.path.basename(toks[i]) if i < len(toks) else ""
        ran = (shell_norm.su_command(toks[i + 1:]) if prog0 == "su"
               else ("script", shell_norm.shell_script(toks[i + 1:])) if prog0 in shell_norm.SHELLS else None)
        if ran and ran[1]:
            yield from adb_calls(ran[1] if ran[0] == "script" else " ".join(shlex.quote(w) for w in ran[1]))
            continue
        if i < len(toks) and os.path.basename(toks[i].lstrip("(")) not in ("adb", "adb.exe"):
            j = prefix_end(toks, True)   # (2026-10-13) a wrapper option value before adb: sudo -u me adb -s X …
            if j < len(toks) and os.path.basename(toks[j]) in ("adb", "adb.exe"):
                i = j
        if i < len(toks):
            toks[i] = toks[i].lstrip("(")                # "(adb -s X shell ls)"
        if i >= len(toks) or os.path.basename(toks[i]) not in ("adb", "adb.exe"):
            continue
        opts, j = [], i + 1
        while j < len(toks) and toks[j].startswith("-"):
            if toks[j] in ADB_VALUE_OPTS and j + 1 < len(toks):
                opts += toks[j:j + 2]; j += 2
            else:
                opts.append(toks[j]); j += 1
        while j < len(toks) and re.fullmatch(r"wait-for-[\w-]+", toks[j]):   # adb wait-for-device remount
            j += 1
        yield toks[i], opts, (toks[j] if j < len(toks) else ""), env_serial, toks[j + 1:]

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

# A serial set to a literal earlier in the same command is known (GeelyEx2 2026-09-27:
# "E=emulator-5554; adb -s $E" was refused twice). Only NAME=literal followed by ; && || or a
# newline counts (a prefix "E=x adb -s $E" does not set $E for that adb); a name assigned
# anything else as well (declare, a second value, a for/read loop) stays unknown.
ASSIGN_ANY = re.compile(r"(?<![\w$.-])([A-Za-z_]\w*)=")
ASSIGN_LIT = re.compile(r"(?:^|[;&|(\n]|\bexport)\s*([A-Za-z_]\w*)=([\w.:-]+)(?=[ \t]*(?:$|;|&&|\|\||\n))", re.M)

def literal_vars(text):
    lits, counts = {}, {}
    for name in ASSIGN_ANY.findall(text):
        counts[name] = counts.get(name, 0) + 1
    for name, val in ASSIGN_LIT.findall(text):
        lits.setdefault(name, []).append(val)
    return {n: v[0] for n, v in lits.items() if len(v) == counts.get(n) and len(set(v)) == 1
            and not re.search(r"\b(?:for|read|select|getopts|mapfile|readarray)\b[^;&|\n]*\b"
                              + re.escape(n) + r"\b", text)}

def expand_literals(word, lits):
    return re.sub(r"\$\{?([A-Za-z_]\w*)\}?", lambda m: lits.get(m.group(1), m.group(0)), word)

def target_serial(exe, opts, env_serial, lits=None):
    """(serial, None) · (None, None) when adb itself would find no single target
    (the command then fails on its own) · (None, why) when it cannot be resolved."""
    lits = lits or {}
    env_serial = expand_literals(env_serial, lits)
    if "-s" in opts:
        s = os.path.expandvars(expand_literals(opts[opts.index("-s") + 1], lits))
        if "$" in s:
            return (None, "serial " + s + " không xác định được")
        if any(s.startswith(pfx) for pfx in ("model:", "usb:", "product:", "device:")):
            adb = exe if "/" in exe and os.access(exe, os.X_OK) else (shutil.which("adb") or sdk_adb())
            if adb:
                try:
                    r = subprocess.run([adb] + opts + ["get-serialno"], capture_output=True, text=True, timeout=8)
                    resolved = r.stdout.strip()
                    if r.returncode == 0 and resolved and resolved != "unknown":
                        return (resolved, None)
                except Exception:
                    pass
        return (s, None)
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
    lits = literal_vars(text)
    for exe, opts, sub, env_serial, _rest in adb_calls(text):
        if not sub or sub in ADB_HOST_ONLY:
            continue
        serial, why = target_serial(exe, opts, env_serial, lits)
        if why:
            return "không xác định được thiết bị đích (" + why + ") — " + (
                "chọn thiết bị bằng adb-device select" if MCP else "ghi rõ adb -s <SERIAL>")
        if serial and serial in deny:
            return "thiết bị " + serial + " nằm trong denylist (máy cá nhân / cấm đụng)"
        if serial and allow and serial not in allow:
            return "thiết bị " + serial + " không có trong allowlist"
    return None

def active_profile():
    try:
        with open(os.path.join(os.environ.get("REPO_ROOT", "."), ".agents", "active-profile.json"),
                  encoding="utf-8") as fh:
            return str(json.load(fh).get("profile") or "")
    except (OSError, ValueError, AttributeError):
        return ""  # no profile: not automotive — this rule protects a log, not the device

# Flags that make logcat end on its own: dump / clear / ring-buffer size / statistics / prune.
# A value glued to another option (-vtime, -bcrash) is not one of them.
LOGCAT_ENDS = re.compile(r"^-([dcgGLSpP]+|t\d*)$")
LOGCAT_ENDS_LONG = {"--clear", "--last", "--buffer-size", "--dump", "--statistics", "--prune"}
# Words that may stand before logcat in its own device command (nohup logcat …).
LOGCAT_LEAD = {"nohup", "setsid", "exec", "busybox", "toybox", "timeout", "su", "0", "root"}
CAR_PATH = re.compile(r"^/(data|sdcard|storage)/")

def logcat_violation(text):
    """An adb logcat that streams to this computer; None for a dump or a logcat detached
    on the car. adb_calls splits at & | ; before shlex, so a quoted device command may
    come back as loose words (\x22logcat): quotes are stripped, and a detached one is
    told by its "… &\x22" closing the quoted command."""
    # "… logcat … &\x22": the logcat of that quoted device command runs in the background.
    detached = re.search(r"\blogcat\b[^;&|\x22\x27\n]*&\s*[\x22\x27]\s*($|[;&|)\n])", text) is not None
    for _exe, _opts, sub, _serial, rest in adb_calls(text):
        words = [w.strip("\x22\x27") for w in " ".join(rest).split()]
        if sub in ("shell", "exec-out") and "logcat" in words:
            k = words.index("logcat")
            pre, args = words[:k], words[k + 1:]
            if not all(w in LOGCAT_LEAD or w.isdigit() for w in pre):
                continue   # logcat is an argument (pkill logcat, pidof logcat), not the command
        elif sub == "logcat":
            pre, args = None, words
        else:
            continue
        if any(LOGCAT_ENDS.match(a) or a.split("=", 1)[0] in LOGCAT_ENDS_LONG for a in args):
            continue
        on_car = False
        for n, a in enumerate(args):
            t = (args[n + 1] if a in (">", ">>", "-f", "--file") and n + 1 < len(args)
                 else a.lstrip(">") if a.startswith(">")
                 else a.split("=", 1)[1] if a.startswith("--file=") else "")
            on_car = on_car or bool(CAR_PATH.match(t))
        if pre is not None and on_car and (detached or {"nohup", "setsid"} & set(pre)):
            continue
        return " ".join(["adb", sub] + rest)
    return None

if rm_why:
    sys.stderr.write("\n🛑 [HARDWARE SAFETY GATE REJECTED]\n")
    sys.stderr.write("rm đệ quy (-rf, -fr, -r -f, --recursive --force; cả find -delete / -exec rm, xargs rm; rm -r không -f trên gốc\n"
                     "project / home / / / phân vùng hệ thống — không có terminal thì rm -r không hỏi) bị chặn — xoá không đảo ngược được:\n")
    sys.stderr.write(f"  • {rm_why}\n")
    sys.stderr.write(f"  • Lệnh: {cmd}\n\n")
    sys.stderr.write("Được phép: build output trong project (build/, dist/, node_modules/, .gradle/, Library/, Temp/, obj/, bin/ …\n"
                     "không bị git track), đường dẫn trong /tmp hoặc $TMPDIR, thư mục từ cấp 2 trong project, một file đơn.\n"
                     "Nếu thật sự cần, người dùng tự chạy lệnh qua prefix `!` (hoặc HARDWARE_OVERRIDE=1).\n")
    sys.exit(2)

if label is None:
    dev = next(filter(None, (device_violation(t) for t in TEXTS)), None)
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

def emulator_window_violation(text):
    """Chặn lệnh mở Android Emulator khởi động AVD mà thiếu cờ -no-window (trừ khi PROOF_WINDOW=1)."""
    # Lệnh không nhắc tới emulator/qemu-system/-avd (sau khi bỏ dấu nháy và \, như shlex ghép e"m"ulator) thì không có gì
    # để chặn: thoát ngay. 20/10: tách theo từng dòng một lệnh eval vô hại 12000 dòng mất 3,7–5,8 s, chạm hạn 7 s của hook
    # khi máy tải nặng và bị chặn fail-closed (test_hw_emulator_window.sh). Đoạn python này nằm trong chuỗi bash nháy đơn:
    # không viết dấu nháy đơn, dùng \x27.
    if not re.search(r"emulator|qemu-system|-avd", re.sub(r"[\"\x27\\]", "", text)):
        return None
    lits = literal_vars(text)
    if os.environ.get("PROOF_WINDOW", lits.get("PROOF_WINDOW", "")).strip().lower() in ("1", "true", "yes", "on"):
        return None
    for seg in re.split(r"[;&|\n]+|\$\(|`", text):
        try:
            toks = shlex.split(seg)
        except ValueError:
            toks = seg.split()
        toks = shell_norm.inline_script(toks)
        seg_win = False
        i = 0
        while i < len(toks):
            w0 = toks[i].lstrip("(")
            if not (re.match(r"^\w+=", w0) or w0 in ADB_WRAPPERS or w0 in SHELL_LEAD or toks[i] in SHELL_LEAD
                    or (i > 0 and toks[i - 1].lstrip("(") in ADB_WRAPPERS and re.match(r"^(-\S*|\d+\w?)$", w0))):
                break
            if w0.startswith("PROOF_WINDOW=") and w0.split("=", 1)[1].strip().lower() in ("1", "true", "yes", "on"):
                seg_win = True
            i += 1
        if seg_win:
            continue
        i = max(i, prefix_end(toks, True))
        if i < len(toks) and os.path.basename(toks[i]) in ("bash", "sh", "zsh") and "-c" in toks[i:]:
            k = toks.index("-c", i)
            if k + 1 < len(toks):
                hit = emulator_window_violation(toks[k + 1])
                if hit:
                    return hit
            continue
        prog0 = os.path.basename(toks[i].lstrip("(")) if i < len(toks) else ""
        ran = (shell_norm.su_command(toks[i + 1:]) if prog0 == "su"
               else ("script", shell_norm.shell_script(toks[i + 1:])) if prog0 in shell_norm.SHELLS else None)
        if ran and ran[1]:
            hit = emulator_window_violation(ran[1] if ran[0] == "script" else " ".join(shlex.quote(w) for w in ran[1]))
            if hit:
                return hit
            continue
        if i >= len(toks):
            continue
        exe = toks[i].lstrip("(")
        base = os.path.basename(exe)
        args = [a.rstrip(")") for a in toks[i + 1:]]
        has_avd = "-avd" in args or any(a.startswith(("-avd=", "@")) and len(a) > 1 for a in args)
        is_emu = base in ("emulator", "emulator.exe") or base.startswith("qemu-system-") or (base.startswith("$") and ("-avd" in args or any(a.startswith("-avd=") for a in args)))
        if not is_emu or not has_avd:
            continue
        if any(a in ("-list-avds", "-version", "-help", "-help-all", "--help") for a in args):
            continue
        if "-no-window" not in args:
            return " ".join([exe] + args)
    return None

if not MCP:
    emu_win = next(filter(None, (emulator_window_violation(t) for t in TEXTS)), None)
    if emu_win:
        sys.stderr.write("\n🛑 [HARDWARE SAFETY GATE REJECTED]\n")
        sys.stderr.write("Lệnh khởi chạy Android Emulator thiếu cờ `-no-window` bị chặn (mở cửa sổ GUI làm phiền người dùng):\n")
        sys.stderr.write(f"  • {emu_win}\n")
        sys.stderr.write(f"  • Lệnh: {shown}\n\n")
        sys.stderr.write("Bắt buộc chạy máy ảo ngầm (headless) dưới background bằng cách thêm `-no-window -no-audio -no-boot-anim`\n"
                         "hoặc gọi `python3 .agents/devkit/bin/proof-capture.py` (mặc định chạy `-no-window`). Nếu cần hiện cửa sổ, đặt `PROOF_WINDOW=1`.\n")
        sys.exit(2)

if not MCP and active_profile() == "automotive":
    lc = next(filter(None, (logcat_violation(t) for t in TEXTS)), None)
    if lc:
        sys.stderr.write("\n🛑 [HARDWARE SAFETY GATE REJECTED]\n")
        sys.stderr.write("Profile automotive: logcat chạy stream về máy tính bị chặn — ADB Wi-Fi tới xe rớt là log chết theo:\n")
        sys.stderr.write(f"  • {lc}\n")
        sys.stderr.write(f"  • Lệnh: {shown}\n\n")
        sys.stderr.write("Ghi log ngay trên xe rồi kéo về:\n"
                         "  • chụp một lần: adb shell \"logcat -d > /data/local/tmp/x.txt\" rồi adb pull /data/local/tmp/x.txt\n"
                         "  • ghi suốt phép đo: adb shell \"nohup logcat -f /data/local/tmp/x.txt &\" … rồi adb pull\n"
                         "  • hoặc adb logcat -d / -t <N> (đọc xong là thoát). Xem GeelyEx2 INSTINCT-099.\n")
        sys.exit(2)
sys.exit(0)
' "$0"
rc=$?
case "${rc}" in 0|2) exit "${rc}" ;; esac
echo "🛑 [HARDWARE SAFETY GATE] python không chạy được (rc ${rc}) — chặn để an toàn (người dùng tự chạy lệnh qua prefix ! hoặc HARDWARE_OVERRIDE=1)." >&2
exit 2
