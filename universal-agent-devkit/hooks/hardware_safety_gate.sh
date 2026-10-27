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
#   • (2026-10-26, #427, tests/gates/test_hardware_issue427.sh) rm -r (cả không -f, find -delete) đi qua một tên mà ln của CHÍNH lệnh đó ghi
#     (`ln -s ~ <scratch>/l && rm -rf <scratch>/l/`: link chưa có lúc hook xét); build output git track ở hoa thường khác (core.ignorecase).
#   • (2026-10-27, #427 vòng 2, tests/gates/test_hardware_backlog427.sh) không theo thứ tự: mọi tên link của cả lệnh được gom trước (rm trong
#     vòng lặp đứng trước ln); link tạo bằng cp -s, mv (tên đích), os.symlink / symlinkSync / symlink trong python -c / node -e / perl -e;
#     rm -r xuyên qua một mục của thư mục mà tar -x / unzip của lệnh giải nén vào; cùng phép đó trong adb shell / ssh; glob [^…], [[:alpha:]],
#     {a..c} xét theo kết quả khớp của shell; git lỗi (trừ rc 128 "not a git repository (or any …") xét như build output đang track.
#     Review vòng 2: {x..y} xét cả từng từ zsh bung (tên chưa có: build/x/{1..2}/../../../src); thân trap / repeat biết phép gán không bị
#     gán lại; NAME=VAL trước một lệnh không còn đặt biến cho các lệnh sau; mv vào thư mục ghi tên nguồn; tên link của adb shell chỉ cho lệnh
#     thiết bị; RERUN_RX tuyến tính, git ls-files nhớ theo đường dẫn. Lượt sau: export / readonly / declare -g gán biến (local, unset, read,
#     NAME+= … làm nó không biết); biến gán trong vùng lặp không biết trong và sau vùng đó; T=$(mktemp -d) là một đường dẫn tạm; phép gán
#     trong ( … ), chặng ống, chạy nền, sau && / ||, if / case, thân hàm không còn đặt biến cho lệnh sau như phép gán chắc chắn.
#   • (2026-10-27, #427 vòng 3, tests/gates/test_hardware_round3_427.sh) tên glob rồi `..` (build/x/*/../../../src: tên chưa có lúc hook xét)
#     xét thêm với mỗi tên glob là một tên thường; rm -r không -f sau cd vào link chính lệnh tạo; thân trap xét với mọi cwd từ trap tới lúc
#     thoát; cp -R / -a / -P, rsync -a / -l, git clone, 7z x, ditto, cpio -i chép / giải nén link (luật của tar); script dưới project mà lệnh
#     chạy (bash x.sh, ./x.sh, source x.sh; < 64 KB) được đọc để gom lệnh tạo link của nó.
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
# The Bash tool runs /bin/zsh here (measured, OCR round 3), not bash. zsh reads a ( glued to a word as a GLOB QUALIFIER of that word:
# build/a(:a:h:h) is the project root, build/*(e:…:) any path its code names. bash refuses the line; the lexer made the ( a subshell and
# judged `build/a`. zsh_qualifiers marks the word; rm_target_problem refuses a target holding the marker (with -f).
ZSH_QUAL = "__ZSH_GLOB_QUALIFIER__"

def zsh_qualifiers(text):
    """text with ZSH_QUAL glued to every word a ( is glued to, the ( set apart: what it holds is still walked as before (a perl qx(…) or
    ruby %x(…) of a kept heredoc body runs its command). Not one: quoted, after $ < > = ( or a separator ($( … ), <( … ), a=( … ),
    (( … ))), and an empty () (a function)."""
    out, i, n, q = [], 0, len(text), None
    while i < n:
        c = text[i]
        if q:   # inside quotes, copied as it is
            out.append(c)
            if c == "\\" and q == "\x22" and i + 1 < n:
                out.append(text[i + 1])
                i += 1
            elif c == q:
                q = None
        elif c == "\\":
            out.append(text[i:i + 2])
            i += 1
        elif c in "\x27\x22":
            q = c
            out.append(c)
        elif c == "(" and i and not text[i - 1].isspace() and text[i - 1] not in "$<>=(;&|" and not text.startswith("()", i):
            out.append(ZSH_QUAL + " (")
        else:
            out.append(c)
        i += 1
    return "".join(out)

def under(p, d):
    return p != d and p.startswith(d.rstrip(os.sep) + os.sep)

_ICASE = []   # core.ignorecase của project, đọc một lần (git_tracks có thể chạy cho nhiều đích trong một lệnh)
_TRACKS = {}  # review #427 vòng 2: kết quả theo đường dẫn — lượt 2 của rm_problem xét lại cùng đích (500 rm: 1000 lần git, 5 s)

def git_tracks(p):
    if p not in _TRACKS:
        _TRACKS[p] = _git_tracks(p)
    return _TRACKS[p]

def _git_tracks(p):
    # H4 (#427): ls-files so pathspec phân biệt hoa thường dù core.ignorecase=true: `rm -rf build` khi `Build/` được track (APFS) lọt như
    # build output không track. Dùng :(icase) khi git nói core.ignorecase là true; chưa đặt (rc 1) là false như git; đọc lỗi thì icase.
    if not _ICASE:
        try:
            c = subprocess.run(["git", "-C", ROOT, "config", "--bool", "core.ignorecase"], capture_output=True, text=True, timeout=5)
            _ICASE.append(c.stdout.strip() == "true" if c.returncode in (0, 1) else True)
        except (OSError, subprocess.SubprocessError):
            _ICASE.append(True)
    # GIT_LITERAL_PATHSPECS=1 thừa kế từ môi trường làm git đọc ":(icase)build" như một tên thật: không file nào khớp, mọi build output
    # được track lọt (review #427). Bỏ các biến *_PATHSPECS khỏi env của lệnh này.
    env = {k: v for k, v in os.environ.items() if k not in ("GIT_LITERAL_PATHSPECS", "GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS",
                                                               "GIT_ICASE_PATHSPECS")}
    env["LC_ALL"] = "C"   # thông báo lỗi của git không bị dịch: phép so "not a git repository" bên dưới đọc bản tiếng Anh
    try:
        r = subprocess.run(["git", "-C", ROOT, "ls-files", "--", (":(icase)" if _ICASE[0] else "") + os.path.relpath(p, ROOT)],
                           capture_output=True, text=True, timeout=5, env=env)
    except (OSError, subprocess.SubprocessError):
        return True   # #427 vòng 2: git không chạy được / quá hạn — không biết, xét như đang track (chặn)
    if r.returncode == 0:
        return bool(r.stdout.strip())
    # #427 vòng 2: mọi rc ≠ 0 từng là "không track" (cho xoá). Nay chỉ rc 128 "not a git repository (or any …" — project ngoài git — là
    # không track; git lỗi khác (index hỏng, worktree mất gitdir "not a git repository: <path>", rc khác) xét như đang track.
    return not (r.returncode == 128 and "not a git repository (or any" in r.stderr)

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

def rel_below(p, d):
    """The names from the folder d down to the resolved path p: [] when p is d, None when p is not under d. Compared by inode, so another
    spelling of the same folder (another case on APFS) counts; a name that does not exist yet is matched through its parents (principal
    review round 2, 25/10, B3: `rm -rf <parent>/PROJ` of the project `<parent>/Proj` was judged as another folder)."""
    try:
        sd = os.stat(d)
    except OSError:
        sd = None
    names, q = [], p
    while True:
        if q == d:
            return names[::-1]
        if sd is not None:
            try:
                if os.path.samestat(os.lstat(q), sd):
                    return names[::-1]
            except OSError:
                pass
        up = os.path.dirname(q)
        if up == q:
            return None
        names.append(os.path.basename(q))
        q = up

def scratch_root(path, roots):
    """(name, below) for the entry of roots ([(name, stat)]) that is the resolved path (below False) or holds it (below True), compared by
    inode (APFS: /private/tmp/CLAUDE-501 is the same folder), else None. A name that does not exist yet is judged by its parents."""
    d, below = path, False
    while roots:
        try:
            st = os.lstat(d)
            hit = next((r for r, s in roots if os.path.samestat(st, s)), None)
            if hit:
                return hit, below
        except OSError:
            pass
        up = os.path.dirname(d)
        if up == d:
            break
        d, below = up, True
    return None

def scratch_escape(base, t, p, reach):
    """Why rm -rf of t, run in the folder base (/ for an absolute t), reaches outside the agent scratch folder although it is in it; None
    when it stays or is not in it. In it = the folder rm works in (the resolved parent), or a folder the path passes through before a `..`
    (read before anything resolves it), is the scratch folder or under it. Stays = all rm removes is UNDER the scratch folder (emptying the
    folder itself is no session scratch): p (rm_reach of t; for a glob, the folder before it) and reach (where the current matches of a
    glob land; None: not walked, they stay in p). A `..` that stays in it is no escape (principal review round 2, A4)."""
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
    hit = scratch_root(os.path.realpath(os.path.dirname(raw.rstrip("/") or "/")), roots) or next(
        (h for h in (scratch_root(os.path.realpath("/".join(parts[:i]) or "/"), roots) for i, x in enumerate(parts) if x == "..") if h), None)
    if hit is None:
        return None
    out = next((q for q in [p] + (reach or []) if not (scratch_root(q, roots) or ("", False))[1]), None)
    return f"ra khỏi thư mục scratch {hit[0]} (tới {out})" if out else None

GLOB_CAP = 2000   # matches of one glob walked to see where they land (principal review round 2, A2: the 2001st on was never judged)
# #427 vòng 2: các kết quả khớp được xét phải là của shell (zsh, bash), không ít hơn. Python glob đọc khác ở ba chỗ, kết quả khớp thật (một
# link tới home) không được xét: {a..c} (shell_norm.braces chỉ bung danh sách có dấu phẩy) → xét như *; [^…] (Python đọc ^ là chữ) → [!…];
# bracket có lớp POSIX [[:alpha:]] (Python không biết) → ? (khớp mọi ký tự: tập lớn hơn, chỉ chặn nhiều hơn).
BRACE_SEQ = re.compile(r"(?<!\$)\{[^{},]*\.\.[^{},]*\}")
POSIX_BRACKET = re.compile(r"\[!?\]?(?:\[:\w+:\]|[^\]\[])*\[:\w+:\](?:\[:\w+:\]|[^\]\[])*\]")

def shell_glob(t):
    """Glob t viết lại cho Python glob khớp như shell (xem trên)."""
    return POSIX_BRACKET.sub("?", t.replace("[^", "[!"))

# Review #427 vòng 2 (P1 mất dữ liệu): dạng glob của {a..b} chỉ thấy tên ĐÃ có — `mkdir -p build/x/1 && rm -rf build/x/{1..2}/../../../src`
# không khớp gì lúc hook xét, chỉ build/x được xét, src/ bị xoá. Nay xét thêm các từ shell bung ra. zsh (Bash tool) bung khoảng ký tự gồm
# mọi ký tự, kể cả . và / (đo 27/10: build/q{-..0}.. thành build/q/..). Mọi số, mọi ký tự thường là một tên thường như nhau (tên đã có
# thì dạng glob vẫn xét): mỗi dãy giữ một đại diện cộng từng ký tự trong SEQ_SPECIAL.
SEQ_SPECIAL = "./~$\x60*?[]"
GLOB_NAME = "__devkit_glob_name__"   # #427 vòng 3: tên thường thay cho một tên glob (rm_target_problem, glob rồi `..`)

def seq_words(t):
    """Các từ của t khi mỗi {x..y} / {x..y..s} được bung như zsh (số: đại diện là số đầu; khoảng ký tự: một ký tự thường và mọi ký tự của
    SEQ_SPECIAL trong khoảng); dãy không bung được (bash 3.2 không bung {-..0}) giữ nguyên chữ. None khi quá GLOB_CAP từ."""
    out, pos = [""], 0
    for m in BRACE_SEQ.finditer(t):
        inner, elems = m.group(0)[1:-1], []
        num = re.fullmatch(r"(-?\d+)\.\.-?\d+(?:\.\.-?\d+)?", inner)
        if num:
            elems.append(num.group(1))
        for k in range(1, len(inner) - 2):   # mọi cách tách c1..c2[..bước] (zsh đọc {...0} là . tới 0)
            c1, c2 = inner[:k], inner[k + 2:]
            c2 = c2[:1] if re.fullmatch(r".\.\.-?\d+", c2, re.S) else c2
            if inner[k:k + 2] != ".." or len(c1) != 1 or len(c2) != 1:
                continue
            lo, hi = sorted((ord(c1), ord(c2)))
            plain = next((chr(c) for c in range(lo, hi + 1) if chr(c) not in SEQ_SPECIAL), None)
            elems += ([plain] if plain else []) + [c for c in SEQ_SPECIAL if lo <= ord(c) <= hi]
        elems = list(dict.fromkeys(elems)) or [m.group(0)]
        out = [o + t[pos:m.start()] + e for o in out for e in elems]
        if len(out) > GLOB_CAP:
            return None
        pos = m.end()
    return [o + t[pos:] for o in out]

def glob_may_leave(t):
    """True when the matches of the glob t can land outside the folder before it: a trailing / (rm follows a matched link) or a glob in a
    name that is not the last one (the path goes on through each match). A glob in the last name only names entries of that folder."""
    return t.endswith("/") or any(GLOB.search(x) for x in t.rstrip("/").split("/")[:-1])

def zsh_starstar(t):
    """None when the glob t has no zsh ** / ***. "" when its ** cannot leave the folder before it: no ***, the last name is a name (not
    empty — a trailing / — nor . or ..), and ** is the whole name just before it with no other glob before (build/**/*.o, build/**/tmp:
    zsh **/ follows no link, rm removes a matched link itself). Else why it cannot be judged: *** follows links, and Python glob walks
    neither like zsh (OCR round 3, H1)."""
    if "**" not in t:
        return None
    names = t.split("/")
    before = names[:-1]
    if "***" not in t and names[-1] not in ("", ".", ".."):
        deep = [i for i, x in enumerate(before) if "**" in x]
        if not deep or (deep == [len(before) - 1] and before[-1] == "**" and not any(GLOB.search(x) for x in before[:-1])):
            return ""
    return ("** / *** của zsh (*** đi theo link; ** có dấu / cuối, tên sau nó không phải tên cuối, hay glob khác trước nó): "
            "Python glob không duyệt được như zsh, không biết kết quả tới đâu")

# #427: link do chính lệnh này tạo (ln …) chưa có lúc hook chạy, nên `ln -s ~ <scratch>/l && rm -rf <scratch>/l/` được xét như thư mục thường
# của scratch / /tmp / build output; chạy thật thì rm đi theo link (dấu / sau nó, đường dẫn bên dưới nó) và xoá nội dung nơi link trỏ tới.
# rm_command_problem ghi vào đây tên (casefold) mọi toán hạng của ln — cả nguồn: `ln -s ~ dir` tạo dir/<user>; "*" khi một toán hạng không
# đọc được ($VAR chưa gán, lệnh con, glob, {} của find / xargs).
# #427 vòng 2: rm chạy lại sau ln (vòng lặp, hàm, chạy nền: rm_problem lượt 2 xét với mọi tên); cũng ghi tên của cp -s, mv (đích), API tạo
# link của interpreter ("*"), và thư mục giải nén của tar -x / unzip (EXTRACT_DIRS).
# #427 vòng 3: cp -R / -a / -P, rsync -a, git clone, 7z, ditto, cpio (copied, git_clone_dir, extract_dirs); script shell dưới project mà
# lệnh chạy (script_links). ponytail: script ngoài project / từ 64 KB / python x.py, git checkout / worktree add / pull, gh repo clone,
# pax / unrar / jar vẫn không được xét. Nâng cấp khi gặp ca thật (thêm lệnh vào rm_command_problem).
LINKS_MADE = set()
# Review #427 vòng 2 (P2 chặn nhầm): tên do lệnh chạy trên THIẾT BỊ (adb shell "…") tạo không có trên máy này — `adb shell "cd /data/local/tmp
# && tar -xf x.tar" && rm -rf build/tmp/` từng bị chặn. Chúng vào DEVICE_LINKS, chung cho mọi lệnh thiết bị của cả lệnh (adb shell "ln …" rồi
# adb shell "rm …"); lệnh thiết bị vẫn thấy tên của máy này (adb push một link). ssh không tách: máy kia có thể chính là máy này (ssh localhost).
DEVICE_LINKS = set()

def ln_names(rest, env, repl, xargs):
    """Tên (casefold) các toán hạng của một lệnh ln (rest: các từ sau ln); "*" cho toán hạng không đọc được."""
    names, opts_done = set(), False
    for a in rest:
        if not opts_done and a.startswith("-"):   # tuỳ chọn (cả giá trị của -t / -S: thêm tên thừa thì chỉ chặn nhiều hơn)
            opts_done = a == "--"
            continue
        if a in repl:
            names.add("*")
            continue
        v = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), a)
        v = os.path.expanduser(v) if v.startswith("~") else v
        for x in [v] + braces(v):
            name = os.path.basename(x.rstrip("/"))
            # Xét trên basename, không trên cả toán hạng: `ln -s $PWD/node_modules $S/node_modules` vẫn biết tên link (review #427).
            # Nhưng toán hạng còn `${…:-…}` / `${…/…}`, `$(`, backtick thì dấu / cuối có thể nằm trong phép mở rộng (basename `l}`,
            # `l)`): tên link thật không biết, là "*" (OCR review #427).
            # `"$(pwd)/x"`: dấu / cuối nằm sau phép mở rộng cuối cùng, basename `x` vẫn đọc được.
            opaque = ((re.search(r"\$\(|`|\$\{[^}]*[^\w}]", x) and "/" not in x[max(x.rfind(")"), x.rfind("}"), x.rfind("`")) + 1:])
                      or re.search(r"[$`{}()]", name))
            names.add("*" if opaque or GLOB.search(name) else name.casefold())
    if xargs:   # xargs ln: toán hạng lấy từ lệnh trước
        names.add("*")
    return names - {"", ".", ".."}

def made_link_name(t):
    """Tên trong t mà rm -r đi xuyên qua (có dấu / theo sau) và có thể là link do chính lệnh này tạo (LINKS_MADE), hoặc None. So casefold
    (APFS không phân biệt hoa thường); một tên là glob, hay một toán hạng ln không đọc được, thì coi như có thể trùng."""
    if not LINKS_MADE:
        return None
    for x in t.split("/")[:-1]:
        if x not in ("", ".", "..") and ("*" in LINKS_MADE or GLOB.search(x) or "$" in x or "`" in x or x.casefold() in LINKS_MADE
                                         or any(n[:1] == "*" and x.casefold().endswith(n[1:]) for n in LINKS_MADE)):   # mẫu đuôi của mv_dest
            return x
    return None

# #427 vòng 2: lời gọi tạo link trong chương trình của interpreter (os.symlink(, fs.symlinkSync(, symlink( / symlink $x của perl / php,
# Path.symlink_to(, FileUtils.ln_s): tên link không đọc được → "*". Chỉ dạng lời gọi: chữ "symlink" trong một câu (message commit, chú thích,
# --mode=symlink) không tính (corpus 27/10: 6 lệnh thật bị chặn nhầm). SYMLINK_API thêm `ln -s` trong một chuỗi (os.system("ln -s …"),
# ["ln", "-s", …]): cho chương trình interpreter; thân heredoc shell đã được duyệt như lệnh, ln của nó có tên.
SYMLINK_CALL = r"\bsymlink(?:Sync)?\s*\(|\.symlink_to\s*\(|\bln_sf?\b|\bsymlink\s+[$\x22\x27]"
SYMLINK_API = re.compile(SYMLINK_CALL + r"|\bln\b\W{1,8}-[A-Za-z]*s\b", re.I)
SYMLINK_CALL = re.compile(SYMLINK_CALL, re.I)
# Thư mục (realpath) mà tar -x / unzip của chính lệnh giải nén vào: một mục bên dưới nó có thể là link trong file nén, chưa có lúc hook xét.
# #427 vòng 3: cả 7z x, cpio -i, git clone, và thư mục mà cp -R / rsync -a / ditto chép các mục vào.
EXTRACT_DIRS = set()
# #427 vòng 3: đích (realpath) của cp -R / -a / -P, rsync -a, ditto chép MỘT nguồn có thể là link (link, chưa có, không đọc được): chính đích
# có thể là link — rm -r đi qua nó (dấu / sau nó, đường dẫn bên dưới) bị chặn; xoá chính nó (không dấu /) vẫn được.
COPY_DESTS = set()
# #427 vòng 3: đích (realpath) → nguồn (realpath) của cp -R / rsync -a / ditto mà mọi nguồn là cây có thật lúc hook xét: một mục dưới đích
# chỉ là link khi mục tương ứng của nguồn là link (extracted_entry so cả hai cách đặt: đích/x ↔ nguồn/x, đích/<tên nguồn>/x ↔ nguồn/x).
COPY_SRCS = {}
TAR_PROGS = {"tar", "gtar", "bsdtar"}
SEVENZ_PROGS = {"7z", "7za", "7zz", "7zr"}
# cwd trên máy kia chỉ biết lúc chạy — sau cd vào link chính lệnh tạo (adb shell, ssh), và trên thiết bị sau mọi cd tới chỗ không biết
# (cd $VAR, cd ~, cd -, popd): remote_target_problem xét nó như một $VAR, phần cố định là / → đích tương đối rm -r bị chặn.
FAR_CWD_AT_RUN = "/$CWD_AT_RUN"
# #427 vòng 3: cwd ở máy này sau cd vào link chính lệnh tạo (ln -s ~ l && cd l): nơi link trỏ tới, không biết — nhưng chắc là không phải chỗ
# hook thấy. Khác cwd None (cd $VAR): đích tương đối bị chặn cả khi rm -r không -f (chính sách 10-09 bỏ qua cwd None).
LINK_CWD = "<cwd: đích của link do chính lệnh tạo>"

def cp_symbolic(rest):
    """True khi cp tạo link thay vì chép: -s (cả trong cụm như -rs) hay --symbolic-link."""
    for a in rest:
        if a == "--":
            break
        if a == "--symbolic-link" or (a.startswith("-") and not a.startswith("--") and "s" in a[1:]):
            return True
    return False

def file_now(a, env, repl, cwds):
    """True khi toán hạng a lúc hook xét là một file hay một link (không phải thư mục thật) ở mọi thư mục hiện tại có thể."""
    v = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), a)
    v = os.path.expanduser(v) if v.startswith("~") else v
    if a in repl or re.search(r"[$\x60]", v) or GLOB.search(v):
        return False
    paths = [v] if os.path.isabs(v) else [c and c != LINK_CWD and os.path.join(c, v) for c in cwds]
    return all(p and os.path.lexists(p) and (os.path.islink(p) or not os.path.isdir(p)) for p in paths)

def real_paths(a, env, repl, cwds):
    """#427 vòng 3: các đường dẫn (realpath, mỗi thư mục hiện tại có thể một) của toán hạng a khi lúc hook xét nó có thật, không phải link, và
    không tên nào của nó là link chính lệnh tạo (made_link_name); None khi không như vậy: chép nó (cp -R, rsync -a, ditto) có thể làm chính
    đích thành link."""
    v = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), a)
    v = os.path.expanduser(v) if v.startswith("~") else v
    if a in repl or re.search(r"[$\x60]", v) or GLOB.search(v) or made_link_name(v.rstrip("/") + "/") is not None:
        return None
    paths = [v] if os.path.isabs(v) else [c and c != LINK_CWD and os.path.join(c, v) for c in cwds]
    ok = all(p and os.path.lexists(p) and not os.path.islink(p.rstrip("/") or "/") for p in paths)
    return [os.path.realpath(p) for p in paths] if ok else None

def mv_dest(rest, env, repl, xargs, cwds):
    """Tên (casefold, như ln_names) nơi mv đặt thứ nó chuyển — link chuyển đi vẫn là link. Đổi tên (một nguồn, đích không có / cuối; -T):
    tên đích. Review #427 vòng 2 (`mv out.json build/` ghi build: chặn nhầm mọi rm qua build/): vào một thư mục (-t / --target-directory,
    hai nguồn trở lên, đích có / cuối) thì thứ nằm trong thư mục là tên NGUỒN. Đích/ với một nguồn không chắc là file / link lúc hook xét
    (thư mục thật, chưa có, không đọc được) ghi cả tên đích: BSD mv đổi tên một thư mục thành đích/ khi đích chưa có (đo 27/10; nguồn là
    link thì lỗi), link bên trong nó lộ ra dưới tên đích. Đích là thư mục có sẵn mà không có / cuối vẫn ghi tên đích: phần trước của lệnh
    có thể xoá thư mục đó (rm, gradle clean …), mv thành đổi tên. "*" khi không đọc được (xargs: toán hạng lấy từ lệnh trước)."""
    ops, dest, opts_done, k, rename = [], None, False, 0, False
    while k < len(rest):
        a = rest[k]
        if not opts_done and a == "--":
            opts_done = True
        elif not opts_done and a.startswith("--target-directory="):
            dest = a.split("=", 1)[1]
        elif not opts_done and a in ("--target-directory", "-S", "--suffix"):
            dest = rest[k + 1] if a == "--target-directory" and k + 1 < len(rest) else dest
            k += 1
        elif not opts_done and a == "--no-target-directory":
            rename = True
        elif not opts_done and a.startswith("-") and len(a) > 1:
            if not a.startswith("--"):
                rename = rename or "T" in a[1:a.index("t", 1) if "t" in a[1:] else None]   # -T (GNU): luôn đổi tên
            if not a.startswith("--") and "t" in a[1:]:   # -t DIR, -ft DIR, -tDIR
                j = a.index("t", 1)
                dest = a[j + 1:] or (rest[k + 1] if k + 1 < len(rest) else "")
                k += 0 if a[j + 1:] else 1
        else:
            ops.append(a)
        k += 1
    if dest is not None and not rename:   # -t DIR: mọi toán hạng là nguồn, nằm trong DIR
        return ln_names(["--"] + ops, env, repl, xargs)
    if dest is None:
        if xargs:
            return {"*"}
        dest = ops[-1] if ops else None
        ops = ops[:-1]
    if dest is None:
        return set()
    if not rename and (len(ops) > 1 or dest.endswith("/")):
        names = ln_names(["--"] + ops, env, repl, xargs)
        if len(ops) > 1 or all(file_now(a, env, repl, cwds) for a in ops):
            return names
    else:
        names = set()
    dnames = ln_names(["--", dest], env, repl, False)
    if dnames == {"*"}:
        # tên đích không đọc được (mv x reports/proof-$st.png — quy trình ảnh nghiệm thu, corpus 27/10: 3 lệnh thật): tên thật vẫn kết thúc
        # bằng phần chữ sau phép mở rộng cuối, kể cả khi biến chứa / → mẫu "*.png" (made_link_name so đuôi) thay cho "*"
        v = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), dest)
        ends = [m.end() for m in re.finditer(r"\$(?:\w+|\{[^}]*\}|.)|`[^`]*`?", v)]
        tail = v[max(ends + [v.rfind(c) + 1 for c in ")}`]"]):]
        if tail and not re.search(r"[/$`{}()\[\]*?]", tail):
            dnames = {"*" + tail.casefold()}
    return names | dnames

def extract_dirs(prog, rest):
    """None: lệnh không giải nén. Không thì các thư mục tar -x / unzip giải nén vào: giá trị -C / --directory của tar, -d của unzip;
    [""]: thư mục hiện tại; None trong danh sách: không đọc được (C trong một cụm cờ của tar)."""
    if prog in TAR_PROGS:
        old = bool(rest) and not rest[0].startswith("-") and re.fullmatch(r"[A-Za-z]*x[A-Za-z]*", rest[0]) is not None   # tar xzf a.tgz
        if not old and not any(a in ("--extract", "--get") or re.match(r"-[A-Za-z]*x", a) for a in rest):
            return None
        dirs, k = ([None] if old and "C" in rest[0] else []), 0
        while k < len(rest):
            a = rest[k]
            if a in ("-C", "--directory"):
                dirs.append(rest[k + 1] if k + 1 < len(rest) else None)
                k += 1
            elif a.startswith("--directory="):
                dirs.append(a.split("=", 1)[1])
            elif re.match(r"-C.", a):
                dirs.append(a[2:])
            elif re.match(r"-[A-Za-z]*C", a):
                dirs.append(None)
            k += 1
        return dirs or [""]
    if prog == "unzip":
        dirs, k = [], 0
        while k < len(rest):
            a = rest[k]
            if a == "-d":
                dirs.append(rest[k + 1] if k + 1 < len(rest) else None)
                k += 1
            elif a.startswith("-d"):
                dirs.append(a[2:])
            elif re.match(r"-[A-Za-z]*[ltvZpcz]", a):   # liệt kê / kiểm / in ra stdout: không ghi đĩa
                return None
            k += 1
        return dirs or [""]
    if prog in SEVENZ_PROGS:   # #427 vòng 3: 7z x / e, -o<thư mục> dính liền (không có: thư mục hiện tại)
        ops = [a for a in rest if not a.startswith("-")]
        if not ops or ops[0] not in ("x", "e"):
            return None
        return [a[2:] or None for a in rest if a.startswith("-o")] or [""]
    if prog == "cpio":   # #427 vòng 3: -i / --extract vào thư mục hiện tại (GNU -D / --directory); -p / --pass-through vào thư mục toán hạng
        flags, dirs, ops, k = "", [], [], 0
        while k < len(rest):
            a = rest[k]
            if a in ("-D", "--directory"):
                dirs.append(rest[k + 1] if k + 1 < len(rest) else None)
                k += 1
            elif a.startswith("--directory="):
                dirs.append(a.split("=", 1)[1])
            elif a in ("--extract", "--pass-through", "--create", "--list"):
                flags += {"--extract": "i", "--pass-through": "p", "--create": "o", "--list": "t"}[a]
            elif a.startswith("-") and not a.startswith("--") and len(a) > 1:
                for j, ch in enumerate(a[1:], 1):
                    if ch in "EFHIMORCD":   # tuỳ chọn có giá trị: phần còn lại của cụm, hay từ sau
                        val = a[j + 1:] or (rest[k + 1] if k + 1 < len(rest) else None)
                        k += 0 if a[j + 1:] else 1
                        dirs += [val] if ch == "D" else []
                        break
                    flags += ch
            elif not a.startswith("-"):
                ops.append(a)
            k += 1
        if "t" in flags or "o" in flags:
            return None
        if "p" in flags:
            return [ops[-1] if ops else None]
        return (dirs or [""]) if "i" in flags else None
    return None

RSYNC_VALUE_OPTS = {"-e", "-f", "-B", "-T", "-M", "-@", "--exclude", "--include", "--filter", "--rsh", "--rsync-path", "--log-file",
                    "--files-from", "--exclude-from", "--include-from", "--temp-dir", "--partial-dir", "--compare-dest", "--copy-dest",
                    "--link-dest", "--backup-dir", "--suffix", "--chmod", "--timeout", "--contimeout", "--bwlimit", "--port",
                    "--password-file", "--max-size", "--min-size", "--max-delete", "--modify-window", "--out-format", "--info", "--debug",
                    "--usermap", "--groupmap", "--chown", "--iconv", "--block-size", "--remote-option", "--address", "--skip-compress"}

def drop_redirects(words):
    """#427 vòng 3: các từ của một lệnh trừ chuyển hướng (2>/dev/null, > log): đích của cp / rsync / cpio -p / git clone là toán hạng cuối."""
    out, k = [], 0
    while k < len(words):
        n = shell_norm.redirect_len(words, k)
        out += [] if n else [words[k]]
        k += n or 1
    return out

def copied(prog, rest):
    """#427 vòng 3: lệnh chép mà link được chép thành link — cp -R / -r / -a / -P / -d (--recursive, --archive, --no-dereference), rsync
    -a / -l (--archive, --links), ditto (không -c; -x giải nén): (đích, các nguồn, vào thư mục). vào thư mục: các nguồn nằm DƯỚI đích (cp
    -t, nhiều nguồn, đích có / cuối, ditto -x). None: không phải lệnh đó, đích ở máy khác (rsync host:path), hay không có đích."""
    if prog not in ("cp", "gcp", "rsync", "ditto"):
        return None
    ops, dest, opts_done, k, flags, longs = [], None, False, 0, "", set()
    vals = RSYNC_VALUE_OPTS if prog == "rsync" else {"--arch", "--bom", "--zlibCompressionLevel"} if prog == "ditto" else {"--suffix"}
    while k < len(rest):
        a = rest[k]
        if not opts_done and a == "--":
            opts_done = True
        elif not opts_done and a.startswith("--"):
            name, eq, val = a.partition("=")
            longs.add(name)
            if prog in ("cp", "gcp") and name == "--target-directory":
                dest = val if eq else (rest[k + 1] if k + 1 < len(rest) else None)
                k += 0 if eq else 1
            elif name in vals and not eq:
                k += 1
        elif not opts_done and a.startswith("-") and len(a) > 1:
            j = next((n for n, ch in enumerate(a[1:], 1) if "-" + ch in vals or (prog in ("cp", "gcp") and ch in "tS")), None)
            flags += a[1:j] if j else a[1:]
            if j:   # tuỳ chọn có giá trị: phần còn lại của cụm, hay từ sau (cp -t DIR)
                val = a[j + 1:] or (rest[k + 1] if k + 1 < len(rest) else None)
                k += 0 if a[j + 1:] else 1
                dest = val if prog in ("cp", "gcp") and a[j] == "t" else dest
        else:
            ops.append(a)
        k += 1
    if prog == "rsync":
        links = bool({"--archive", "--links"} & longs) or "a" in flags or "l" in flags
    elif prog == "ditto":
        links = "c" not in flags
    else:
        links = bool({"--recursive", "--archive", "--no-dereference"} & longs) or any(c in flags for c in "RraPd")
    if not links:
        return None
    into = dest is not None or (prog == "ditto" and "x" in flags)
    if dest is None:
        if len(ops) < 2:
            return None
        dest, ops = ops[-1], ops[:-1]
    if prog == "rsync" and (re.match(r"^[^/]*:", dest) or dest.startswith("rsync:")):   # máy khác
        return None
    return dest, ops, into or len(ops) > 1 or dest.endswith("/"), prog == "ditto" and "x" in flags   # đích/: mục nằm trong nó

GIT_CLONE_VALUE_OPTS = {"-o", "-b", "-u", "-c", "-j", "--origin", "--branch", "--upload-pack", "--template", "--config", "--depth",
                        "--shallow-since", "--shallow-exclude", "--reference", "--reference-if-able", "--separate-git-dir", "--jobs",
                        "--filter", "--server-option", "--bundle-uri", "--ref-format"}

def git_clone_dir(rest):
    """#427 vòng 3: [thư mục working tree] mà `git clone` tạo (git lưu link: một mục bên dưới có thể là link) — toán hạng thứ hai, không có
    thì tên git lấy từ URL; -C DIR đặt trước nó. [] khi không phải clone, hay --bare / --mirror (không có working tree); [None]: không đọc được."""
    j, base = 0, ""
    while j < len(rest) and rest[j].startswith("-"):
        if rest[j] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"):   # giá trị là từ sau
            base = os.path.join(base, rest[j + 1]) if rest[j] == "-C" and j + 1 < len(rest) else base
            j += 1
        j += 1
    if j >= len(rest) or rest[j] != "clone":
        return []
    ops, k = [], j + 1
    while k < len(rest):
        a = rest[k]
        if a == "--":
            ops += rest[k + 1:]
            break
        if a in ("--bare", "--mirror"):
            return []
        k += 1 if a in GIT_CLONE_VALUE_OPTS else 0
        if not a.startswith("-"):
            ops.append(a)
        k += 1
    if not ops:
        return []
    d = ops[1] if len(ops) > 1 else re.split(r"[/:]", re.sub(r"(?:/\.git|\.git|\.bundle)$", "", ops[0].rstrip("/")))[-1]
    return [os.path.join(base, d) if d else None]

def extracted_entry(raw):
    """Đường dẫn của mục đầu tiên nằm DƯỚI một thư mục của EXTRACT_DIRS mà raw (đường dẫn tuyệt đối của đích rm) đi xuyên qua — mọi tên
    trừ tên cuối (dấu / cuối: cả tên cuối), như made_link_name —, hoặc None. Chính thư mục giải nén không tính: rm -r không theo link bên trong.
    #427 vòng 3: một đích COPY_DESTS thì tính cả chính nó (đích chép từ một link là link); dưới một đích COPY_SRCS chỉ mục mà mục tương ứng
    của nguồn là link (từng tiền tố được xét, nên link ở giữa đường cũng thấy)."""
    if not EXTRACT_DIRS and not COPY_DESTS and not COPY_SRCS:
        return None
    parts = raw.split("/")
    for k in range(1, len(parts) - 1):
        if parts[k] in ("", ".", ".."):
            continue
        pre = "/".join(parts[:k + 1])
        rp = os.path.realpath(pre)
        # rel_below: [] là chính d, None là ngoài d
        if any(rel_below(rp, d) for d in EXTRACT_DIRS) or any(rel_below(rp, d) is not None for d in COPY_DESTS):
            return pre
        for d, srcs in COPY_SRCS.items():
            rel = rel_below(rp, d)
            if rel and any(os.path.islink(os.path.join(src, *rel)) or (rel[0] == os.path.basename(src) and len(rel) > 1
                                                                       and os.path.islink(os.path.join(src, *rel[1:]))) for src in srcs):
                return pre
    return None

def dir_paths(d, cwds, env, repl, remote):
    """#427 vòng 3: realpath của thư mục d ở mỗi thư mục hiện tại có thể; None khi không đọc được (None, $VAR, ~ lạ, glob, {} của xargs, máy
    kia, cwd không biết với d tương đối)."""
    d = d if d is None else re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), d)
    d = os.path.expanduser(d) if d and d.startswith("~") else d
    if d is None or remote or d in repl or re.search(r"[$`~]", d) or GLOB.search(d):
        return None
    if any(cwd in (None, LINK_CWD) for cwd in cwds) and not os.path.isabs(d):
        return None
    return [os.path.realpath(os.path.join(cwd or "/", d)) for cwd in cwds]

def record_dirs(dirs, into, cwds, env, repl, remote, named=False):
    """#427 vòng 2/3: ghi các thư mục mà lệnh đặt mục (có thể là link) vào — into: chỉ các mục bên dưới (EXTRACT_DIRS), không thì cả chính
    nó (COPY_DESTS). Thư mục không đọc được (None, $VAR, ~ lạ, glob, {} của xargs, máy kia, cwd không biết): tên link "*". named (cp -R,
    rsync, ditto, git clone): đích tương đối đọc được mà chỉ cwd không biết (cd $W && cp -R a b; corpus 27/10) ghi tên cuối của nó như tên
    link của ln — rm đi qua một thư mục tên đó bị chặn, rm khác không."""
    for d in dirs:
        found = dir_paths(d, cwds, env, repl, remote)
        name = os.path.basename(d.rstrip("/")) if d else ""
        if found is None and named and not remote and d not in repl and not re.search(r"[$`~]", d or "$") and not GLOB.search(d) \
                and name not in ("", ".", ".."):
            LINKS_MADE.add(name.casefold())
        elif found is None:   # máy kia, hay không đọc được
            LINKS_MADE.add("*")
        else:
            (EXTRACT_DIRS if into else COPY_DESTS).update(found)

def rm_target_problem(t, cwds, env, forced=True, _seq=False):
    """Why removing target t recursively is refused, or None. Without -f (forced=False; 2026-10-09,
    tests/gates/test_hardware_rm_unforced.sh) only a target that is or holds the project root, the home folder, / or a
    system partition: rm -r with no terminal to ask on deletes all the same. A target it cannot resolve is not refused then.
    _seq: t là một từ seq_words đã bung (không bung lại, biến đã thay)."""
    orig = t
    if ZSH_QUAL in t:   # a zsh glob qualifier (zsh_qualifiers): build/a(:a:h:h) is the project root, *(e:…:) any path its code names
        shown = orig.replace(ZSH_QUAL, "(…)")
        if forced:
            return f"{shown}: glob qualifier của zsh (`(` dính vào tên): không biết nó mở ra đường dẫn nào"
        # without -f the word before the qualifier is judged, as before 6bf699e8 (OCR final check: rm -r ~(N) is rm -r ~ and passed)
        t = orig = t.replace(ZSH_QUAL, "")
    if t == "~+" or t.startswith("~+/"):   # ~+ is the cwd (OCR round 3, H2: expanduser leaves it as it is)
        t = "$PWD" + t[2:]
    if PWD_VAR.search(t):   # $PWD is the directory the command runs in (2026-10-13: rm -rf "$PWD/build" was refused as unknown)
        for cwd in cwds:
            if cwd in (None, LINK_CWD):   # #427 vòng 3: sau cd vào link chính lệnh tạo — cả khi không -f
                if forced or cwd == LINK_CWD:
                    return f"{orig}: không biết thư mục hiện tại ($PWD sau cd tới $VAR / lệnh con / popd / link do chính lệnh tạo)"
                continue
            why = rm_target_problem(PWD_VAR.sub(lambda m: cwd, t), [cwd], env, forced)
            if why:
                return why
        return None
    # The variable first, then `~` (principal review round 2, B1): bash expands `~` of an unquoted assignment (D=~/x), so the value of $D
    # may start with it; expanded before, `"$D"/` was judged as `<cwd>/~/x`. A quoted `D="~/x"` reads the same: refused as the home folder.
    t = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), t)
    if t.startswith("~"):
        t = os.path.expanduser(t)
        if t.startswith("~"):   # ~- (the previous folder), ~+ out of a variable, ~user with no such user: unknown (OCR round 3, H2)
            return f"{orig}: không biết {t.split(chr(47))[0]} trỏ tới đâu (~- / ~+ / ~user lạ)" if forced else None
    if not _seq and BRACE_SEQ.search(t):   # #427 vòng 2: {a..c} / {1..9..2} shell bung, braces() không: xét như * (gồm mọi tên nó bung ra)
        words = seq_words(t)   # review vòng 2: cả từng từ shell bung (tên chưa có, `..` sau nó) và chữ nguyên (bash 3.2 không bung)
        if words is None:
            return f"{orig}: dãy {{x..y}} bung ra hơn {GLOB_CAP} từ: không xét hết được — chia nhỏ lệnh"
        for x in dict.fromkeys([t] + words):
            why = rm_target_problem(x, cwds, {}, forced, True)   # env {}: biến đã thay; một $ do dãy sinh ra là chữ
            if why:
                return why
        t2 = BRACE_SEQ.sub("*", t)
        t = t2 if "**" in t else re.sub(r"\*{2,}", "*", t2)   # không tự tạo ** của zsh từ {a..z}*
    link = made_link_name(t)   # #427: trước khi tách forced — rm -r không -f (và find -delete, rsync --delete) qua link cũng xoá
    if link is not None:
        return (f"{orig}: đi qua `{link}`, có thể là link do chính lệnh này tạo (ln, cp -s, mv, os.symlink, giải nén vào thư mục không biết) "
                f"— rm -r theo link (dấu / sau nó, đường dẫn bên dưới) xoá nội dung nơi link trỏ tới. Tách lệnh tạo link và rm thành hai lệnh "
                f"để cổng thấy link thật")
    if "$" in t or "`" in t:
        return f"{orig}: không xác định được đường dẫn ($VAR / lệnh con)" if forced else None
    glob = bool(GLOB.search(t))
    starstar = zsh_starstar(t) if glob else None   # OCR round 3, H1: zsh *** follows links, ** walks folders Python glob does not
    if starstar and forced:
        return f"{orig}: {starstar}"
    # #427 vòng 3 (P0): một tên glob rồi `..` sau nó — `mkdir -p build/x/1 && rm -rf build/x/*/../../../src`: tên chưa có lúc hook xét thì
    # glob không khớp gì, chỉ thư mục trước glob (build/x) được xét; chạy thật thì shell khớp build/x/1, `..` đưa tới src/. Xét thêm đường
    # dẫn với mỗi tên glob là một tên thường (shell gộp `..` sau nó như vậy); chặn khi một trong hai cách đọc chặn.
    names = t.split("/")
    if glob and ".." in names[next(k for k, x in enumerate(names) if GLOB.search(x)):]:
        why = rm_target_problem("/".join(GLOB_NAME if GLOB.search(x) else x for x in names), cwds, {}, forced, True)
        if why:
            return why.replace(GLOB_NAME, "*")
    for cwd in ([None] if os.path.isabs(t) else cwds):
        if cwd == LINK_CWD:   # #427 vòng 3: đích tương đối sau cd vào link chính lệnh tạo — cả rm -r không -f (nơi link trỏ tới)
            return (f"{orig}: thư mục hiện tại là nơi một link do chính lệnh này tạo trỏ tới (cd vào link): không biết là đâu — tách lệnh tạo "
                    f"link và lệnh xoá để cổng thấy link thật")
        if cwd is None and not os.path.isabs(t):
            if not forced:
                continue
            return f"{orig}: không biết thư mục hiện tại (cd tới $VAR / lệnh con / popd)"
        base = cwd or "/"
        ent = extracted_entry(os.path.join(base, t))   # #427 vòng 2: trước khi tách forced, như made_link_name
        if ent:
            return (f"{orig}: đi qua {ent}, một mục mà chính lệnh này giải nén / chép vào (tar -x, unzip, 7z, cpio, cp -R, rsync -a, ditto, "
                    f"git clone) — mục đó có thể là link, rm -r theo nó xoá nơi link trỏ tới. Tách lệnh đó và rm thành hai lệnh để cổng thấy "
                    f"mục thật")
        if glob:  # judged as its directory: rm -rf src/* empties src; the shell expands the glob inside it, through a link too
            parts = t.split("/")
            k = next(i for i, x in enumerate(parts) if GLOB.search(x))
            p = os.path.realpath(os.path.join(base, "/".join(parts[:k]) or ("/" if t.startswith("/") else ".")))
        else:   # where the kernel resolves it (review of A7, 25/10): `link/` deletes what the link points at, `link` the link alone
            p = rm_reach(os.path.join(base, t))
        why = rm_path_problem(p, orig, forced, glob)   # the folder first: a refused one costs no walk of its matches (review round 2, A3)
        if why:
            return why
        reach = None
        # where each current match lands, walked once for both checks below (review of A7, round 2 A2); a ** that cannot leave
        # (zsh_starstar "") is not walked: build/**/*.o is a common clean, and its matches stay in the folder
        if glob and starstar != "" and glob_may_leave(t):
            import glob as _glob, itertools as _it
            found = list(_it.islice(_glob.iglob(os.path.join(_glob.escape(base), shell_glob(t))), GLOB_CAP + 1))
            if len(found) > GLOB_CAP:   # with -f or not (OCR round 3, H3: rm -r reached the home folder through match 2010)
                return (f"{orig}: glob khớp hơn {GLOB_CAP} mục mà kết quả có thể ra ngoài {p} (dấu / cuối, hoặc glob trước tên cuối): "
                        f"không xét hết được từng mục — chia nhỏ lệnh hoặc bỏ dấu / cuối")
            reach = list(dict.fromkeys(rm_reach(m) for m in found[:GLOB_CAP]))
        if forced:   # A7: a path in the scratch folder must stay in it (scratch_escape), whatever its spelling
            esc = scratch_escape(base, t, p, reach)
            if esc:
                return f"{orig}: {esc}"
        for r in reach or []:   # a match that left the folder through a link: judged where it lands
            if r != p and not r.startswith(p.rstrip(os.sep) + os.sep):
                why = rm_path_problem(r, orig, forced, False)
                if why:
                    return why
    return None

def rm_path_problem(p, orig, forced, glob):
    """The verdict of rm_target_problem on one resolved path p (glob: p is the folder a glob expands in). None when allowed."""
    if not glob and os.path.lexists(p) and (os.path.islink(p) or not os.path.isdir(p)):
        return None  # a single file
    # the project root and the home folder compared by inode (rel_below), not by spelling (principal review round 2, B3)
    if not forced:   # / holds the project root, so it is caught by the first test
        hit = next((d for d in (ROOT, HOME) if rel_below(d, p) is not None), None) or (p if p in SYS_PART_DIRS else None)
        return f"{orig}: là hoặc chứa {hit} (gốc project / home / phân vùng hệ thống)" if hit else None
    rel = rel_below(p, ROOT)
    if rel == []:
        return f"{orig}: là thư mục gốc project"
    if rel is not None:
        if any(x in BUILD_OUTPUTS for x in rel):
            return (f"{orig}: là build output nhưng git đang track file trong đó (là source), hoặc git lỗi nên không biết"
                    if git_tracks(os.path.join(ROOT, *rel)) else None)
        return f"{orig}: là thư mục cấp 1 của project" if len(rel) == 1 else None
    # Before the /tmp exemption (2026-10-09): a project under /tmp or $TMPDIR is inside its parent, and
    # `rm -rf ..` from it passed while `rm -rf <project>` was blocked.
    if rel_below(ROOT, p) is not None:
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
    # the zsh-qualifier marker dropped (OCR final check, 25/10): `/__ZSH…` read as no system partition, `ssh host rm -rf /(N)` passed
    t = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), t.replace(ZSH_QUAL, ""))
    for x in [t] + braces(t):
        link = made_link_name(x)   # #427 vòng 2: link do chính lệnh tạo trên máy kia — miễn trừ /data/local/tmp không cứu được nơi nó trỏ tới
        if link is not None:
            return (f"{t}: đi qua `{link}`, có thể là link do chính lệnh này tạo trên máy kia — rm -r theo link (dấu / sau nó, đường dẫn "
                    f"bên dưới) xoá nơi link trỏ tới (có thể là / hay phân vùng hệ thống)")
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
                p = shell_norm.norm_path(re.split(r"[$`]", full, maxsplit=1)[0])   # maxsplit theo tên: Python 3.13 cảnh báo ra stderr
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

# Review #427 vòng 2 (thêm): `T=$(mktemp -d); trap \x27rm -rf "$T"\x27 EXIT` (corpus 27/10: 9 lệnh thật bị chặn từ vòng 2). rm_walk thay
# NAME=$(mktemp …) bằng NAME=__MKTEMP_<n>__ (lexer tách $( … ) không nháy thành nhiều từ); assign đọc ra một đường dẫn dưới thư mục tạm
# khi chắc chắn (mktemp_path), không thì giá trị không biết như trước. mktemp là hàm / alias của lệnh, hay PATH bị đổi: không thay.
# (mỗi đoạn chỉ khớp một cách: $NAME hết chữ, ${NAME} có }, chữ thường không gồm $ { } — không quay lui hàm mũ)
MKTEMP_ASSIGN = re.compile(r"(?<![\w$])([A-Za-z_]\w*=)(\x22?)\$\(\s*mktemp((?:[ \t]+(?:(?:[^\s()$\x60;&|<>\x22\x27\\{}]|\$\{\w+\}|\$\w+(?!\w))+"
                           r"|\x22(?:[^\x22$\x60\\{}]|\$\{\w+\}|\$\w+(?!\w))*\x22))*)[ \t]*\)\2(?=[\s;&|)]|$)")
MKTEMP_ARGS = []
MKTEMP_SHADOW = []

def mktemp_rewrite(text):
    if not MKTEMP_SHADOW:
        MKTEMP_SHADOW.append(bool(re.search(r"\bmktemp\s*\(|\bfunction\s+mktemp\b|\balias\b[^;&|\n]*\bmktemp=|(?<![\w$])PATH\+?=|\bhash\s+-\w*p", cmd)))
    if MKTEMP_SHADOW[0] or "mktemp" not in text:
        return text
    def sub(m):
        MKTEMP_ARGS.append(m.group(3))
        return m.group(1) + m.group(2) + "__MKTEMP_%d__" % (len(MKTEMP_ARGS) - 1) + m.group(2)
    return MKTEMP_ASSIGN.sub(sub, text)

def mktemp_path(args, env):
    """Đường dẫn mà $(mktemp ARGS) in ra, chỉ khi chắc chắn nằm dưới thư mục tạm (TMP_ROOTS): không mẫu, -t PREFIX, --tmpdir, hay mẫu
    tuyệt đối trong /tmp, /private/tmp, $TMPDIR; -p DIR thì cả DIR lẫn $TMPDIR (BSD: TMPDIR đè -p) phải là thư mục tạm. Mẫu tương đối (thư
    mục hiện tại), ~/…, chữ $ / glob / . / .. trong đường dẫn, tuỳ chọn lạ, nhiều mẫu: None."""
    try:
        words = shlex.split(re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), args))
    except ValueError:
        return None
    dirs, tmpl, tdir, k = [], [], False, 0
    while k < len(words):
        a = words[k]
        if a in ("--directory", "--quiet", "--dry-run") or re.fullmatch(r"-[dqu]+", a):
            pass
        elif a == "--tmpdir" or a.startswith("--tmpdir="):
            tdir = True
            dirs += [a.split("=", 1)[1]] if "=" in a else []
        elif re.fullmatch(r"-[dqu]*[tp].*", a, re.S):
            j = re.search(r"[tp]", a).start()
            val = a[j + 1:] or (words[k + 1] if k + 1 < len(words) else None)
            k += 0 if a[j + 1:] else 1
            if a[j] == "p" and val is None:
                return None
            dirs += [val] if a[j] == "p" else []
            tmpl += [val] if a[j] == "t" and val is not None else []
            tdir = True
        elif a.startswith("-"):
            return None
        else:
            tmpl.append(a)
        k += 1
    if len(tmpl) > 1:
        return None
    t = tmpl[0] if tmpl else "tmp.XXXXXXXXXX"
    if tdir or not tmpl:
        if "/" in t:
            return None
        paths = [None if b is None else b.rstrip("/") + "/" + t for b in dirs + [env.get("TMPDIR")]]
    else:
        paths = [t]
    for p in paths:
        if p is None or not p.startswith("/") or re.search(r"[$\x60~*?\[\]{}\\]", p) or re.search(r"(?:^|/)\.\.?(?:/|$)", p):
            return None
        d = os.path.realpath(os.path.dirname(p))
        if not any(d == r or under(d, r) for r in TMP_ROOTS):
            return None
    return paths[0]

def assign(env, name, v):
    """NAME=v vào env: biến đã biết thay vào; NAME=$(mktemp …) (mktemp_rewrite) thành đường dẫn tạm, hay không biết."""
    m = re.fullmatch(r"\x22?__MKTEMP_(\d+)__\x22?", v)
    env[name] = (mktemp_path(MKTEMP_ARGS[int(m.group(1))], env) or "$(mktemp)") if m else \
        re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), m.group(0)), v)
    marks = env.get(MAYBE_EMPTY, frozenset())   # mktemp hỏng (TMPDIR mất, đĩa đầy) thì rỗng; gán lại thì hết
    env[MAYBE_EMPTY] = marks | {name} if m else marks - {name}

# Review #427 vòng 2 (thêm): biến có thể RỖNG lúc chạy — gán từ $(mktemp …), hay chỉ gán trong một chuỗi && đã dứt (cd hỏng thì chuỗi
# dừng trước phép gán) — được xét hai cách: giá trị của nó và chuỗi rỗng; chặn khi một trong hai bị chặn. `T=$(mktemp -d); rm -rf "$T"/*`
# rỗng là rm -rf /*. Tập tên nằm trong env dưới khoá MAYBE_EMPTY (không phải tên biến: theo env khi ( … ) / thân hàm / thân trap khôi phục).
MAYBE_EMPTY = "\x00maybe-empty"

def empty_readings(t, env):
    """[t] cộng các cách đọc t khi một biến có thể rỗng là chuỗi rỗng (từng biến, rồi tất cả); cách đọc rỗng hẳn bị bỏ (rm "" không xoá gì)."""
    names = [n for n in sorted(env.get(MAYBE_EMPTY, ())) if re.search(r"\$(?:" + n + r"(?!\w)|\{" + n + r"\})", t)]
    out = [t]
    for group in [[n] for n in names] + ([names] if len(names) > 1 else []):
        x = t
        for n in group:
            x = re.sub(r"\$(?:" + n + r"(?!\w)|\{" + n + r"\})", "", x)
        if x.strip("\x22\x27") and x not in out:
            out.append(x)
    return out

# Review #427 vòng 2 (thêm, P0 có từ trước): phép gán qua builtin từng bị bỏ qua, biến giữ giá trị cũ — `export TMPDIR=~; rm -rf "$TMPDIR"/x`,
# `D=/tmp/a; unset D; rm -rf $D/*` (rm -rf /*), `D+=/../..` đều qua. export / readonly / declare -g / typeset -g NAME=VAL: gán như NAME=VAL.
# local, declare / typeset không -g (trong hàm là biến cục bộ), cờ khác x g r (-i -a -n -l -u …), NAME+=, unset, read, getopts, mapfile,
# readarray, vared, let, printf -v: tên đó thành không biết (-f thì chặn).
DECL_BUILTINS = ("export", "readonly", "declare", "typeset", "local", "integer", "float")
NAME_BUILTINS = ("unset", "read", "getopts", "mapfile", "readarray", "vared", "let")

def decl_effect(word, rest, env):
    """True khi word (chữ lệnh) là một builtin gán / bỏ biến (env đã cập nhật); False cho mọi lệnh khác."""
    m = re.match(r"([A-Za-z_]\w*)\+=", word)
    if m:
        env.pop(m.group(1), None)
        return True
    if word in DECL_BUILTINS:
        opts = [a for a in rest if re.fullmatch(r"[-+]\w+", a)]
        plain = all(set(a[1:]) <= set("xgr") for a in opts) and (word in ("export", "readonly") or any("g" in a for a in opts))
        for a in rest:
            m = re.match(r"([A-Za-z_]\w*)(\+?=)?", a)
            if a[:1] in "-+" or not m:
                continue
            if m.group(2) == "=" and plain:
                assign(env, m.group(1), a.split("=", 1)[1])
            elif m.group(2) or word not in ("export", "readonly"):
                env.pop(m.group(1), None)
        return True
    if word in NAME_BUILTINS or word == "printf":
        for k, a in enumerate(rest):
            m = re.match(r"[A-Za-z_]\w*", a)
            if m and (word != "printf" or (k and rest[k - 1] == "-v")):
                env.pop(m.group(0), None)
        return word != "printf"
    return False

def note_copy(prog, rest, cwds, env, repl, remote):
    """#427 vòng 3: ghi đích của một lệnh chép link thành link (copied); True khi lệnh là lệnh như thế. Mọi nguồn là cây có thật: cặp đích →
    nguồn (COPY_SRCS). Không thì như tar — một nguồn có thật, không phải link: chỉ các mục bên dưới đích (EXTRACT_DIRS); nguồn có thể là link:
    cả chính đích (COPY_DESTS)."""
    c = copied(prog, drop_redirects(rest))
    if c is None:
        return False
    dest, srcs, into, archive = c
    found = [real_paths(a, env, repl, cwds) for a in srcs]
    dests = dir_paths(dest, cwds, env, repl, remote)
    marks = EXTRACT_DIRS | COPY_DESTS | set(COPY_SRCS)
    # mọi nguồn là cây có thật, không cây nào dính tới thư mục mà phần trước của lệnh giải nén / chép vào (cây đó có thể đổi trước lúc chép):
    # ghi cặp đích → nguồn (extracted_entry xét mục tương ứng của nguồn). Không thì như tar: mục bên dưới đích, hay cả chính đích.
    if dests and srcs and not archive and all(found) and not any(rel_below(x, d) is not None or rel_below(d, x) is not None
                                                                  for xs in found for x in xs for d in marks):
        for d in dests:
            COPY_SRCS.setdefault(d, []).extend(x for xs in found for x in xs)
    else:
        record_dirs([dest], into or (len(srcs) == 1 and found[0] is not None), cwds, env, repl, remote, True)
    return True

SCRIPT_MAX = 64 * 1024
SCRIPTS_READ = set()
COLLECT = [0]   # > 0: rm_walk đang duyệt một script chỉ để gom lệnh tạo link (script_links) — không phán quyết nào được trả về

def script_links(path, cwds, depth, remote, shebang):
    """#427 vòng 3: script mà lệnh chạy (bash x.sh, source x.sh, ./x.sh) có thể tạo link mà rm -r sau nó đi qua. File có thật dưới project,
    nhỏ hơn 64 KB, không phải nhị phân (shebang: ./x.sh chỉ khi dòng #! là một shell, hay không có #!) được duyệt như thân heredoc shell, chỉ
    để gom tên link / thư mục giải nén (COLLECT: rm của nó không bị xét ở đây). Script ngoài project, từ 64 KB, $VAR / glob, cwd không
    biết, trên máy kia: không đọc (ponytail ở LINKS_MADE)."""
    if remote or depth > 4 or re.search(r"[$\x60*?\[]", path):
        return
    path = os.path.expanduser(path)
    for cwd in ([None] if os.path.isabs(path) else cwds):
        if cwd in (None, LINK_CWD) and not os.path.isabs(path):
            continue
        p = os.path.realpath(os.path.join(cwd or "/", path))
        if p in SCRIPTS_READ or rel_below(p, ROOT) is None:
            continue
        SCRIPTS_READ.add(p)
        try:
            if not os.path.isfile(p) or os.path.getsize(p) >= SCRIPT_MAX:
                continue
            with open(p, "rb") as fh:
                data = fh.read(SCRIPT_MAX)
        except OSError:
            continue
        if b"\x00" in data or (shebang and data.startswith(b"#!") and not re.match(rb"#![^\n]*\b(?:ba|z|da|k|mk)?sh\b", data)):
            continue
        COLLECT[0] += 1
        try:
            rm_problem(data.decode("utf-8", "replace"), cwds, depth + 1, remote)
        finally:
            COLLECT[0] -= 1

def rm_command_problem(toks, i, cwds, env, depth, feed, remote, implied):
    """rm_segment_problem for the program at toks[i]; toks[:i] is its prefix (NAME=VAL words for this command, xargs and its
    options)."""
    xargs, xargs_file, repl, k = False, False, {"{}"}, 0
    while k < i:
        tk = toks[k]
        if re.match(r"^[A-Za-z_]\w*=", tk):
            name, v = tk.split("=", 1)
            assign(env, name, v)
            if i < len(toks):   # review #427 vòng 2: NAME=VAL trước một lệnh chỉ cho lệnh đó (sh / builtin đặc biệt thì giữ): sau nó không biết
                env.pop(name)   # (`D=build/x make; rm -rf $D/*` là rm -rf /*; thân trap thấy env này: body_env)
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
    if i >= len(toks) or decl_effect(toks[i], toks[i + 1:], env):
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
        record_dirs(git_clone_dir(drop_redirects(rest)), True, cwds, env, repl, remote, True)   # #427 vòng 3: git clone — mục bên dưới có thể là link
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
        if not scripts:   # #427 vòng 3: bash x.sh — đọc file script để gom lệnh tạo link của nó (script_links)
            j, stdin = 0, False
            while j < len(rest) and rest[j][:1] in "-+" and rest[j] not in ("-", "--"):
                stdin = stdin or (rest[j][1:2] != "-" and "s" in rest[j][1:])   # -s: script từ stdin, không phải file
                j += 2 if rest[j] in shell_norm.SHELL_OPTS_WITH_ARG else 1
            j += 1 if j < len(rest) and rest[j] == "--" else 0
            if j < len(rest) and not stdin:
                script_links(rest[j], cwds, depth, remote, False)
        return None
    dev = device_script(prog, rest)
    if dev:
        if dev[2] != "device" or remote == "device":
            return rm_problem(dev[0], dev[1], depth + 1, dev[2])
        local = set(LINKS_MADE)   # DEVICE_LINKS: tên thiết bị tạo không về phán quyết rm của máy này
        LINKS_MADE.update(DEVICE_LINKS)
        try:
            return rm_problem(dev[0], dev[1], depth + 1, dev[2])
        finally:
            DEVICE_LINKS.update(LINKS_MADE - local)
            LINKS_MADE.intersection_update(local)
    if prog == "eval":
        return rm_problem(" ".join(rest), cwds, depth + 1, remote)
    # #427 vòng 2 (P0 có từ trước): thân `repeat N cmd` / `repeat N { … }` của zsh và chuỗi hành động của `trap "<code>" SIG…` là lệnh chạy
    # thật (trap chạy khi tín hiệu tới hay shell thoát): xét như eval. `trap - SIG` / `trap -p` không có thân. Review vòng 2: với các phép
    # gán đã biết mà không gì trong lệnh gán lại được (body_env) — `S=/tmp/claude-501/y; trap \x27rm -rf "$S"\x27 EXIT` từng bị chặn.
    if prog == "repeat" and len(rest) > 1:
        return rm_problem(" ".join(rest[1:]), cwds, depth + 1, remote, env=body_env(env))
    if prog == "trap":
        acts = [a for a in rest if a != "--"]
        if acts and not acts[0].startswith("-"):
            if TRAPS:   # #427 vòng 3: thân chạy lúc thoát, ở cwd lúc đó — rm_walk xét lại với mọi cwd từ đây tới lúc thoát (late_traps)
                e = [acts[0], body_env(env), list(cwds), None, list(cwds), remote]
                TRAPS[-1] += [] if e in TRAPS[-1] else [e]
            return rm_problem(acts[0], cwds, depth + 1, remote, env=body_env(env))
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
                why = next(filter(None, (rm_target_problem(y, cwds, env, False) for y in empty_readings(ops[-1], env))), None)
                if why:
                    return why + " (rsync --delete)"
            note_copy(prog, rest, cwds, env, repl, remote)   # #427 vòng 3: sau phép xét --delete (đích của chính nó không tính)
            return None
        rim = rimraf_args(prog, rest)
        if rim is not None:
            return rm_segment_problem(["rm", "-rf", "--"] + rim, cwds, env, depth + 1)
    if prog.lower() in ("ln", "gln") or (prog.lower() in ("cp", "gcp") and cp_symbolic(rest)):   # #427: tên link lệnh này tạo
        LINKS_MADE.update(ln_names(rest, env, repl, xargs))   # (vòng 2: cp -s / --symbolic-link ghi tên như ln)
        return None
    if prog.lower() in ("mv", "gmv"):   # #427 vòng 2: link chuyển đi vẫn là link — tên đích
        # vòng 3: trong script đọc để gom (COLLECT) chỉ khi một toán hạng có thể là link chính lệnh tạo: `mv "$tmp" "$path"` (ghi file
        # nguyên tử, rất thường gặp) từng làm tên "*" chặn mọi rm qua thư mục (corpus 27/10). ponytail: script chuyển một link có sẵn.
        if not COLLECT[0] or any(made_link_name(a.rstrip("/") + "/") is not None for a in rest if not a.startswith("-")):
            LINKS_MADE.update(mv_dest(rest, env, repl, xargs, cwds))
        return None
    if note_copy(prog.lower(), rest, cwds, env, repl, remote):   # #427 vòng 3: cp -R / -a, rsync -a, ditto chép link thành link
        return None
    if prog in ("source", ".") and rest:   # #427 vòng 3: script chạy trong shell này
        script_links(rest[0], cwds, depth, remote, False)
        return None
    if (shell_norm.INTERPRETER.fullmatch(prog) or prog in shell_norm.RUNNERS) and any(SYMLINK_API.search(a) for a in rest):
        LINKS_MADE.add("*")   # #427 vòng 2: chương trình nội tuyến (-c / -e) của interpreter tạo link (os.symlink …): tên không đọc được
        return None
    ex = extract_dirs(prog.lower(), drop_redirects(rest))
    if ex is not None:   # #427 vòng 2: tar -x / unzip (vòng 3: 7z, cpio) — mục bên dưới thư mục giải nén có thể là link (extracted_entry)
        record_dirs(ex, True, cwds, env, repl, remote)
        return None
    if "/" in toks[i] and prog.lower() != "rm":   # #427 vòng 3: ./x.sh, scripts/run.sh — script shell (shebang) dưới project
        script_links(toks[i], cwds, depth, remote, True)
    if prog.lower() != "rm" or COLLECT[0]:   # COLLECT: chỉ gom lệnh tạo link của script (script_links), không xét rm của nó
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
            for y in empty_readings(t, env):   # biến có thể rỗng: hai cách đọc (MAYBE_EMPTY)
                why = remote_target_problem(y, cwds, env, remote)
                if why:
                    return why
            continue
        for x in [t] + [b for b in braces(t) if b != t]:   # the raw word, then each brace expansion (rm -rf ~/{a,b})
            for y in empty_readings(x, env):
                why = rm_target_problem(y, cwds, env, force)
                if why:
                    return why
    return None

# find operators written escaped or quoted (\; \( \) and their quoted forms) are words of find, not shell separators
# (2026-10-09): split there, `find . \( … \) -delete` and `find . -exec … \; -delete` lost their -delete. An escaped
# backslash before them (`\\;`) is not an escape of the operator.
FIND_OP = re.compile(r"(?<!\\)((?:\\\\)*)\\([;()])|\x27([;()])\x27|\x22([;()])\x22")
FIND_OP_WORD = {";": " __ESC_SEMI__ ", "(": " __ESC_LP__ ", ")": " __ESC_RP__ "}

drop_comments = shell_norm.drop_comments   # one copy for both guards (issue #7)

_REBOUND = {}

def body_env(env):
    """Review #427 vòng 2: phần env mà thân trap / repeat dùng — thân trap chạy lúc thoát, sau mọi lệnh; repeat chạy lại thân. Chỉ tên
    không gì trong cả lệnh gán lại được: trừ các lần đọc ($S, ${S}, ${#S}, ${S:-…} ${S%…} …), tên trần xuất hiện đúng một lần, là S=. Mọi
    dạng khác (S= thứ hai, S+=, ${S:=…}, read / for / printf -v / unset S, chữ S trong chuỗi) bỏ tên đó: không biết, như trước (-f thì chặn).
    Tên mặc định (HOME, TMPDIR) không xuất hiện trần thì giữ."""
    out = {}
    for k, v in env.items():
        if k not in _REBOUND:
            rest = re.sub(r"\$(?:" + k + r"(?!\w)|\{#?" + k + r"(?:\}|(?=:?[-+?%#/^,]|:\d)))", "", cmd)
            _REBOUND[k] = re.findall(r"(?<![\w$])" + k + r"(?!\w)(\+?=)?", rest) not in ([], ["="])
        if not _REBOUND[k]:
            out[k] = v
    return out

def rm_problem(text, cwds, depth=0, remote="", _pass=0, env=None):
    """#427 vòng 2: rm / find -delete / rsync --delete đứng TRƯỚC ln mà chạy SAU nó (vòng lặp, hàm gọi sau) từng được xét khi tên link chưa
    ghi. Cả lệnh (depth 0): lượt 1 xét như trước và gom mọi tên (LINKS_MADE, EXTRACT_DIRS; lượt 1 không chặn thì đã đi hết lệnh); có tên
    thì lượt 2 xét lại với đủ tên các lệnh có thể chạy sau một lệnh tạo link đứng sau chúng: trong vùng lặp (for / while / until / select …
    done, LOOP), hay mọi lệnh khi lệnh có hàm, chạy nền &, trap, xargs / find -exec / parallel / watch (RERUN). rm ở ngoài vòng lặp, đứng
    trước, chỉ chạy một lần trước ln (rm -rf $S; mkdir $S; for …; do ln -s … $S/$x; done: corpus 27/10, 11 lệnh thật) — lượt 1 đã đúng.
    Chặn khi một trong hai lượt chặn: chỉ thêm phán quyết, không bớt.
    Walk the command like the shell: `cd` moves the cwd (after `&&` for sure; after
    ; || | & both the old and the new directory stay possible), ( ) restores it. remote: the text runs on a device ("device")
    or a remote host ("ssh") (2026-10-13): no host variable or ~ applies there. A heredoc body is cut only for a message of a
    known option, the one file statement of a modeled command, or an interpreter program that cannot start a process and whose output nothing
    takes (shell_norm.heredocs, policy of 15/10); an unquoted body with a $ or a backtick is never cut (the shell runs its $( )).
    The text is walked once per reading (shell_norm.readings: continuations joined, and as typed): blocked when either reading is."""
    if depth == 0 and not _pass:
        RERUN[0], PASS[0], LOOP[0] = False, 1, 0   # RERUN: đặt ở lượt 1, trên văn bản đã cắt thân heredoc dữ liệu (bên dưới)
        why = rm_problem(text, cwds, 0, remote, 1)
        if why or not (LINKS_MADE or EXTRACT_DIRS or COPY_DESTS or COPY_SRCS or DEVICE_LINKS):
            return why
        PASS[0], LOOP[0] = 2, 0
        return rm_problem(text, cwds, 0, remote, 2)
    if depth > 5:
        return "lồng lệnh quá sâu để phân tích"
    shell_text = text   # #427 vòng 2: văn bản mà RERUN_RX đọc — không có thân heredoc dữ liệu / chương trình interpreter (code C# / Python
    # trong đó, như `F() {`, không phải hàm shell), dù scan_text giữ chúng lại khi lệnh không được mô hình
    if "<<" in text:   # an interpreter program that can start a process (backticks, qx, %x, system …) stays: its text is a command line
        docs = shell_norm.heredocs(text)
        for h in sorted((h for h in docs if h.kind in ("data", "interp")), key=lambda h: -h.body_start):
            shell_text = shell_text[:h.body_start] + shell_text[h.body_end:]
        # #427 vòng 2: chương trình / script trong thân heredoc tạo link (python3 - <<EOF … os.symlink …): tên không đọc được. Thân "shell"
        # được duyệt như lệnh (ln của nó có tên), thân "data" không bao giờ chạy
        if any(h.kind not in ("shell", "data") and (SYMLINK_API if h.kind == "interp" else SYMLINK_CALL).search(h.body(text)) for h in docs):
            LINKS_MADE.add("*")
        # a body that stays is not quote-scoped (15/10 r6): the quote characters of its lines that do not close them are dropped, or they pair with a quote of another
        # body and hide the command between them from drop_comments and the lexer
        text, _open = shell_norm.scan_text(text, lambda h: h.kind == "data" or shell_norm.program_cut(h, text), docs)
    if depth == 0 and _pass == 1:
        RERUN[0] = bool(RERUN_RX.search(shell_text))
    # env: phép gán đã biết mà thân trap / repeat dùng (body_env); mặc định: mới, như mọi script con (sh -c không thấy biến không export)
    env = dict(env) if env is not None else {} if remote else {"HOME": os.path.expanduser("~"), "TMPDIR": os.environ.get("TMPDIR") or "/tmp"}
    for reading in shell_norm.readings(drop_comments(text)):
        loop = LOOP[0]   # vùng lặp của lệnh bao ngoài (sh -c trong vòng lặp vẫn ở trong nó); một done lẻ không lọt ra ngoài
        TRAPS.append([])   # #427 vòng 3: trap đặt trong lần duyệt này (late_traps)
        try:
            why = rm_walk(reading, cwds, depth, remote, env)
        finally:
            TRAPS.pop()
        LOOP[0] = loop
        if why:
            return why
    return None

# #427 vòng 2, lượt 2 của rm_problem: LOOP độ sâu vùng lặp ở chỗ rm_walk đang đọc; PASS lượt đang chạy; RERUN lệnh có cấu trúc chạy lại /
# đổi thứ tự mà rm_walk không mô hình (hàm, & chạy nền, nhóm ( … ) / { … } nối ống, trap, coproc, xargs / find -exec / parallel / watch):
# lượt 2 xét mọi lệnh.
LOOP, PASS, RERUN = [0], [0], [False]
# review #427 vòng 2: (?<![\w.-]) thay \b — \b cho bắt đầu ở mọi ranh giới trong một chuỗi a.a.a…, mỗi chỗ quét lại tới cuối (bậc hai: 20 KB
# 2 s, 60 KB chạm hạn 7 s); nay chỉ bắt đầu ở đầu chuỗi, cùng các chỗ khớp.
RERUN_RX = re.compile(r"(?<![\w.-])[\w.-]+\s*\(\s*\)\s*[{(]|\bfunction\s+[\w.-]+|(?<![&>|<])&(?![&>])|[)}]\s*\|(?!\|)|\btrap\b|\bcoproc\b|\bxargs\b"
                      r"|\s-(?:exec|execdir|ok|okdir)\b|\bparallel\b|\bwatch\b")
LOOP_HEADS = ("for", "while", "until", "select", "repeat", "foreach")   # repeat N … / foreach x ( … ) … end: vòng lặp của zsh (Bash tool)
LOOP_WORD = re.compile(r"\b(?:" + "|".join(LOOP_HEADS) + r")\b")

SEP_CHARS = set(";&|()\n")   # the characters of a separator word of shell_norm.lex_words (a newline is one)

def seg_head(seg):
    """(chỉ số, tên) chữ lệnh của một đoạn như rm_walk đọc: sau NAME=VAL và RM_WRAPPERS."""
    i = 0
    while i < len(seg) and (re.match(r"^[A-Za-z_]\w*=", seg[i]) or seg[i] in RM_WRAPPERS):
        i += 1
    return i, (os.path.basename(seg[i]) if i < len(seg) else "")

def seg_names(s, i, head):
    """Tên một đoạn có thể gán: NAME= / NAME+= ở bất cứ từ nào, biến của for / select / foreach, tên trong read / unset / export / local …"""
    names = {m.group(1) for w in s for m in [re.match(r"([A-Za-z_]\w*)\+?=", w)] if m}
    if head in ("for", "select", "foreach") + DECL_BUILTINS + NAME_BUILTINS + ("printf",):
        names |= {w for w in s[i + 1:] if re.fullmatch(r"[A-Za-z_]\w*", w)}
    return names

def loop_regions(toks):
    """Review #427 vòng 2 (thêm, P0 có từ trước): `D=build/x; for i in 1 2; do rm -rf $D; D=~; done` qua — lượt lặp 2 xoá ~. {số thứ tự
    đoạn đầu vòng lặp (như rm_walk đếm): tên được gán ở bất cứ đâu trong vùng lặp (điều kiện, thân, vòng lồng; tới done khớp, không có thì
    tới hết lệnh)}: NAME= / NAME+=, biến của for / select / foreach, tên trong read / unset / export / local … rm_walk bỏ chúng khỏi env ở
    đầu vùng (lượt sau thấy giá trị lượt trước) và ở done (không lượt nào chạy thì còn giá trị cũ)."""
    segs, cur = [], []
    for tk in toks + [";"]:
        if shell_norm.join_fd_dup(cur, tk):
            continue
        if not set(tk) <= SEP_CHARS:
            cur.append(tk)
            continue
        if cur:
            segs.append(cur)
        cur = []
    out, stack = {}, []
    for n, s in enumerate(segs):
        i, head = seg_head(s)
        if head in LOOP_HEADS:
            out[n] = set()
            stack.append(out[n])
        if stack:
            stack[-1].update(seg_names(s, i, head))
        if head == "done" and stack:
            inner = stack.pop()
            if stack:
                stack[-1].update(inner)
    while len(stack) > 1:   # vùng không đóng: tới hết lệnh, chứa mọi vùng trong nó
        inner = stack.pop()
        stack[-1].update(inner)
    return out

TRAPS = []   # #427 vòng 3: mỗi rm_walk đang chạy một danh sách [thân, env, cwds tới giờ, độ sâu ( … ), cwds lúc đặt, remote] của trap

def late_traps(traps, level, depth):
    """#427 vòng 3: thân trap chạy khi shell của nó thoát, ở cwd LÚC ĐÓ (lệnh dừng ở đâu cũng được: lỗi, tín hiệu) — xét lại với mọi cwd từ
    lúc đặt tới lúc thoát: `trap \x27rm -rf build\x27 EXIT; cd ~` xoá ~/build; cd sau đó tới chỗ không biết thì không biết. level: trap đặt
    sâu hơn (trong ( … ) vừa đóng) chạy bây giờ; -1: hết lệnh. Không cwd nào thêm thì phép xét lúc đặt trap đã đủ."""
    for tr in [t for t in traps if t[3] is None or t[3] > level]:
        traps.remove(tr)
        if tr[2] != tr[4] and not COLLECT[0]:
            why = rm_problem(tr[0], tr[2], depth + 1, tr[5], env=tr[1])
            if why:
                return why + " (thân trap chạy lúc thoát, ở thư mục hiện tại lúc đó)"
    return None

def rm_walk(text, cwds, depth, remote, env):
    """rm_problem of one reading of the text (comments already cut, continuations already decided)."""
    # `…` is $(…): the lexer splits "$" from "(", so a target built from one stays "$…"
    # (unresolvable, refused) while the inner command is walked as its own segment.
    text = re.sub(r"`([^`]*)`?", r"$(\1)", text)
    text = mktemp_rewrite(text)   # NAME=$(mktemp …) → NAME=__MKTEMP_<n>__ (assign)
    text = FIND_OP.sub(lambda m: (m.group(1) or "") + FIND_OP_WORD[m.group(2) or m.group(3) or m.group(4)], text)
    text = zsh_qualifiers(text)
    try:
        if shell_norm.dq_nested_quote(text):   # "$(echo "a b"; rm -rf ~)": the lexer pairs the quotes across the substitution (15/10 r6): read it as text that does not parse
            raise ValueError("a double quote inside a command substitution inside double quotes")
        toks = shell_norm.lex_words(text)
    except ValueError:   # a quote left open: split at blanks, a newline is a separator of its own (it is no blank here)
        toks = [x.strip("\"\x27") for x in re.split(r"\s+|([;&|()]+)", text.replace("\n", " ; ")) if x and x.strip()]
    stack, seg, pending, feed = [], [], None, None
    regions, nseg, open_loops = loop_regions(toks), -1, []   # review vòng 2 (thêm): tên gán trong vùng lặp — loop_regions
    # Review vòng 2 (thêm, P0 có từ trước): phép gán không chắc chạy, hay chạy ở shell con, từng đặt biến cho các lệnh sau như phép gán chắc
    # chắn: `D=~; false && D=/tmp/a; rm -rf $D`, `D=/tmp/a | cat`, `D=/tmp/a &`, `if …; then D=/tmp/a; fi`, thân hàm (chạy lúc gọi). Nay
    # tên đó thành không biết: ngay sau đoạn (chặng ống, chạy nền, sau ||), khi chuỗi && dứt (sau &&), ở fi / esac (if / case). Thân hàm:
    # xét với body_env như thân trap (chạy lúc gọi, sau mọi phép gán); sau định nghĩa, tên nó gán không biết ở mọi chỗ (gọi lúc nào cũng được).
    prev, cond, blocks, volatile, fn_body, fn_next, seen, cond_kept = ";", set(), [], set(), None, False, set(), set()
    for tk in toks + [";"]:
        if shell_norm.join_fd_dup(seg, tk):   # 2>&1 rm …: the & belongs to the redirect
            continue
        if not set(tk) <= SEP_CHARS:
            seg.append(tk)
            continue
        if seg:
            nseg += 1
            i, head = seg_head(seg)
            names = seg_names(seg, i, head)
            if seg[0] in ("if", "case"):
                blocks.append(set())
            if fn_body is None and (fn_next or head == "function") and "{" in seg:
                fn_body = [dict(env), 0, set()]   # env trước thân, độ sâu { }, tên thân gán
                body = body_env(env)
                env.clear()
                env.update(body)
            if fn_body is not None:
                fn_body[1] += seg.count("{") - seg.count("}")
                fn_body[2] |= names
            if head in LOOP_HEADS:   # #427 vòng 2: vùng lặp, kể cả điều kiện của while / until (end của foreach không đóng: thừa thì chặn hơn)
                LOOP[0] += 1
                open_loops.append(regions.get(nseg, set()))
                for name in open_loops[-1]:
                    env.pop(name, None)
            elif head == "done":
                LOOP[0] = max(0, LOOP[0] - 1)
                for name in (open_loops.pop() if open_loops else ()):
                    env.pop(name, None)
            for tok_seg in seg:  # "$(…)" / `…` inside a quoted word runs too — #427 vòng 2: trước lệnh chứa nó (chạy trước), như shell
                if "(" in tok_seg and depth < 5:
                    why = rm_problem(tok_seg.split("(", 1)[1].rstrip(")"), cwds, depth + 1, remote)
                    if why and not COLLECT[0]:
                        return why
            if head in ("cd", "pushd", "popd"):
                # raw words: options (-L -P -e -@ --, pushd -n) are skipped, but "-" (cd -) and +N / -N (pushd +1) are not options
                args, k, opts = seg[i + 1:], 0, []
                while k < len(args) and args[k].startswith("-") and len(args[k]) > 1 and not re.fullmatch(r"-\d+", args[k]):
                    opts.append(args[k]); k += 1
                    if args[k - 1] == "--":
                        break
                # the zsh-qualifier marker dropped (OCR final check): `cd /(N)` enters /, not /__ZSH…
                arg = args[k].replace(ZSH_QUAL, "") if k < len(args) else ("~" if head == "cd" else None)
                if head == "pushd" and "-n" in opts:
                    pass   # pushd -n only edits the directory stack: the shell stays where it is
                elif remote and arg is not None and made_link_name(arg + "/") is not None:
                    # #427 vòng 2: trên máy kia cwd None là "không xét" (đích tương đối qua đi): cd vào link chính lệnh tạo thì thư mục thật
                    # là nơi link trỏ tới — chỉ biết lúc chạy, như $VAR (remote_target_problem chặn nếu nó có thể là / hay phân vùng hệ thống)
                    pending = [FAR_CWD_AT_RUN]
                elif (head == "popd" or arg is None or arg == "-" or re.fullmatch(r"[+-]\d+", arg) or "$" in arg or GLOB.search(arg)
                      or (CDPATH_SET and not arg.startswith(("/", "~"))) or (remote and arg.startswith("~"))
                      or (arg.startswith("~") and os.path.expanduser(arg).startswith("~"))):   # cd ~- / ~+ / ~nosuchuser (OCR round 3)
                    # popd / bare pushd / cd - / pushd +N come back to a directory this walk never saw; with CDPATH a relative
                    # name may resolve anywhere ("CDPATH=/opt cd data" enters /opt/data); the far home is unknown
                    pending = [None]
                elif made_link_name(arg + "/") is not None:   # #427: cd vào link chính lệnh này tạo — thư mục thật là nơi link trỏ tới
                    pending = [LINK_CWD]   # vòng 3: không phải None — đích tương đối bị chặn cả khi rm -r không -f
                else:
                    arg = arg if remote else os.path.expanduser(arg)
                    # c is None after `cd $VAR`: an absolute arg ignores it (join(None, arg) raised TypeError, rc 1, command ran)
                    # #427 vòng 2: từ c chỉ biết lúc chạy (FAR_CWD_AT_RUN, chỉ có trên máy kia) cd tương đối vẫn chỉ biết lúc chạy — normpath
                    # gộp `..` của nó thành /
                    pending = [LINK_CWD if c == LINK_CWD and not os.path.isabs(arg)   # vòng 3: cd tương đối từ đó vẫn ở nơi link trỏ tới
                               else FAR_CWD_AT_RUN if c and "$" in c and not os.path.isabs(arg)
                               else os.path.normpath(os.path.join(c or "/", arg)) if c or os.path.isabs(arg) else None
                               for c in cwds]
                    if k < len(args) and ZSH_QUAL in args[k]:   # a qualifier may move it ((:h) of /tmp is /): also unknown
                        pending.append(None)
            elif (PASS[0] != 2 or LOOP[0] or RERUN[0] or tk.strip() in ("|", "|&")
                  or LOOP_WORD.search(" ".join(seg))):   # lượt 2: chỉ lệnh có thể chạy SAU một lệnh tạo link đứng sau nó (rm_problem); một
                # chặng ống chạy cùng lúc với các chặng sau; một lệnh mang script có vòng lặp (adb shell "for …", sh -c "while …")
                why = rm_segment_problem(seg, cwds, env, depth, feed, remote)
                if why and not COLLECT[0]:
                    return why
                for tr in TRAPS[-1]:   # #427 vòng 3: trap vừa đặt thuộc shell con ( … ) đang mở (late_traps)
                    tr[3] = len(stack) if tr[3] is None else tr[3]
            else:   # lượt 2, lệnh chỉ chạy một lần, trước mọi ln đứng sau nó: không xét lại, chỉ giữ phép gán NAME=VAL cho lệnh sau như lượt 1
                for w in seg[:i]:
                    if re.match(r"^[A-Za-z_]\w*=", w):
                        name, v = w.split("=", 1)
                        assign(env, name, v)
                        if i < len(seg):   # trước một lệnh: chỉ cho lệnh đó (rm_command_problem)
                            env.pop(name)
                if i < len(seg):   # export / unset / read … (decl_effect), như lượt 1
                    decl_effect(seg[i], seg[i + 1:], env)
            sep = tk.strip("\n") or ";"   # phép gán không chắc (xem trên prev, cond …)
            uncertain = names if sep in ("|", "|&", "&") or prev in ("|", "|&", "||") else ()
            if prev == "&&":   # tên chưa từng gán (trong lệnh, vùng lặp đang mở, môi trường) mà phép gán sau && không chạy thì rỗng: giữ giá
                # trị như trước (corpus 27/10: 26 lệnh `cd <wt> && S=<scratch>; rm -rf $S`), cộng cách đọc rỗng (cd hỏng: rm -rf $S/x là /x)
                risky = {n for n in names if n in seen or n in os.environ or fn_body is not None or any(n in r for r in open_loops)}
                cond |= risky
                cond_kept |= names - risky   # giữ giá trị; chuỗi && dứt thì có thể rỗng (dừng trước phép gán): MAYBE_EMPTY
            seen |= names
            if blocks:
                blocks[-1] |= names
            if seg[0] in ("fi", "esac") and blocks:
                uncertain = set(uncertain) | blocks.pop()
                if blocks:
                    blocks[-1] |= uncertain
            if fn_body is not None and fn_body[1] <= 0:   # hết thân hàm: env như trước định nghĩa, tên thân gán không biết từ đây
                env.clear()
                env.update(fn_body[0])
                volatile |= fn_body[2]
                fn_body = None
            fn_next = (head == "function" and "{" not in seg) or (len(seg) == 1 and tk.replace(" ", "") == "()")
            for name in set(uncertain) | volatile:
                env.pop(name, None)
        if (tk.strip("\n") or ";") != "&&":
            for name in cond:
                env.pop(name, None)
            cond.clear()
            if cond_kept:
                env[MAYBE_EMPTY] = env.get(MAYBE_EMPTY, frozenset()) | cond_kept
                cond_kept.clear()
        prev = tk.strip("\n") or ";"
        if pending is not None:
            if remote == "device":   # #427 vòng 2: thiết bị bắt đầu ở / (biết); cd tới chỗ không biết ($VAR, ~, -, popd) không còn bỏ qua đích tương đối
                pending = [FAR_CWD_AT_RUN if c is None else c for c in pending]
            cwds = list(dict.fromkeys(pending if tk.strip("\n") == "&&" else cwds + pending))   # && then a newline is still &&
            pending = None
            for tr in TRAPS[-1]:   # #427 vòng 3: cwd mà thân trap có thể chạy ở đó
                tr[2] = list(dict.fromkeys(tr[2] + cwds))
        if "(" in tk:   # review vòng 2 (thêm): ( … ) là shell con — phép gán trong đó (cả export) không ra ngoài, như cwd
            stack.append((cwds, dict(env)))
        if ")" in tk and stack:
            cwds, saved = stack.pop()
            env.clear()
            env.update(saved)
            why = late_traps(TRAPS[-1], len(stack), depth)   # #427 vòng 3: trap đặt trong ( … ) chạy khi nó thoát
            if why and not COLLECT[0]:
                return why
            for tr in TRAPS[-1]:
                tr[2] = list(dict.fromkeys(tr[2] + cwds))
        feed = seg if ("|" in tk and "||" not in tk and not tk.startswith(")")) else None   # what `| xargs rm` reads
        seg = []
    return None if COLLECT[0] else late_traps(TRAPS[-1], -1, depth)   # #427 vòng 3: trap của shell này chạy khi nó thoát

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
