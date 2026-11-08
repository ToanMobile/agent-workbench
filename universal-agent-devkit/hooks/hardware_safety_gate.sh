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
#     Review vòng 3: tên glob dưới / trên đích chép khớp với mục thật của nguồn (dist/t/*/x); rm -r chứa một worktree git đã đăng ký
#     (`rm -rf .claude/worktrees`); đích chép / clone không đọc được chỉ chặn rm cũng không đọc được; cd trong eval / script source, chdir;
#     trap đã gỡ (trap - EXIT), cd chạy nền, nguồn mkdir của chính lệnh không còn bị xét; tra theo khoá, git ls-files một lần (thời gian).
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
#   • the same device checks through mobile-mcp (@mobilenext/mobile-mcp 1.0.16, PreToolUse `mcp__mobile-mcp__.*`, 08/11/2026):
#     the string `device` of each call (a serial, or the AVD name of an emulator) is checked against the device policy like
#     `adb -s <device>`; mobile_install_app / uninstall_app / clear_app_data are read as the adb command they run (a system
#     package is refused); mobile_batch_commands is opened step by step (a step's own `device` replaces the batch one, and
#     listElementsAtEnd touches the batch device); the four cloud tools and any call that names no device are refused.
#     A denylist entry must be written the way the device is NAMED to the tool: list both the adb serial and the AVD name /
#     Simulator UDID. An MCP tool name anywhere in the payload sends it to the parser, never the fast path (tests/gates/test_hw_mobile_mcp.sh).
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
  local mcp_re='"tool(_n|N)ame"[[:space:]]*:[[:space:]]*"mcp__'
  # (09/11, audit T0001) the two regexes below read the WHOLE payload, so an MCP call whose arguments carry {"tool_name":"Bash",
  # "command":"ls"} (mobile_batch_commands steps take any key) looked like a Bash call and skipped the parser. An MCP tool name
  # anywhere in the payload sends it to the parser.
  [[ $INPUT =~ $mcp_re ]] && return 1
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

# The python of this gate is hooks/hardware_safety_gate_main.py, beside this file (#967: inline code is compiled again at every
# Bash call, an imported module is cached: ~35 ms CPU less per call, measured 04/11). This loader: the hook directory from
# realpath($0), never the project (-I keeps the cwd off sys.path); bytecode only in the private directory of hooks/prompt_context.sh
# (#823: a real directory of this user that nobody else can write, lstat), else none, never a __pycache__ beside the hook. The
# module cannot be loaded: blocked with the reason (fail closed).
printf '%s' "$INPUT" | REPO_ROOT="${REPO_ROOT}" python3 -I -c '
import sys, os, stat
def _not_loaded(etype, value, tb):
    try:
        why = (str(value).splitlines() or [""])[0][:120]
        sys.stderr.write("🛑 [HARDWARE SAFETY GATE] không nạp được hooks/hardware_safety_gate_main.py cạnh hook (" + etype.__name__ + ": " + why
                         + ") — chặn để an toàn. Cài lại DevKit (agent-kit init); lệnh cần chạy ngay thì người dùng tự chạy qua prefix `!` "
                         "(hoặc HARDWARE_OVERRIDE=1).\n")
        sys.stderr.flush()
    finally:
        os._exit(2)
sys.excepthook = _not_loaded   # the module installs its own fail-closed hook as its first statement
_d = os.path.dirname(os.path.realpath(sys.argv[1])) if len(sys.argv) > 1 else ""
if not os.path.isabs(_d):
    raise ImportError("hook path ($0) is not known")
sys.dont_write_bytecode = True
_c = os.environ.get("TMPDIR") or os.environ.get("XDG_CACHE_HOME") or (os.environ.get("HOME") or "") + "/.cache"
_c = (_c[:-1] if _c.endswith("/") else _c) + "/devkit-pycache-" + str(os.getuid())
if os.path.isabs(_c) and hasattr(sys, "pycache_prefix"):
    try:
        if not os.path.isdir(_c):
            os.mkdir(_c, 0o700)
        _st = os.lstat(_c)
    except OSError:
        _st = None   # no private bytecode directory (cannot be made, a dangling link, a race lost): uncached, as before #967
    if _st is not None and stat.S_ISDIR(_st.st_mode) and _st.st_uid == os.getuid() and not _st.st_mode & 0o022:
        sys.pycache_prefix = _c
        sys.dont_write_bytecode = False
sys.path.append(_d)   # after the stdlib
import hardware_safety_gate_main
' "$0"
rc=$?
case "${rc}" in 0|2) exit "${rc}" ;; esac
echo "🛑 [HARDWARE SAFETY GATE] python không chạy được (rc ${rc}) — chặn để an toàn (người dùng tự chạy lệnh qua prefix ! hoặc HARDWARE_OVERRIDE=1)." >&2
exit 2
