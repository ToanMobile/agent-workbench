#!/usr/bin/env bash
# Regression test (ported to gate speed v26 mục 1, 07/11): a repeated Stop must say WHY it blocks again and what to run.
# Before v26 (gate speed, 2026-10-15) the hook re-ran the whole gate when a session's stored block missed, and wrote one log line naming
# the part of the key that moved ("repeat miss sid=<sid> differs=fp,tree,local,sig"). v26 removed the stored block with the gate call:
# the Stop runs NO suite and starts no gate; it reads the receipt of the tree (bin/tree_fp.py receipt_for_tree) and, when there is none,
# blocks with the exact gate command for this kind of repo and logs why each receipt was refused ("no receipt: <file>: <reason>").
# What this file keeps of the old contract, on the v26 mechanism:
#   M1 no receipt, on the trunk branch with a verified_head: the block names the reason and the exact command
#      `python3 <gate> --run-tests --scoped --brief --diff <verified_head>`; the log says "no receipt"; nothing is started
#   M2 a receipt for an OLDER tree does not count: blocked, and the log names the refusal (": fp", the receipt is of another tree);
#      back on that older tree the same receipt is accepted again (control)
#   M3 on a branch that is not the trunk the command carries no --diff
#   M4 a receipt of this tree whose run started after verified_head, with the commits between off the trunk: blocked, and the block
#      says those commits were not checked (the range reason)
# The kit under test is a COPY whose bin/post-fix-gate.py counts its starts when GATE_SPAWNS names a file (only the hook's Stops set it).
# The suite PASSES here, so a hook that ran the gate itself would allow (the pre-v26 kit). bash 3.2 compatible;
# REPEATMISS_KIT=<kit dir> tests another copy of the kit (a mutant, or the pre-v26 kit, must go red).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export WORKTREE_TRUNK_MODE=0   # K12 (18/10): các ca ở đây là phiên sửa thẳng main (không trunk mode); ở trunk mode Stop tại main không gate (test_regression_gate_trunk_main.sh)
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_KIT="${REPEATMISS_KIT:-$DEVKIT_DIR}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID REGRESSION_GATE_MAX_ATTEMPTS DEVKIT_GATE_CACHE_MAX_S TEST_RUN_LOCK_WAIT_S
export FLAKY_RETRY=0 VACUITY_REVERT=0 DEVKIT_GATE_CACHE=0

KIT="$TMP/kit"
if ! { mkdir -p "$KIT" && cp -R "$SRC_KIT/hooks" "$KIT/hooks" && cp -R "$SRC_KIT/bin" "$KIT/bin"; }; then echo "✖ cannot copy the kit $SRC_KIT"; exit 1; fi
for d in scripts profiles templates rules; do [ -e "$SRC_KIT/$d" ] && ln -s "$SRC_KIT/$d" "$KIT/$d"; done   # what the gate imports (scripts/governance ...)
python3 -I -c 'import sys
p = sys.argv[1]; src = open(p, encoding="utf-8").read().split("\n")
i = next(n for n, l in enumerate(src) if l.startswith("import "))
src.insert(i, "import os as _spawn_os; _spawn_os.environ.get(\"GATE_SPAWNS\") and open(_spawn_os.environ[\"GATE_SPAWNS\"], \"a\").write(\"x\")")
open(p, "w", encoding="utf-8").write("\n".join(src))' "$KIT/bin/post-fix-gate.py" || { echo "✖ cannot instrument the gate copy"; exit 1; }
HOOK="$KIT/hooks/regression_gate.sh"
GATE="$KIT/bin/post-fix-gate.py"
GATE_REAL="$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$GATE")"   # the block prints the real path (/private/var on macOS)
SPAWNS="$TMP/spawns"; : > "$SPAWNS"
spawns() { wc -c < "$SPAWNS" | tr -d ' '; }

printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"c-r"}' > "$TMP/claude.jsonl"
R="$TMP/repo"; mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
printf '.env\n.claude/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/regression_checklist.md\n' > .gitignore
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-R","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
LOG="$R/.claude/audit-gate/regression_gate.log"
STATE="$R/.claude/audit-gate/regression_gate.state.json"
stopx() { # $1 = session id
  printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$TMP/claude.jsonl" \
    | env GATE_SPAWNS="$SPAWNS" CLAUDE_PROJECT_DIR="$R" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"
  RC=$?
}
vh() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verified_head") or "")' "$STATE" 2>/dev/null; }
# gaterun [args]: the agent's gate run (output in $TMP/gate.out, exit code in GRC)
gaterun() { ( cd "$R" && CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --scoped --brief "$@" ) >"$TMP/gate.out" 2>&1; GRC=$?; }
nolines() { grep -c "no receipt:" "$LOG" 2>/dev/null | tr -d ' '; }
REASON="chưa có biên nhận gate cho code hiện tại"

stopx c-one   # clean tree: verified_head = the start point
V="$(vh)"

# M1
echo "fun ok() = 2" > src/Core.kt
stopx c-one
if [ "$RC" = 2 ] && [ -n "$V" ] && grep -q "$REASON" "$TMP/err" \
   && grep -qF "\`python3 $GATE_REAL --run-tests --scoped --brief --diff $V\`" "$TMP/err" && [ "$(nolines)" -ge 1 ] && [ "$(spawns)" = 0 ]; then
  ok "M1: no receipt: blocked with the reason and the exact command (--diff <verified_head> on the trunk), logged 'no receipt', nothing started"
else
  fail "M1: rc=$RC vh='$V' spawns=$(spawns) nolines=$(nolines) err='$(head -c 400 "$TMP/err")'"
fi

# M2: a receipt of tree A, the Stop on tree B
echo "fun ok() = 3" > src/Core.kt
gaterun --diff "$V"; ga=$GRC
echo "fun ok() = 4" > src/Core.kt
n=$(nolines); stopx c-one; b1=$RC; b1e="$(cat "$TMP/err")"
lastno="$(grep "no receipt:" "$LOG" | tail -1)"
echo "fun ok() = 3" > src/Core.kt
stopx c-one; b2=$RC
if [ "$ga" = 0 ] && [ "$b1" = 2 ] && printf '%s' "$b1e" | grep -q "$REASON" && [ "$(nolines)" -gt "$n" ] \
   && printf '%s' "$lastno" | grep -q ": fp" && [ "$b2" = 0 ] && [ "$(spawns)" = 0 ]; then
  ok "M2: a receipt of an older tree: blocked, the log names the refusal (fp); back on that tree the receipt is accepted"
else
  fail "M2: gate=$ga rc=$b1/$b2 spawns=$(spawns) log='$lastno' err='$(printf '%s' "$b1e" | head -c 300)'"
fi

# M3: a branch that is not the trunk: no --diff in the command
git checkout -q -b issue-1
echo "fun ok() = 5" > src/Core.kt
stopx c-one
if [ "$RC" = 2 ] && grep -qF "\`python3 $GATE_REAL --run-tests --scoped --brief\`" "$TMP/err" && ! grep -q -- "--diff" "$TMP/err" && [ "$(spawns)" = 0 ]; then
  ok "M3: off the trunk branch the block names the command without --diff"
else
  fail "M3: rc=$RC spawns=$(spawns) err='$(head -c 400 "$TMP/err")'"
fi

# M4: commits after verified_head that the run did not check, off the trunk: the receipt of this tree is refused for its range
git add -A && git commit -qm "unchecked commit" && echo "fun ok() = 6" > src/Core.kt
gaterun --diff HEAD; gm=$GRC
stopx c-one
if [ "$gm" = 0 ] && [ "$RC" = 2 ] && grep -q "lượt gate bắt đầu sau verified_head" "$TMP/err" && grep -q ": covers base" "$LOG" && [ "$(spawns)" = 0 ]; then
  ok "M4: a receipt of this tree that started after verified_head: blocked, the block says the commits between were not checked"
else
  fail "M4: gate=$gm rc=$RC spawns=$(spawns) err='$(head -c 400 "$TMP/err")' gate='$(tail -2 "$TMP/gate.out")'"
fi

cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "regression gate repeat miss log: $FAILS FAILED"; exit 1; fi
echo "regression gate repeat miss log: all checks passed"
