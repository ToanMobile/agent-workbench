#!/usr/bin/env bash
# Regression test (ported to gate speed v26 mục 1, 07/11): the repeat behaviour of hooks/regression_gate.sh on one content.
# Before v26 the Stop hook RAN the gate and kept a per-session block cache (regression_gate.state.json "repeat": the stored block came back
# without running the suites; its key held the tree, the gitignored local config, the hook and gate files; a TTL; a read-merge-write
# across sessions). v26 removed that cache with the gate call: the Stop runs NO suite and starts no gate; it reads the receipt the agent's
# own gate run wrote for the tree (bin/tree_fp.py receipt_for_tree) and blocks one content at most MAX_ATTEMPTS (2) times. What this file
# keeps of the old contract, on the v26 mechanism:
#   C1 no receipt: the first two Stops of one content block naming the gate command, the third is released with a warning
#      (systemMessage, not a PASS); none of them starts the gate or a suite (the old hook ran the gate at the first Stop)
#   C2 the agent's gate run writes a receipt (exit 0): every later Stop of that content is allowed from it, the gate is not started again
#   C3 the content moves after the receipt (a tracked edit, then new bytes in an untracked file): blocked again, the old receipt is not reused
#   C4 the gate file changes after the receipt (the old key held the gate's size and mtime; the receipt holds its sha256): blocked again
# The kit under test is a COPY whose bin/post-fix-gate.py counts its own starts when GATE_SPAWNS names a file; only the hook's Stops set
# it (the agent's gate runs here do not), so any count means the Stop started the gate. bash 3.2 compatible;
# REPEATCACHE_KIT=<kit dir> tests another copy of the kit (a mutant, or the pre-v26 kit, must go red).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export WORKTREE_TRUNK_MODE=0   # K12 (18/10): các ca ở đây là phiên sửa thẳng main (không trunk mode); ở trunk mode Stop tại main không gate (test_regression_gate_trunk_main.sh)

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_KIT="${REPEATCACHE_KIT:-$DEVKIT_DIR}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID REGRESSION_GATE_MAX_ATTEMPTS DEVKIT_GATE_CACHE_MAX_S TEST_RUN_LOCK_WAIT_S
export FLAKY_RETRY=0 VACUITY_REVERT=0 DEVKIT_GATE_CACHE=0

# the kit under test, with a gate that counts the starts the hook makes
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
SPAWNS="$TMP/spawns"; : > "$SPAWNS"
RUNS="$TMP/runs"; : > "$RUNS"
spawns() { wc -c < "$SPAWNS" | tr -d ' '; }
runs() { wc -c < "$RUNS" | tr -d ' '; }

# A Claude Code transcript (not degraded).
printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"c-r"}' > "$TMP/claude.jsonl"
R="$TMP/repo"; mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
printf '.env\n.claude/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/regression_checklist.md\n' > .gitignore
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-R","name":"core","command":"printf x >> $RUNS"}]}]}
JSON
git add -A && git commit -qm init

# stopx <session>: one Stop of the kit copy's hook. Sets RC; stdout/stderr in $TMP/out, $TMP/err.
stopx() {
  printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$TMP/claude.jsonl" \
    | env GATE_SPAWNS="$SPAWNS" CLAUDE_PROJECT_DIR="$R" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"
  RC=$?
}
# gaterun: the agent's gate run, the command a block prints (--diff <verified_head> on this trunk branch once one is recorded)
gaterun() {
  local vh; vh="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verified_head") or "")' "$R/.claude/audit-gate/regression_gate.state.json" 2>/dev/null)"
  git cat-file -e "${vh:-none}^{commit}" 2>/dev/null || vh=""
  ( cd "$R" && CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --scoped --brief ${vh:+--diff "$vh"} ) >"$TMP/gate.out" 2>&1; GRC=$?
}

stopx s1   # clean tree: verified_head = the start point
CMD="post-fix-gate.py --run-tests --scoped --brief"

# C1: no receipt: block, block, release with a warning; the hook starts nothing
echo "fun ok() = 2" > src/Core.kt
stopx s1; r1=$RC; e1="$(cat "$TMP/err")"; stopx s1; r2=$RC; stopx s1; r3=$RC
if [ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$r3" = 0 ] && printf '%s' "$e1" | grep -q -- "$CMD" && grep -q "systemMessage" "$TMP/out" \
   && [ "$(spawns)" = 0 ] && [ "$(runs)" = 0 ]; then
  ok "C1: no receipt: two blocks naming the gate command, the third Stop released with a warning; the hook started no gate, no suite"
else
  fail "C1: rc=$r1/$r2/$r3 spawns=$(spawns) runs=$(runs) err1='$(printf '%s' "$e1" | head -c 300)' out='$(head -c 200 "$TMP/out")'"
fi

# C2: the agent's gate run writes the receipt: the Stops of that content are allowed from it, nothing is started again
#     (another content than C1, whose two blocks are used up: a release there would also exit 0)
echo "fun ok() = 22" > src/Core.kt
gaterun; n0=$(runs)
stopx s1; a1=$RC; stopx s1; a2=$RC; stopx s2; a3=$RC
if [ "$GRC" = 0 ] && [ "$n0" -ge 1 ] && [ "$a1" = 0 ] && [ "$a2" = 0 ] && [ "$a3" = 0 ] && [ ! -s "$TMP/err" ] && ! grep -q "CHƯA ĐẠT" "$TMP/out" \
   && [ "$(spawns)" = 0 ] && [ "$(runs)" = "$n0" ]; then
  ok "C2: a receipt of this content: three Stops (two sessions) allowed from it, the hook started no gate (runs stay $n0)"
else
  fail "C2: gate=$GRC rc=$a1/$a2/$a3 spawns=$(spawns) runs $n0 -> $(runs) err='$(head -c 300 "$TMP/err")' gate='$(tail -3 "$TMP/gate.out")'"
fi

# C3: the content moves: a tracked edit, then other bytes in an untracked file of the same name
echo "fun ok() = 3" > src/Core.kt
stopx s1; t1=$RC; t1e="$(cat "$TMP/err")"
gaterun; g3=$GRC; echo "scratch v1" > scratch.txt; gaterun; g4=$GRC
stopx s1; t2=$RC
echo "scratch v2 other bytes" > scratch.txt
stopx s1; t3=$RC; t3e="$(cat "$TMP/err")"
if [ "$t1" = 2 ] && printf '%s' "$t1e" | grep -q -- "$CMD" && [ "$g3" = 0 ] && [ "$g4" = 0 ] && [ "$t2" = 0 ] \
   && [ "$t3" = 2 ] && printf '%s' "$t3e" | grep -q -- "$CMD" && [ "$(spawns)" = 0 ]; then
  ok "C3: a tracked edit and new bytes in an untracked file each need a new receipt (blocked), the receipt of the old content is not reused"
else
  fail "C3: rc=$t1/$t2/$t3 gate=$g3/$g4 spawns=$(spawns) err='$(printf '%s' "$t3e" | head -c 300)'"
fi

# C4: the gate file changes between the receipt and the Stop: that receipt no longer counts. (Once a Stop allowed a content, the hook's
#     pass_fp lets the same content through without reading the receipt again; so the edit lands before the first Stop of a new content.)
echo "fun ok() = 4" > src/Core.kt
gaterun; g5=$GRC
echo "# edited" >> "$GATE"
stopx s1; u2=$RC; u2e="$(cat "$TMP/err")"
if [ "$g5" = 0 ] && [ "$u2" = 2 ] && printf '%s' "$u2e" | grep -q -- "$CMD" && [ "$(spawns)" = 0 ]; then
  ok "C4: the gate file changed after the receipt: the Stop blocks (the receipt holds the gate's sha256), still without starting it"
else
  fail "C4: gate=$g5 rc=$u2 spawns=$(spawns) err='$(printf '%s' "$u2e" | head -c 300)'"
fi
gaterun; stopx s1
[ "$GRC" = 0 ] && [ "$RC" = 0 ] && [ "$(spawns)" = 0 ] && ok "C4 control: a gate run by the edited gate writes a receipt the Stop accepts" \
  || fail "C4 control: gate=$GRC rc=$RC spawns=$(spawns) err='$(head -c 300 "$TMP/err")'"

cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "regression gate repeat cache: $FAILS FAILED"; exit 1; fi
echo "regression gate repeat cache: all passed"
