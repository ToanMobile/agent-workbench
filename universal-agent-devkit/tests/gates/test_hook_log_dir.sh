#!/usr/bin/env bash
# Where hooks keep their logs and state when CLAUDE_PROJECT_DIR is unset (audit 2026-10-09, finding C5): they took the git
# root of the PROCESS cwd, else the process cwd itself, and ignored the payload's `cwd` — a fuzz run at / created
# /.claude/audit-gate/. Now the project is CLAUDE_PROJECT_DIR, else the git tree of the payload cwd (the process cwd when
# the payload has none); outside a git tree nothing is created (logging skipped; the Stop gates that keep a loop guard there,
# claim_check and review_gate, pass), and a `git restore` whose backup has no project to go into is not allowed.
# Each hook runs with CLAUDE_PROJECT_DIR unset and its process cwd in a scratch dir X that is NOT a git tree:
#   A. payload cwd = a git repo R → state lands in R/.claude/audit-gate, nothing in X;
#   B. payload cwd = a non-git dir N → no .claude/ in X or N.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="${LD_HOOKS:-$DEVKIT_DIR/hooks}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset CLAUDE_PROJECT_DIR

X="$TMP/x"; N="$TMP/n"; R="$X/repo"     # R sits INSIDE the non-git X, like a checkout under a home folder
mkdir -p "$X" "$N" "$R/src"
git -C "$R" init -q . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
printf 'class A\n' > "$R/src/A.kt"; printf 'class B\n' > "$N/B.kt"
git -C "$R" add -A && git -C "$R" commit -qm init && printf 'class A2\n' > "$R/src/A.kt"
python3 -I -c 'import json,sys; open(sys.argv[1],"w").write(json.dumps({"type":"user","cwd":sys.argv[2],"message":{"role":"user","content":"go"}})+"\n")' \
  "$TMP/tr.jsonl" "$R"

# payload <cwd> <event> <tool> <tool_input json> [extra json fields]
payload() {
  python3 -I -c 'import json,sys; d={"session_id":"s1","transcript_path":sys.argv[1],"cwd":sys.argv[2],"hook_event_name":sys.argv[3]}
if sys.argv[4]: d.update(tool_name=sys.argv[4], tool_input=json.loads(sys.argv[5]))
d.update(json.loads(sys.argv[6] if len(sys.argv) > 6 else "{}")); print(json.dumps(d))' "$TMP/tr.jsonl" "$@" > "$TMP/in.json"
}
# run <hook> [VAR=val…]: from X, CLAUDE_PROJECT_DIR unset; rc in $RC
run() { local h="$1"; shift; ( cd "$X" && env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOKS/$h" < "$TMP/in.json" > /dev/null 2>&1 ); RC=$?; }
clean() { rm -rf "$X/.claude" "$N/.claude" "$R/.claude"; }
# expect <label> <file that must exist under R/.claude/audit-gate, or "-" when nothing may be created anywhere>
expect() {
  local label="$1" want="$2" bad=""
  [ -e "$X/.claude" ] && bad="$bad X/.claude"
  [ -e "$N/.claude" ] && bad="$bad N/.claude"
  if [ "$want" = "-" ]; then
    [ -e "$R/.claude" ] && bad="$bad R/.claude"
  else
    [ -e "$R/.claude/audit-gate/$want" ] || bad="$bad (no R/.claude/audit-gate/$want)"
  fi
  [ -z "$bad" ] && ok "$label" || fail "$label:$bad"
  clean
}

# (hook | event | tool | tool_input for case A | tool_input for case B | file A must create | extra fields | env)
NOEXTRA='{}'
while IFS='|' read -r h ev tool inA inB want extra envs; do
  [ -n "$h" ] || continue
  inA="${inA//@R@/$R}"; inA="${inA//@X@/$X}"; inB="${inB//@N@/$N}"; inB="${inB//@X@/$X}"
  payload "$R" "$ev" "$tool" "$inA" "${extra:-$NOEXTRA}"; run "$h" $envs
  expect "$h: payload cwd in a git repo → state in that repo, nothing in the process cwd (rc $RC)" "$want"
  payload "$N" "$ev" "$tool" "$inB" "${extra:-$NOEXTRA}"; run "$h" $envs
  expect "$h: payload cwd outside any git repo → no .claude/ created (rc $RC)" "-"
done <<'EOF'
precode_gate.sh|PreToolUse|Edit|{"file_path":"@R@/src/A.kt","old_string":"a","new_string":"b"}|{"file_path":"@N@/B.kt","old_string":"a","new_string":"b"}|precode_gate.log||
read_ledger.sh|PostToolUse|Read|{"file_path":"@R@/src/A.kt"}|{"file_path":"@N@/B.kt"}|read_ledger.tsv||
churn_guard.sh|PostToolUse|Edit|{"file_path":"@R@/src/A.kt","old_string":"a","new_string":"b"}|{"file_path":"@N@/B.kt","old_string":"a","new_string":"b"}|churn_guard.log||
comment_claim_guard.sh|PostToolUse|Write|{"file_path":"@R@/src/A.kt","content":"// plain\nclass A"}|{"file_path":"@N@/B.kt","content":"// plain\nclass B"}|comment_claim_guard.log||
worktree_guard.sh|PreToolUse|Bash|{"command":"ls"}|{"command":"ls"}|wg_scan||
claim_check.sh|Stop||||claim_check.log|{"last_assistant_message":"Lỗi nằm ở Ghost.kt:4211."}|
review_gate.sh|Stop||||review_gate.log|{"last_assistant_message":"xong"}|
hardware_safety_gate.sh|PreToolUse|Bash|{"command":"adb reboot"}|{"command":"adb reboot"}|hardware_safety_gate.log||HARDWARE_OVERRIDE=1
block-dangerous-git.sh|PreToolUse|Bash|{"command":"git restore @R@/src/A.kt"}|{"command":"git restore @X@/repo/src/A.kt"}|restore-backup||
EOF

[ "$FAILS" -eq 0 ] && echo "✅ test_hook_log_dir: all passed" || { echo "❌ test_hook_log_dir: $FAILS failed"; exit 1; }
