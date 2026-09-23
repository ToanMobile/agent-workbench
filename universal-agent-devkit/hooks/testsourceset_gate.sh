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
# Skips entirely when there are no uncommitted .kt/.java changes. The build is
# ./gradlew, or — in a monorepo without one at the root — the nearest gradlew
# above each changed file (e.g. android/gradlew), run from that folder.
#
# Cost: usually seconds — Gradle serves UP-TO-DATE when nothing in that source
# set moved. Escape hatch: TESTSOURCESET_GATE=0 to skip (logged).
#
# Loop-guard: MAX_ATTEMPTS then release with a warning, so a broken gate can
# never trap the session. Fail-open on internal error.
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

# Read stdin to isolate session attempt tracking and file scope.
# No `eval` (QA note): python prints the sanitized session id on line 1 and one
# touched source path per following line; bash reads them as plain data.
INPUT="$(cat)"
SID_RAW=""
SESSION_FILES=""
if [ -n "${INPUT}" ] && command -v python3 >/dev/null 2>&1; then
  PARSED="$(printf '%s' "${INPUT}" | python3 -c '
import sys, json, os, re
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
sid = d.get("session_id") or d.get("sessionId") or ""
print(re.sub(r"[^a-zA-Z0-9_-]", "_", str(sid)))
tp = d.get("transcript_path")
files = set()
if tp and os.path.exists(tp):
    with open(tp, "r", encoding="utf-8", errors="ignore") as f:
        for m in re.finditer(r"[^\s\"\x27]+\.(?:kt|java)\b", f.read()):
            fpath = m.group(0)
            if "/src/" in fpath and "/build/" not in fpath:
                files.add(fpath)
for fp in sorted(files):
    print(fp)
' 2>/dev/null || true)"
  SID_RAW="$(printf '%s\n' "${PARSED}" | sed -n 1p)"
  SESSION_FILES="$(printf '%s\n' "${PARSED}" | sed -n '2,$p')"
elif [ -n "${INPUT}" ]; then
  echo "⚠ testsourceset_gate: python3 không có — không scope được theo phiên." >&2
fi

if [ -n "${SID_RAW}" ]; then
  ATTEMPTS_FILE="${LOG_DIR}/.testsourceset_attempts_${SID_RAW}"
else
  ATTEMPTS_FILE="${LOG_DIR}/.testsourceset_attempts"
fi
MAX_ATTEMPTS="${TESTSOURCESET_GATE_MAX_ATTEMPTS:-2}"

log() { printf '%s [SID=%s] %s\n' "${TS}" "${SID_RAW:-default}" "$*" >>"${LOG}" 2>/dev/null || true; }

if [ "${TESTSOURCESET_GATE:-1}" = "0" ]; then
  log "SKIP — disabled via TESTSOURCESET_GATE=0"
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

# Paths are newline-separated and may contain spaces (QA K-7): iterate on
# newlines only, with globbing off.
set -f
NL='
'
OLDIFS="${IFS}"
IFS="${NL}"

# If transcript specifies files touched in this session, scope to those files
if [ -n "${SESSION_FILES:-}" ] && [ -n "${CHANGED}" ]; then
  MATCHED=""
  for f in ${CHANGED}; do
    for sf in ${SESSION_FILES}; do
      if [[ "$sf" == *"$f"* ]] || [[ "$f" == *"$sf"* ]]; then
        MATCHED="${MATCHED}${NL}${f}"
        break
      fi
    done
  done
  MATCHED="$(printf '%s\n' "${MATCHED}" | grep -v '^$' | sort -u || true)"
  if [ -n "${MATCHED}" ]; then
    CHANGED="${MATCHED}"
    log "Scoped compilation checks to active session (${SID_RAW:-default}): ${CHANGED}"
  fi
fi

[ -n "${CHANGED}" ] || { log "PASS — no uncommitted Kotlin/Java changes"; exit 0; }

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
printf '%s\n' "${OUT}" >"${OUT_FILE}" 2>/dev/null || true

if printf '%s' "${OUT}" | grep -qE '^e: |error:|Compilation error|compile[A-Za-z0-9]*UnitTestKotlin.*FAILED'; then
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

ATTEMPTS=0
[ -f "${ATTEMPTS_FILE}" ] && ATTEMPTS="$(cat "${ATTEMPTS_FILE}" 2>/dev/null || echo 0)"
ATTEMPTS=$((ATTEMPTS + 1))
printf '%s' "${ATTEMPTS}" >"${ATTEMPTS_FILE}" 2>/dev/null || true

if [ "${ATTEMPTS}" -gt "${MAX_ATTEMPTS}" ]; then
  log "RELEASE after ${ATTEMPTS} attempts — gate may be broken; letting Claude finish"
  rm -f "${ATTEMPTS_FILE}" 2>/dev/null || true
  exit 0
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
} >&2
exit 2
