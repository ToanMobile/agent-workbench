#!/usr/bin/env bash
# super-build-dispatch.sh — dispatch a single GitHub issue to a headless `claude -p` worker.
#
# Contract (per .claude/skills/super-build/SKILL.md):
#   - Arg: issue number N
#   - Env: BASE_BRANCH (required) — the branch the worktree is created from
#          REPO_DIR    (optional) — defaults to PWD; the working repo root
#          SKILL_DIR   (optional) — defaults to the dir this script lives in's parent
#          MAX_TURNS   (optional) — default 250
#   - Side effects:
#       * agent-kit worktree add .claude/worktrees/issue-N loop/issue-N --lane=build --base=BASE_BRANCH (DevKit links, ignored config + hooks)
#       * runs `claude -p` inside that worktree with the composed prompt
#       * captures stdout+stderr to .planning/super-build-logs/issue-N.log
#   - Exit codes:
#       0  success           — worker produced `🔧 [chore] loop: close #N` commit on loop/issue-N
#       2  worker non-zero   — `claude -p` exited non-zero AND no recognizable done/WIP marker
#       3  no done-commit    — `claude -p` exited zero but no `🔧 [chore] loop: close #N` commit
#       4  HUMAN GATE        — log contains `HUMAN GATE TRIPPED:`
#       5  WIP-PARTIAL       — log final assistant message starts with `WIP-PARTIAL:` AND
#                              a `🚧 [wip] loop: #N partial` commit exists on the branch
#   Subjects follow writing-standard.md § 1. The old `chore(loop):` / `wip(loop):` shapes
#   are still accepted so a branch started before the switch is not read as a failure.
#
# Notes:
#   - The dispatcher never merges, never closes the issue, never edits labels — those
#     are the orchestrator's job. This script just runs the worker and reports outcome.
#   - The worktree is left intact in all exit paths so a human can inspect it.

set -uo pipefail

N="${1:-}"
if [[ -z "$N" ]]; then
  echo "usage: $0 <issue-number>" >&2
  exit 64
fi

if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  echo "error: issue number must be numeric, got: $N" >&2
  exit 64
fi

BASE_BRANCH="${BASE_BRANCH:-}"
if [[ -z "$BASE_BRANCH" ]]; then
  echo "error: BASE_BRANCH env var is required" >&2
  exit 64
fi

REPO_DIR="${REPO_DIR:-$PWD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${SKILL_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
MAX_TURNS="${MAX_TURNS:-250}"

PREAMBLE="$SKILL_DIR/references/worker-preamble.md"
if [[ ! -f "$PREAMBLE" ]]; then
  echo "error: worker preamble not found at $PREAMBLE" >&2
  exit 64
fi

cd "$REPO_DIR" || { echo "error: cannot cd to REPO_DIR=$REPO_DIR" >&2; exit 64; }

# Verify we're in a git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: $REPO_DIR is not a git repository" >&2
  exit 64
fi

# Lane worktrees live in the MAIN checkout's .claude/worktrees (`worktree add --lane` refuses any other folder): run from a session's own
# worktree, say so now instead of failing later inside add, after the prompt is written.
MAIN_DIR=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
TOP_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$MAIN_DIR" && "$(cd "$MAIN_DIR" && pwd -P)" != "$(cd "$TOP_DIR" && pwd -P)" ]]; then
  echo "error: run from the main checkout ($MAIN_DIR), not from a linked worktree: lane worktrees live in its .claude/worktrees" >&2
  exit 64
elif [[ "$(pwd -P)" != "$(cd "$TOP_DIR" && pwd -P)" ]]; then
  echo "error: run from the repository root ($TOP_DIR), not a subfolder: the worktree path .claude/worktrees/issue-$N is relative to it" >&2
  exit 64
fi
# The DevKit makes the worktree (below): checked here, before any network call or file is written
WT_PY="$REPO_DIR/.agents/devkit/scripts/git/worktree.py"
if [[ ! -f "$WT_PY" ]]; then
  echo "error: DevKit missing ($WT_PY): run agent-kit init in $REPO_DIR first" >&2
  exit 64
fi

# Verify base branch exists locally or on origin
if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  if ! git rev-parse --verify "origin/$BASE_BRANCH" >/dev/null 2>&1; then
    echo "error: base branch '$BASE_BRANCH' not found locally or on origin" >&2
    exit 64
  fi
fi

WORKTREE_DIR=".claude/worktrees/issue-$N"
WORKER_BRANCH="loop/issue-$N"
LOG_DIR="$REPO_DIR/.planning/super-build-logs"
LOG_FILE="$LOG_DIR/issue-$N.log"
PROMPT_FILE="$LOG_DIR/issue-$N.prompt.md"


# Refuse to clobber an existing worktree/branch silently
if [[ -e ".worktrees/issue-$N" ]]; then
  echo "error: legacy worktree .worktrees/issue-$N exists — inspect it before resuming" >&2
  echo "       Stop its worker, preserve edits, then git worktree move .worktrees/issue-$N $WORKTREE_DIR" >&2
  exit 64
fi
if [[ -e "$WORKTREE_DIR" ]]; then
  echo "error: worktree path $WORKTREE_DIR already exists — refusing to clobber" >&2
  echo "       (remove with: python3 \"$WT_PY\" remove $WORKTREE_DIR — agent-kit worktree remove; it refuses only when work would be lost)" >&2
  exit 64
fi
if git rev-parse --verify "$WORKER_BRANCH" >/dev/null 2>&1; then
  echo "error: branch $WORKER_BRANCH already exists — refusing to clobber" >&2
  echo "       merged: python3 \"$WT_PY\" prune-branch $WORKER_BRANCH; not merged: it holds work — resume it by hand or ask the user to delete it" >&2
  exit 64
fi
# `worktree add --lane` (below) resumes a branch only origin has; this dispatcher always starts fresh off BASE_BRANCH (BASE_SHA and the
# done-commit check rely on it): refuse a remote leftover like the local one above. Origin unreachable: add --lane would refuse too, so
# say it here. The probe is the DevKit's own bounded git call (the user's own ssh/credential setup, killed after its timeout: headless)
# — the very check add --lane makes, so the two never disagree.
if git remote get-url origin >/dev/null 2>&1; then
  LS_RC=0
  LS_ERR=$(GIT_TERMINAL_PROMPT=0 python3 - "$WT_PY" "$WORKER_BRANCH" 2>&1 >/dev/null <<'PY'
import importlib.util, sys
try:
    spec = importlib.util.spec_from_file_location("devkit_worktree", sys.argv[1])
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    r = m.git(".", "ls-remote", "--exit-code", "--heads", "origin", "refs/heads/" + sys.argv[2], check=False)
except Exception as e:   # an old or broken DevKit (load or call) is no network fault: its own exit code and its reason
    print(f"DevKit worktree.py unusable: {e!r}", file=sys.stderr)
    sys.exit(3)
print((r.stderr or "").strip(), file=sys.stderr)
sys.exit(r.returncode)
PY
  ) || LS_RC=$?
  # git's first fatal/error line carries the reason (its hint lines follow it); otherwise the last line said
  LS_WHY=$( { printf '%s\n' "$LS_ERR" | grep -m1 -E '^(fatal|error|DevKit)'; } || printf '%s\n' "$LS_ERR" | grep -v '^[[:space:]]*$' | tail -1)
  LS_WHY=$(printf '%s' "$LS_WHY" | cut -c1-200)
  if [[ "$LS_RC" -eq 0 ]]; then
    echo "error: branch $WORKER_BRANCH already exists on origin — refusing to clobber" >&2
    exit 64
  elif [[ "$LS_RC" -eq 3 || "$LS_RC" -eq 127 ]]; then   # 127: no python3 to run the DevKit at all
    echo "error: ${LS_WHY:-DevKit worktree.py unusable} — repair the DevKit install (agent-kit init) / python3 in $REPO_DIR" >&2
    exit 64
  elif [[ "$LS_RC" -ne 2 ]]; then
    echo "error: cannot reach origin to check $WORKER_BRANCH (git ls-remote exit $LS_RC${LS_WHY:+: $LS_WHY})" >&2
    exit 64
  fi
fi

# Compose the worker prompt: preamble + issue body + working-dir footer
SB_BIN="$REPO_DIR/.claude/bin"
ISSUE_JSON=$(python3 "$SB_BIN/super-board-github-read.py" --kind issue -- issue view "$N" --json number,title,body 2>&1) || {
  echo "error: gh issue view #$N failed:" >&2
  echo "$ISSUE_JSON" >&2
  exit 79
}
LABELS_JSON=$(python3 "$SB_BIN/super-board-github-read.py" --kind json -- issue view "$N" --json labels) || exit $?
CARD_JSON=$(printf '%s' "$ISSUE_JSON" | jq -c --argjson labels "$LABELS_JSON" '[{number:.number,status:"Ready",body:.body,labels:($labels.labels // [])}]')
SKILLS_RC=0
printf '%s' "$CARD_JSON" | python3 "$SB_BIN/super-board-skills-ready.py" --root "$REPO_DIR" --host claude --cards - --lane build || SKILLS_RC=$?
[ "$SKILLS_RC" -eq 0 ] || exit "$SKILLS_RC"
mkdir -p "$LOG_DIR"

ISSUE_TITLE=$(printf '%s' "$ISSUE_JSON" | jq -r '.title')
ISSUE_BODY=$(printf '%s' "$ISSUE_JSON" | jq -r '.body')

{
  printf 'First operation: repeat super-board-skills-ready.py --root %s --host claude --cards - --lane build with %s as stdin. Halt on exit 10 before any lifecycle writes. Recheck conditional helpers with --require before use.\n' "$REPO_DIR" "$CARD_JSON"
  cat "$PREAMBLE"
  printf '\n# Issue #%s — %s\n\n' "$N" "$ISSUE_TITLE"
  printf '%s\n' "$ISSUE_BODY"
  printf '\n---\n\n'
  printf 'Working directory: %s/%s (branch %s, based on %s)\n' "$REPO_DIR" "$WORKTREE_DIR" "$WORKER_BRANCH" "$BASE_BRANCH"
  printf 'Log file: %s/%s\n' "$REPO_DIR" "$LOG_FILE"
} > "$PROMPT_FILE"

# Create the worktree on its branch off BASE_BRANCH with the DevKit, never a plain `git worktree add` (agent-workbench#93): the worker
# runs IN it, so it needs the DevKit links and the git-ignored hooks the settings run (missing, every python3 hook exits 2 and blocks
# the tool), and a Unity Library cloned copy-on-write instead of a full re-import. Exit 4 = under the disk floor, nothing made.
WT_RC=0
python3 "$WT_PY" add "$WORKTREE_DIR" "$WORKER_BRANCH" --lane=build --base="$BASE_BRANCH" >>"$LOG_FILE" 2>&1 || WT_RC=$?
if [[ "$WT_RC" -eq 4 ]]; then   # 4 is this dispatcher's HUMAN GATE code: a missing precondition stays 64, the message says which
  echo "error: under the DevKit worktree disk floor (WORKTREE_DISK_MIN_GIB) — free space first; see $LOG_FILE" >&2
  exit 64
elif [[ "$WT_RC" -ne 0 ]]; then
  echo "error: agent-kit worktree add failed (exit $WT_RC) — see $LOG_FILE" >&2
  exit 64
fi

# Record the base SHA so we can diff afterward
BASE_SHA=$(git -C "$WORKTREE_DIR" rev-parse HEAD)

echo "▶︎ dispatching worker for issue #$N — worktree $WORKTREE_DIR — base $BASE_BRANCH @ ${BASE_SHA:0:7}" | tee -a "$LOG_FILE"

# Run the worker. stdin gets the composed prompt; stdout+stderr both stream to the log.
# We do NOT use --output-format stream-json here because we want a plain-text log we
# can grep for the HUMAN GATE / WIP-PARTIAL markers. The orchestrator gets the same log.
WORKER_EXIT=0
(
  cd "$WORKTREE_DIR" || exit 99
  exec claude -p \
    --dangerously-skip-permissions \
    --max-turns "$MAX_TURNS" \
    < "$PROMPT_FILE"
) >>"$LOG_FILE" 2>&1 || WORKER_EXIT=$?

echo "▶︎ worker for issue #$N exited with code $WORKER_EXIT" | tee -a "$LOG_FILE"

# Inspect outcome on the worker branch
HEAD_SHA=$(git -C "$WORKTREE_DIR" rev-parse HEAD)
COMMITS_RANGE="${BASE_SHA}..${HEAD_SHA}"

CLOSE_COMMIT=""
WIP_COMMIT=""
if [[ "$BASE_SHA" != "$HEAD_SHA" ]]; then
  CLOSE_COMMIT=$(git -C "$WORKTREE_DIR" log --format="%H %s" "$COMMITS_RANGE" 2>/dev/null \
    | grep -E "^[0-9a-f]+ ([^ ]+ \[chore\] loop|chore\(loop\)): close #$N( |$)" | head -1 || true)
  WIP_COMMIT=$(git -C "$WORKTREE_DIR" log --format="%H %s" "$COMMITS_RANGE" 2>/dev/null \
    | grep -E "^[0-9a-f]+ ([^ ]+ \[wip\] loop|wip\(loop\)): #$N partial" | head -1 || true)
fi

# Detect HUMAN GATE in log
if grep -q "HUMAN GATE TRIPPED:" "$LOG_FILE"; then
  echo "▶︎ HUMAN GATE TRIPPED detected in log for issue #$N" | tee -a "$LOG_FILE"
  exit 4
fi

# Detect WIP-PARTIAL: requires both the literal log marker AND a wip commit
if [[ -n "$WIP_COMMIT" ]] && grep -q "^WIP-PARTIAL:" "$LOG_FILE"; then
  echo "▶︎ WIP-PARTIAL detected for issue #$N: $WIP_COMMIT" | tee -a "$LOG_FILE"
  exit 5
fi

# Detect success: a `[chore] loop: close #N` commit is present
if [[ -n "$CLOSE_COMMIT" ]]; then
  if [[ "$WORKER_EXIT" -ne 0 ]]; then
    echo "▶︎ worker exited non-zero ($WORKER_EXIT) but produced close-commit; treating as success" | tee -a "$LOG_FILE"
  fi
  echo "▶︎ success: $CLOSE_COMMIT" | tee -a "$LOG_FILE"
  exit 0
fi

# No done-commit
if [[ "$WORKER_EXIT" -ne 0 ]]; then
  echo "▶︎ worker failed (exit $WORKER_EXIT) with no done-commit" | tee -a "$LOG_FILE"
  exit 2
fi

echo "▶︎ worker exited 0 but produced no [chore] loop: close #$N commit" | tee -a "$LOG_FILE"
exit 3
