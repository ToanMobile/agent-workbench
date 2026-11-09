#!/usr/bin/env bash
# Regression test (ported to gate speed v26 mục 1, 07/11): a STALE suite is never taken as a pass by the Stop hook.
# bin/post-fix-gate.py marks a re-used PASS whose source file a concurrent run replaced or deleted as UNTESTED with the label STALE
# (tests/gates/test_gate_stop_reuse_race.sh): such a run ends exit 4, writes no receipt exit 0 and (lane D2) writes NO outcome and drops
# the tree's old one, so the Stop has to ask for a real run. Before v26 the hook ran the gate itself and worded a STALE suite in its
# block / BUSY message (a fake gate printed the summary). v26: the Stop runs NO suite and starts no gate; it reads the receipt
# (bin/tree_fp.py receipt_for_tree: exit 0 only) and the outcome of the tree (<git dir>/postfix-gate/outcomes/<fp>.json, five known
# reasons only). What this file keeps, on the v26 mechanism:
#   S1 a receipt of this tree that holds a STALE suite (exit 4, REG-R UNTESTED/STALE) is refused: the Stop blocks with the gate command;
#      control: the receipt of a real exit-0 run of the same tree is accepted
#   S2 an outcome for this tree whose reason is not one the gate writes for a no-receipt verdict ("stale") is ignored: blocked with the
#      gate command, its lines are not said and it is not worded as "cannot run on this machine"
#   S3 control: an outcome "device_untested" whose base covers the range IS said once (UNTESTED, cannot run here, not a PASS) and allowed
# The kit under test is a COPY whose bin/post-fix-gate.py counts its starts when GATE_SPAWNS names a file (only the hook's Stops set it).
# bash 3.2 compatible; STALELABEL_KIT=<kit dir> tests another copy of the kit (a mutant, or the pre-v26 kit, must go red).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export WORKTREE_TRUNK_MODE=0   # K12 (18/10): các ca ở đây là phiên sửa thẳng main (không trunk mode); ở trunk mode Stop tại main không gate (test_regression_gate_trunk_main.sh)
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_KIT="${STALELABEL_KIT:-$DEVKIT_DIR}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID REGRESSION_GATE_MAX_ATTEMPTS DEVKIT_GATE_CACHE_MAX_S TEST_RUN_LOCK_WAIT_S \
      REGRESSION_GATE_REPEAT_TTL_S REGRESSION_GATE_TOUCHED_RECHECK_S
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
SPAWNS="$TMP/spawns"; : > "$SPAWNS"
spawns() { wc -c < "$SPAWNS" | tr -d ' '; }

printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"c-r"}' > "$TMP/claude.jsonl"
R="$TMP/repo"; mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
printf '.claude/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/regression_checklist.md\n' > .gitignore
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-R","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
STATE="$R/.claude/audit-gate/regression_gate.state.json"
stopx() { # $1 = session id
  printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$TMP/claude.jsonl" \
    | env GATE_SPAWNS="$SPAWNS" CLAUDE_PROJECT_DIR="$R" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"
  RC=$?
}
gaterun() {
  local vh; vh="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verified_head") or "")' "$STATE" 2>/dev/null)"
  git cat-file -e "${vh:-none}^{commit}" 2>/dev/null || vh=""
  ( cd "$R" && CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --scoped --brief ${vh:+--diff "$vh"} ) >"$TMP/gate.out" 2>&1; GRC=$?
}
# stale_receipts: every receipt of the current tree turned into what a STALE run ends with (exit 4, REG-R UNTESTED / STALE). Prints the count.
stale_receipts() { python3 -I -c 'import json,os,sys
sys.path.insert(0, sys.argv[2]); import tree_fp
fp = tree_fp.tree_fingerprint(sys.argv[1]); top = os.path.join(sys.argv[1], ".git", "postfix-gate"); n = 0
for d, _, fs in os.walk(top):
    if os.path.basename(d) == "outcomes":
        continue
    for f in fs:
        p = os.path.join(d, f)
        try:
            r = json.load(open(p))
        except Exception:
            continue
        if isinstance(r, dict) and fp in (r.get("fingerprint"), r.get("fp")) and r.get("exit") == 0:
            r["exit"] = 4
            r["tests"] = [{"id": "REG-R", "name": "core", "status": "UNTESTED", "label": "STALE"}]
            json.dump(r, open(p, "w")); n += 1
print(n)' "$R" "$KIT/bin"; }
# outcome <reason> <base sha>: the outcome file of the current tree, as post-fix-gate write_gate_outcome lays it out
outcome() { python3 -I -c 'import json,os,sys,time
sys.path.insert(0, sys.argv[2]); import tree_fp
fp = tree_fp.tree_fingerprint(sys.argv[1]); d = os.path.join(os.path.dirname(tree_fp.receipt_path(sys.argv[1])), "outcomes")
os.makedirs(d, exist_ok=True)
json.dump({"exit": 4, "reason": sys.argv[3], "lines": ["fake verdict REG-R " + sys.argv[3]], "base": sys.argv[4], "at": time.time()},
          open(os.path.join(d, fp + ".json"), "w"))' "$R" "$KIT/bin" "$1" "$2"; }
CMD="post-fix-gate.py --run-tests --scoped --brief"
NOTHERE="không chạy được trên máy này"

stopx s1   # clean tree: verified_head = the start point

# S1
echo "fun ok() = 2" > src/Core.kt
gaterun; g1=$GRC; nst="$(stale_receipts)"
stopx s1; r1=$RC; e1="$(cat "$TMP/err")"
gaterun; g2=$GRC; stopx s1; r2=$RC
if [ "$g1" = 0 ] && [ "${nst:-0}" -ge 1 ] && [ "$r1" = 2 ] && printf '%s' "$e1" | grep -q -- "$CMD" && [ "$g2" = 0 ] && [ "$r2" = 0 ] && [ "$(spawns)" = 0 ]; then
  ok "S1: a receipt of this tree holding a STALE suite (exit 4) is refused: blocked with the gate command; the real exit-0 receipt is accepted"
else
  fail "S1: gate=$g1/$g2 stale_receipts=$nst rc=$r1/$r2 spawns=$(spawns) err='$(printf '%s' "$e1" | head -c 300)'"
fi

# S2
echo "fun ok() = 3" > src/Core.kt
outcome stale "$(git rev-parse HEAD)"
stopx s1
if [ "$RC" = 2 ] && grep -q -- "$CMD" "$TMP/err" && ! grep -q "fake verdict" "$TMP/err" "$TMP/out" && ! grep -q "$NOTHERE" "$TMP/err" "$TMP/out" \
   && [ "$(spawns)" = 0 ]; then
  ok "S2: an outcome 'stale' (a reason the gate never writes for a no-receipt verdict) is ignored: blocked with the gate command, its lines not said"
else
  fail "S2: rc=$RC spawns=$(spawns) out='$(head -c 300 "$TMP/out")' err='$(head -c 300 "$TMP/err")'"
fi

# S3 control
echo "fun ok() = 4" > src/Core.kt
outcome device_untested "$(git rev-parse HEAD)"
stopx s1
if [ "$RC" = 0 ] && grep -q "$NOTHERE" "$TMP/out" && grep -q "fake verdict REG-R device_untested" "$TMP/out" && [ ! -s "$TMP/err" ] && [ "$(spawns)" = 0 ]; then
  ok "S3 control: an outcome device_untested covering the range is said (UNTESTED, cannot run here) and the Stop allowed"
else
  fail "S3 control: rc=$RC spawns=$(spawns) out='$(head -c 300 "$TMP/out")' err='$(head -c 300 "$TMP/err")'"
fi

cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "regression gate stale label: $FAILS FAILED"; exit 1; fi
echo "regression gate stale label: all checks passed"
