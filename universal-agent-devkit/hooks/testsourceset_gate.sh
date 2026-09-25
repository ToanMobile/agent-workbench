#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# testsourceset_gate.sh — Stop hook: compile the TEST source set of every module
# with uncommitted Kotlin/Java changes (kills "debug build green, CI red").
#
# Rationale (real P0, 2026-07-16): a constructor param was added to
# PermissionViewModel without updating its two `src/test` call sites.
# `:app:assembleDebug` and `:<module>:compileDebugKotlin` BOTH stayed green —
# neither compiles the unit-test source set — so the break was invisible until a
# fresh-context reviewer ran `compileDebugUnitTestKotlin` by hand. It had taken
# down StoragePermissionReleaseGateTest, i.e. the release gate. Prose rules did
# not prevent this (Deep Audit Loop already said "targeted module compile"); a
# command that actually runs does.
#
# BLOCK (exit 2) when: a touched module's `compileDebugUnitTestKotlin` fails — or,
# for a module with `testBuildType = "<x>"`, `compile<X>UnitTestKotlin`: AGP creates
# unit-test variants only for the testBuildType, so a `testBuildType = "release"`
# module has no Debug task and used to be dropped as "lacks the task" (OfficeReader
# :app, 2026-09-23). Read the way scripts/matrix_detect.py reads it.
# Skips entirely when there are no uncommitted .kt/.java changes, and when THIS
# session wrote none of them (bin/session_authorship.py, post-fix-gate's rule: Edit/Write/
# MultiEdit, a sub-agent's edit, a write-shaped Bash command, or an mtime inside one of its
# bash_write_ledger.tsv windows — see the "scope" block below); falls back to every dirty
# module when it cannot tell (a write tool it cannot see through, no shared module). The build is
# ./gradlew, or — in a monorepo without one at the root — the nearest gradlew
# above each changed file (e.g. android/gradlew), run from that folder.
#
# Cost: usually seconds — Gradle serves UP-TO-DATE when nothing in that source
# set moved. Escape hatch: TESTSOURCESET_GATE=0 to skip (logged).
#
# Loop-guard: MAX_ATTEMPTS then release with a warning (systemMessage), so a broken
# gate can never trap the session. Fail-open on internal error.
#
# Non-Claude agent or no usable Claude transcript (hooks/devkit_harness.py: Grok, whose
# transcript is its own updates.jsonl; a bridged agent; a caller with no transcript):
# the scope falls back to repo-wide, which under Grok meant compiling every test source
# set on every stop (OfficeReader, 2026-09-25). So:
#   - the repo-wide result is re-used while the tree is unchanged (fingerprint of HEAD +
#     diff + untracked contents, per session): one compile per unchanged tree per session;
#   - "degraded" sessions hold at most TESTSOURCESET_GATE_MAX_SESSION_BLOCKS (default 3)
#     blocks in total — the attempts guard alone restarts after each release — then the
#     stop is allowed with a systemMessage (still not a PASS); a PASS resets the count;
#   - Grok's observe-only session-end Stop (payload reason ≠ end_turn) compiles nothing.
# The SCOPE log line names the agent and the transcript kind.
#
# Stop hook protocol: stdin JSON; exit 2 blocks (stderr→Claude); exit 0 allows.
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG_DIR="${REPO_ROOT}/.claude/audit-gate"
mkdir -p "${LOG_DIR}"
[ -f "${LOG_DIR}/.gitignore" ] || printf '*\n' > "${LOG_DIR}/.gitignore" 2>/dev/null || true
LOG="${LOG_DIR}/testsourceset_gate.log"
TS="$(date +%Y-%m-%dT%H:%M:%S)"

# Read stdin: the session id keys the attempts file, and the transcript (read by the
# scoping step below) tells which files THIS session wrote. No `eval` (QA note):
# python prints the sanitized session id and bash reads it as plain data.
INPUT="$(cat)"
SID_RAW=""
HAVE_PY=1
command -v python3 >/dev/null 2>&1 || HAVE_PY=0
# Which agent runs this Stop (hooks/devkit_harness.py, next to this script or its link
# target): AGENT, TKIND (transcript kind), DEGRADED=1 when not Claude or no usable Claude
# transcript, TERMINAL=1 for Grok's session-end Stop. Without the helper: old behaviour.
HARNESS=""
for cand in "$(dirname "$0")/devkit_harness.py" \
            "$(python3 -c 'import os,sys; print(os.path.dirname(os.path.realpath(sys.argv[1])))' "$0" 2>/dev/null)/devkit_harness.py"; do
  [ -f "${cand}" ] && { HARNESS="${cand}"; break; }
done
AGENT="unknown"; TKIND="?"; DEGRADED=0; TERMINAL=0; REASON=""
if [ -n "${INPUT}" ] && [ "${HAVE_PY}" = 1 ]; then
  if [ -n "${HARNESS}" ]; then
    FIELDS="$(printf '%s' "${INPUT}" | HOOK_PPID="${PPID}" python3 "${HARNESS}" fields 2>/dev/null || true)"
    TAB="$(printf '\t')"
    OLDIFS="${IFS}"; IFS="${TAB}"
    # shellcheck disable=SC2086
    set -- ${FIELDS}
    IFS="${OLDIFS}"
    [ $# -ge 5 ] && { SID_RAW="$1"; AGENT="$2"; TKIND="$3"; DEGRADED="$4"; TERMINAL="$5"; REASON="${6:-}"; }
  fi
  [ -n "${SID_RAW}" ] || SID_RAW="$(printf '%s' "${INPUT}" | python3 -c '
import sys, json, re
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
sid = d.get("session_id") or d.get("sessionId") or ""
print(re.sub(r"[^a-zA-Z0-9_-]", "_", str(sid)))
' 2>/dev/null || true)"
elif [ -n "${INPUT}" ]; then
  echo "⚠ testsourceset_gate: python3 không có — không scope được theo phiên." >&2
fi

if [ -n "${SID_RAW}" ]; then
  ATTEMPTS_FILE="${LOG_DIR}/.testsourceset_attempts_${SID_RAW}"
else
  ATTEMPTS_FILE="${LOG_DIR}/.testsourceset_attempts"
fi
MAX_ATTEMPTS="${TESTSOURCESET_GATE_MAX_ATTEMPTS:-2}"
MAX_SESSION_BLOCKS="${TESTSOURCESET_GATE_MAX_SESSION_BLOCKS:-3}"
GUARD_FILE="${LOG_DIR}/.testsourceset_guard_${SID_RAW:-default}.json"
BLOCK_MSG_FILE="${LOG_DIR}/.testsourceset_block_${SID_RAW:-default}.txt"
guard() { [ -n "${HARNESS}" ] && python3 "${HARNESS}" guard "${GUARD_FILE}" "$@" 2>/dev/null; }
sysmsg() { if [ -n "${HARNESS}" ]; then python3 "${HARNESS}" sysmsg "$1"; else echo "$1" >&2; fi; }

log() { printf '%s [SID=%s] %s\n' "${TS}" "${SID_RAW:-default}" "$*" >>"${LOG}" 2>/dev/null || true; }

if [ "${TESTSOURCESET_GATE:-1}" = "0" ]; then
  log "SKIP — disabled via TESTSOURCESET_GATE=0"
  exit 0
fi
if [ "${TERMINAL}" = 1 ]; then
  # Grok's observe-only Stop when the session closes: no turn left to continue.
  log "SKIP — session-end Stop (agent=${AGENT} reason=${REASON})"
  exit 0
fi

cd "${REPO_ROOT}" 2>/dev/null || exit 0
# The Gradle wrapper is ./gradlew, or — in a monorepo whose Android/JVM app sits in
# a subfolder — a gradlew further down. No wrapper anywhere: nothing to compile.
if [ ! -x ./gradlew ] && [ -z "$(git ls-files -- '*/gradlew' 2>/dev/null | head -1)" ]; then
  log "SKIP — no ./gradlew"; exit 0
fi

# Uncommitted .kt/.java, staged + unstaged + untracked.
CHANGED="$( { git diff --name-only --diff-filter=ACMR 2>/dev/null
              git diff --cached --name-only --diff-filter=ACMR 2>/dev/null
              git ls-files --others --exclude-standard 2>/dev/null
            } | grep -E '\.(kt|java)$' | grep -v '/build/' | sort -u )"

[ -n "${CHANGED}" ] || { log "PASS — no uncommitted Kotlin/Java changes"; exit 0; }

# ── scope to the files THIS session wrote ────────────────────────────────────
# On a shared worktree, compiling every dirty module means one session's in-flight
# breakage blocks every other session (OfficeReader, 2026-09-09: a pdftools session
# blocked by modules a concurrent session had mid-edit). "Wrote" follows the rule of
# bin/session_authorship.py — the one post-fix-gate.py uses to tell whose test edit it is:
#   1. Edit/Write/MultiEdit/NotebookEdit file_path in the transcript — and in this
#      session's sub-agent transcripts (<transcript>/subagents/*.jsonl), whose edits
#      the parent transcript never shows;
#   2. a dirty file whose mtime falls inside one of THIS session's Bash windows in
#      .claude/audit-gate/bash_write_ledger.tsv (hooks/bash_write_ledger.sh). This is
#      what catches Kotlin written by `find | xargs sed -i`, a script or codegen,
#      whose path never appears in the transcript. Windows are long (p50 1.8s,
#      max 390s), so when an mtime sits in windows of several sessions the NARROWEST
#      wins and an exact tie goes to nobody;
#   3. a dirty file named by a WRITE-shaped Bash command (sed -i, perl -i, a `>`/`>>`
#      target, tee, cp, mv, rm, touch, ln, tar, rsync, unzip, patch, git apply/checkout…)
#      by its path, a glob or a directory holding it — the heredoc case, and a fallback
#      where the ledger is not wired. A path a command merely READS (cat, grep) does not
#      count.
# Outcomes: files found and dirty → compile only their modules. Session wrote no
# Kotlin/Java at all → PASS (exit 3 below): the dirty files belong to another session.
# Fail-closed (repo-wide, the old scope) on: no transcript, unreadable or unparsable
# input, a transcript with no tool call at all (nothing to judge by), a tool the rule
# cannot see through (a write-capable MCP tool, an external agent: its writes are
# unknown), no bin/session_authorship.py next to the hook, or a session whose Kotlin
# writes are none of them dirty.
SCOPED=""
SCOPE_RC=1
SELF_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null)"
AUTHORSHIP_BIN=""
for cand in "$(dirname "$(dirname "${SELF_REAL:-$0}")")/bin" "${REPO_ROOT}/.agents/devkit/bin" \
            "${DEVKIT_ROOT:-/nonexistent}/bin" "${HOME}/.universal-agent-devkit/bin"; do
  [ -f "${cand}/session_authorship.py" ] && { AUTHORSHIP_BIN="${cand}"; break; }
done
if [ "${HAVE_PY}" = 1 ] && [ -n "${INPUT}" ] && [ -n "${AUTHORSHIP_BIN}" ]; then
  SCOPED="$(TS_INPUT="${INPUT}" TS_CHANGED="${CHANGED}" TS_ROOT="${REPO_ROOT}" TS_BIN="${AUTHORSHIP_BIN}" python3 -c '
import os, sys, json
raw = os.environ.get("TS_INPUT", "")
changed = [l for l in os.environ.get("TS_CHANGED", "").splitlines() if l.strip()]
# realpath BOTH sides: on macOS /var is a symlink to /private/var.
root = os.path.realpath(os.environ.get("TS_ROOT", "."))
SRC = (".kt", ".java")
sys.path.insert(0, os.environ["TS_BIN"])
try:
    import session_authorship as sa
    d = json.loads(raw)
except Exception:
    sys.exit(1)
if not isinstance(d, dict):
    sys.exit(1)
tp = d.get("transcript_path")
if not isinstance(tp, str) or not tp or not os.path.isfile(tp):
    sys.exit(1)
cwd = d.get("cwd")
cwd = os.path.realpath(cwd if isinstance(cwd, str) and cwd else root)
trace = sa.session_trace(tp)
if trace is None:
    sys.exit(1)          # unreadable, or no tool call at all: nothing to judge by
edited_abs, bash, _started, _calls, opaque = trace
if opaque:
    sys.exit(4)          # a tool that may write where the rule cannot see: repo-wide
edited = {os.path.relpath(fp, root).replace(os.sep, "/") for fp in edited_abs if fp.endswith(SRC)}
named = sa.shell_named(bash)

def named_here(c):
    # Bash tokens are relative to the shell cwd; the payload cwd is the best known one.
    return sa.names_path(named, root, c) or (
        cwd != root and sa.names_path(named, cwd, os.path.relpath(os.path.join(root, c), cwd)))

windows = sa.bash_windows(root)
my_sid = d.get("session_id") if isinstance(d.get("session_id"), str) else ""
hit = []
for c in changed:
    mine = c in edited or named_here(c)
    if not mine and my_sid:
        try:
            mine = sa.window_owner(os.path.getmtime(os.path.join(root, c)), windows) == my_sid
        except OSError:
            mine = False
    if mine:
        hit.append(c)
if not edited and not hit and not any(t.endswith(SRC) for t in named):
    sys.exit(3)          # session wrote no Kotlin/Java at all → nothing of mine
if not hit:
    sys.exit(1)          # wrote Kotlin, none of it dirty → stay repo-wide
print("\n".join(hit))
' 2>/dev/null)"
  SCOPE_RC=$?
fi
[ "${SCOPE_RC}" -eq 0 ] || SCOPED=""

# Exit 3 = transcript parsed and this session wrote no Kotlin/Java. review_gate treats
# the same state as "none edited this session — pass"; compiling other sessions'
# in-flight Kotlin here is the cross-session block this scoping exists to remove.
if [ "${SCOPE_RC}" -eq 3 ]; then
  log "PASS — this session wrote no Kotlin/Java (dirty files belong to another session)"
  rm -f "${ATTEMPTS_FILE}" 2>/dev/null || true
  exit 0
fi
if [ -n "${SCOPED}" ]; then
  if [ "${SCOPED}" != "${CHANGED}" ]; then
    log "SCOPE — $(printf '%s\n' "${CHANGED}" | grep -c .) dirty file(s) → $(printf '%s\n' "${SCOPED}" | grep -c .) written by this session: $(printf '%s' "${SCOPED}" | tr '\n' ' ')"
  fi
  CHANGED="${SCOPED}"
else
  log "SCOPE — repo-wide (rc=${SCOPE_RC}: no usable transcript or bin/session_authorship.py, a write tool the scope cannot see through (rc=4), or this session's Kotlin/Java writes are not dirty; agent=${AGENT} transcript=${TKIND})"
fi

# Repo-wide compile at most once per unchanged tree per session: the result for the same
# tree fingerprint (HEAD + diff + untracked contents) is re-used. Scoped runs (a Claude
# transcript named the files) are cheap and keep compiling.
TREE_FP=""; CACHED=""
if [ -z "${SCOPED}" ] && [ -n "${HARNESS}" ]; then
  TREE_FP="$(python3 "${HARNESS}" fingerprint "${REPO_ROOT}" 2>/dev/null || true)"
  [ -n "${TREE_FP}" ] && CACHED="$(guard get "${TREE_FP}")"
  [ "${CACHED}" = block ] && [ ! -s "${BLOCK_MSG_FILE}" ] && CACHED=""
fi
if [ "${CACHED}" = pass ]; then
  log "PASS (reused result, tree unchanged fp=${TREE_FP})"
  rm -f "${ATTEMPTS_FILE}" 2>/dev/null || true
  exit 0
fi

# Paths are newline-separated and may contain spaces (QA K-7): iterate on
# newlines only, with globbing off.
set -f
NL='
'
OLDIFS="${IFS}"
IFS="${NL}"

# The Gradle build each file belongs to: ./gradlew covers every file; without it,
# the nearest folder above the file that holds an executable gradlew.
gradle_root_of() {
  if [ -x ./gradlew ]; then echo "."; return; fi
  local d
  d="$(dirname "$1")"
  while [ "${d}" != "." ] && [ "${d}" != "/" ]; do
    [ -x "${d}/gradlew" ] && { echo "${d}"; return; }
    d="$(dirname "${d}")"
  done
}
ROOT_FILES=""   # "<gradle root><TAB><file>" per line
for f in ${CHANGED}; do
  r="$(gradle_root_of "${f}")"
  [ -n "${r}" ] && ROOT_FILES="${ROOT_FILES}${NL}${r}	${f}"
done
ROOTS="$(printf '%s\n' "${ROOT_FILES}" | grep -v '^$' | cut -f1 | sort -u || true)"
[ -n "${ROOTS}" ] || { log "PASS — changed files are under no gradlew"; exit 0; }

# unit_test_task_of DIR — the unit-test compile task of the module in DIR:
# compile<TestBuildType>UnitTestKotlin, Debug unless its build file sets testBuildType.
# Same reading as scripts/matrix_detect.py _test_build_type: comment lines ignored,
# `testBuildType = "x"` (kts) or `testBuildType 'x'` (groovy), first match wins.
unit_test_task_of() {
  local tbt
  tbt="$(cat "$1/build.gradle" "$1/build.gradle.kts" 2>/dev/null \
        | grep -vE '^[[:space:]]*(//|\*|/\*)' \
        | sed -nE "s/(^|.*[^A-Za-z0-9_])testBuildType[[:space:]]*=?[[:space:]]*[\"']([A-Za-z0-9_]+)[\"'].*/\2/p" \
        | head -n 1)"
  [ -n "${tbt}" ] || tbt="debug"
  printf 'compile%s%sUnitTestKotlin' "$(printf '%s' "${tbt}" | cut -c1 | tr '[:lower:]' '[:upper:]')" \
    "$(printf '%s' "${tbt}" | cut -c2-)"
}

# compile_root ROOT FILES — compile the test source set of the modules FILES
# belong to, in the build at ROOT. Sets OUT, RC and TASKS (empty: nothing to run).
compile_root() {
  local root="$1" files="$2" f d rel m t mod _round
  OUT=""; RC=0; TASKS=""
  # Map each path to its Gradle module by walking up to the nearest build.gradle*,
  # and that module to its unit-test compile task.
  local modules=""
  for f in ${files}; do
    d="$(dirname "${f}")"
    while [ "${d}" != "${root}" ] && [ "${d}" != "." ] && [ "${d}" != "/" ]; do
      if [ -f "${d}/build.gradle.kts" ] || [ -f "${d}/build.gradle" ]; then
        if [ "${root}" = "." ]; then rel="${d}"; else rel="${d#"${root}"/}"; fi
        modules="${modules}${NL}:$(printf '%s' "${rel}" | tr '/' ':'):$(unit_test_task_of "${d}")"
        break
      fi
      d="$(dirname "${d}")"
    done
  done
  modules="$(printf '%s\n' "${modules}" | grep -v '^$' | sort -u || true)"
  [ -n "${modules}" ] || { log "PASS — changed files map to no Gradle module (${root})"; return; }

  # Only modules that really expose the task (app/library modules do; others don't).
  for m in ${modules}; do
    case "${m}" in
      :build-logic*|:gradle*) continue ;;
    esac
    TASKS="${TASKS}${NL}${m}"
  done
  TASKS="$(printf '%s\n' "${TASKS}" | grep -v '^$' || true)"
  [ -n "${TASKS}" ] || { log "PASS — no compilable modules (${root})"; return; }

  # A module without the task is not a failure, but it must not hide the others
  # (QA K-8: one "not found in project" used to PASS every module). Drop exactly
  # the modules Gradle names as lacking the task and re-run the rest.
  local keep missing
  for _round in 1 2 3; do
    OUT="$(cd "${root}" && ./gradlew ${TASKS} --quiet 2>&1)"
    RC=$?
    [ ${RC} -eq 0 ] && break
    missing="$(printf '%s\n' "${OUT}" | sed -n "s/.*not found in project '\\(:[^']*\\)'.*/\\1/p" | sort -u)"
    [ -n "${missing}" ] || break
    keep=""
    for t in ${TASKS}; do
      mod="${t%:*}"
      if printf '%s\n' "${missing}" | grep -qxF "${mod}"; then
        log "SKIP ${mod} — lacks ${t##*:}"
      else
        keep="${keep}${NL}${t}"
      fi
    done
    keep="$(printf '%s\n' "${keep}" | grep -v '^$' || true)"
    if [ "${keep}" = "${TASKS}" ]; then break; fi
    TASKS="${keep}"
    if [ -z "${TASKS}" ]; then
      log "PASS — no touched module has its unit-test compile task (${root})"
      OUT=""; RC=0
      return
    fi
  done
}

GRADLEW_CMD="./gradlew"
ALL_TASKS=""
TASKS=""; RC=0; OUT=""
[ "${CACHED}" = block ] && { RC=1; ROOTS=""; }
for root in ${ROOTS}; do
  files="$(printf '%s\n' "${ROOT_FILES}" | awk -F'\t' -v r="${root}" '$1 == r { print $2 }')"
  compile_root "${root}" "${files}"
  [ -n "${TASKS}" ] && ALL_TASKS="${ALL_TASKS}$([ "${root}" = "." ] || printf '[%s] ' "${root}")$(printf '%s ' ${TASKS})"
  if [ ${RC} -ne 0 ]; then
    [ "${root}" = "." ] || GRADLEW_CMD="cd ${root} && ./gradlew"
    break
  fi
done
IFS="${OLDIFS}"
TASKS_STR="$(printf '%s ' ${TASKS})"

if [ ${RC} -eq 0 ]; then
  log "PASS — ${ALL_TASKS}"
  rm -f "${ATTEMPTS_FILE}" 2>/dev/null || true
  [ -n "${TREE_FP}" ] && guard store "${TREE_FP}" pass
  exit 0
fi

# ── exit≠0 does NOT mean "the test source set is broken" ─────────────────────
# Gradle exits non-zero for daemon death, lock contention with a concurrent
# build, OOM, network/plugin resolution, or a harness timeout. Reporting those
# as "src/test vỡ" sends the reader hunting for a signature change that does not
# exist — and the old version also DISCARDED the output, so the real cause was
# unrecoverable. Measured 2026-07-27: this gate blocked with an empty error
# section while `compileDebugUnitTestKotlin` for the same five modules exited 0
# when re-run by hand.
# Classify before blaming, and always persist the raw output.
OUT_FILE="${LOG_DIR}/testsourceset_last_failure${SID_RAW:+_${SID_RAW}}.txt"
[ "${CACHED}" = block ] || printf '%s\n' "${OUT}" >"${OUT_FILE}" 2>/dev/null || true

if [ "${CACHED}" = block ]; then
  log "BLOCK re-used (tree unchanged fp=${TREE_FP}) — no compile"
elif printf '%s' "${OUT}" | grep -qE '^e: |error:|Compilation error|compile[A-Za-z0-9]*UnitTestKotlin.*FAILED'; then
  : # genuine compile failure — fall through to BLOCK below
else
  log "INFRA (rc=${RC}, không có dấu hiệu lỗi compile) — fail-open; output: ${OUT_FILE}"
  {
    echo "⚠️ TEST-SOURCESET GATE: gradle exit ${RC} nhưng KHÔNG có lỗi compile nào."
    echo "   Đây là hỏng hạ tầng (daemon/lock/OOM/network/timeout), KHÔNG phải src/test vỡ."
    echo "   Gate thả để không chặn nhầm. Output đầy đủ: ${OUT_FILE}"
    printf '%s\n' "${OUT}" | tail -8
  } >&2
  rm -f "${ATTEMPTS_FILE}" 2>/dev/null || true
  exit 0
fi

# Non-Claude agent / no usable transcript: a total block cap per session (a PASS resets
# it). The attempts guard below alone restarts after each release, so an agent whose tree
# changes every turn was blocked again and again.
if [ "${DEGRADED}" = 1 ] && [ -n "${HARNESS}" ]; then
  SBLOCKS="$(guard blocks)"
  if [ "${SBLOCKS:-0}" -ge "${MAX_SESSION_BLOCKS}" ]; then
    log "RELEASE — session cap (${SBLOCKS} blocks, agent=${AGENT}, transcript=${TKIND})"
    sysmsg "⚠ TEST-SOURCESET GATE đã chặn ${SBLOCKS} lần trong phiên ${SID_RAW:-?} (agent: ${AGENT}, transcript: ${TKIND}) — CHO DỪNG để agent không bị kẹt; test source set VẪN CHƯA compile, KHÔNG phải PASS. Người dùng cần xem lại: ${OUT_FILE} (released after ${SBLOCKS} blocks this session — TESTSOURCESET_GATE_MAX_SESSION_BLOCKS; not a PASS)"
    exit 0
  fi
fi

ATTEMPTS=0
[ -f "${ATTEMPTS_FILE}" ] && ATTEMPTS="$(cat "${ATTEMPTS_FILE}" 2>/dev/null || echo 0)"
ATTEMPTS=$((ATTEMPTS + 1))
printf '%s' "${ATTEMPTS}" >"${ATTEMPTS_FILE}" 2>/dev/null || true

if [ "${ATTEMPTS}" -gt "${MAX_ATTEMPTS}" ]; then
  log "RELEASE after ${ATTEMPTS} attempts — gate may be broken; letting the agent finish"
  rm -f "${ATTEMPTS_FILE}" 2>/dev/null || true
  sysmsg "⚠ TEST-SOURCESET GATE: đã chặn ${MAX_ATTEMPTS} lần liên tiếp — CHO DỪNG để không kẹt phiên; test source set VẪN CHƯA compile, KHÔNG phải PASS. Output: ${OUT_FILE} (released after ${MAX_ATTEMPTS} attempts; not a PASS)"
  exit 0
fi
[ "${DEGRADED}" = 1 ] && guard add-block >/dev/null

if [ "${CACHED}" = block ]; then
  log "BLOCK (attempt ${ATTEMPTS}, re-used) — $(head -1 "${BLOCK_MSG_FILE}" 2>/dev/null)"
  cat "${BLOCK_MSG_FILE}" >&2
  exit 2
fi

# Name the real cause before blaming signature drift.
#
# An unresolved merge leaves `<<<<<<<` markers inside production sources, and Kotlin reports them as
# a wall of "Syntax error: Expecting an element" — nothing about it looks like a broken call site.
# Sending the reader to hunt for a changed parameter list then costs a full detour, and a gate that
# misnames the cause actively pushes people to edit the wrong file. Measured 2026-08-25: an external
# process merged a stale remote commit into trunk mid-session and this gate blamed signatures.
UNMERGED="$(git -C "${REPO_ROOT}" diff --name-only --diff-filter=U 2>/dev/null || true)"

log "BLOCK (attempt ${ATTEMPTS}) — ${TASKS_STR}"
{
  echo "⛔ TEST-SOURCESET GATE: test source set không compile."
  echo ""
  if [ -n "${UNMERGED}" ]; then
    echo "NGUYÊN NHÂN: repo đang có MERGE CHƯA GIẢI QUYẾT. Dấu xung đột nằm trong source"
    echo "production, nên Kotlin báo hàng loạt lỗi cú pháp — KHÔNG phải call site trong src/test vỡ."
    echo ""
    echo "File chưa merge xong:"
    printf '%s\n' "${UNMERGED}" | sed 's/^/  • /' | head -15
    echo ""
    printf '%s\n' "${OUT}" | grep -E '^e: |error:' | head -8
    echo ""
    echo "Giải quyết merge TRƯỚC (hoặc \`git merge --abort\`) rồi chạy lại: ${GRADLEW_CMD} ${TASKS_STR}"
    echo "CẤM sửa call site để né lỗi này — làm vậy là tự chọn một bên của merge mà không có quyền."
  else
    echo "Module tôi vừa sửa có call site trong src/test đang vỡ. \`assemble…\`"
    echo "và \`compile…Kotlin\` KHÔNG compile test source set nên chúng vẫn xanh —"
    echo "chỉ CI/release gate mới đỏ. Đây là P0 thật đã xảy ra 2026-07-16."
    echo ""
    printf '%s\n' "${OUT}" | grep -E '^e: |error:' | head -15
    echo ""
    echo "Sửa call site trong src/test (thường do đổi signature: thêm/bớt/đổi thứ tự param),"
    echo "rồi chạy lại: ${GRADLEW_CMD} ${TASKS_STR}"
  fi
} >"${BLOCK_MSG_FILE}" 2>/dev/null
[ -n "${TREE_FP}" ] && guard store "${TREE_FP}" block
cat "${BLOCK_MSG_FILE}" >&2
exit 2
