#!/usr/bin/env bash
# #862 (#1054): the no-gate automerge (Stop hook) checked the receipt for the HEAD it read FIRST; if the worktree HEAD changed before
# the fast-forward (a commit landing between the check and the loop) the loop fast-forwarded main with a commit that has NO receipt.
# It must answer needs_gate instead, leaving main untouched.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK DEVKIT_SESSION_ID \
      CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_SLOT_PRIORITY CLAUDE_PROJECT_DIR DEVKIT_GATE_CACHE_MAX_S
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export GIT_CONFIG_GLOBAL=/dev/null
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export GATE_COUNT="$TMP/count"

repo() {   # repo <name> [nomatrix]
  local p="$TMP/$1"; mkdir -p "$p/.agents" && G "$p" init -q -b main . && G "$p" config user.email t@t && G "$p" config user.name t
  printf 'greet() { echo ok; }\n' > "$p/lib.sh"
  printf '. ./lib.sh\ngreet\n' > "$p/app.sh"
  printf 'echo run >> "$GATE_COUNT"\nfor f in app*.sh; do [ "$(bash "$f" 2>/dev/null)" = ok ] || { echo "FAIL $f"; exit 1; }; done\necho ok\n' > "$p/check.sh"
  echo '{"profile":"backend"}' > "$p/.agents/active-profile.json"
  [ "${2:-}" = nomatrix ] || printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"apps","command":"bash check.sh"}]}]}\n' \
    > "$p/.agents/regression_matrix.active.json"
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/regression_checklist.md\n.agents/evidence/\n.agents/regression_journal/\n.claude/\n' > "$p/.gitignore"
  G "$p" add -A && G "$p" commit -qm base
}
wtadd() { (cd "$TMP/$1" && python3 "$WT" add "$TMP/$1-w" --no-init >/dev/null 2>&1) || fail "setup: worktree add $1-w"; }
work() { printf '. ./lib.sh\ngreet\n' > "$TMP/$1-w/app2.sh" && G "$TMP/$1-w" add app2.sh && G "$TMP/$1-w" commit -qm "app2"; }
am() { (cd "$TMP/$1" && python3 "$WT" automerge "$TMP/$1-w" --keep > "$TMP/out" 2>&1); AM=$?; }
st() { python3 -c 'import json,sys; print(json.loads([l for l in open(sys.argv[1]) if l.startswith("{")][-1]).get("status"))' "$TMP/out" 2>/dev/null; }
runs() { [ -f "$GATE_COUNT" ] && wc -l < "$GATE_COUNT" | tr -d ' ' || echo 0; }


repo a; wtadd a; work a
( cd "$TMP/a-w" && python3 "$GATE" --run-tests --scoped --brief ) > "$TMP/gout" 2>&1 || { fail "setup: gate rc"; tail -5 "$TMP/gout"; }
M0="$(G "$TMP/a" rev-parse HEAD)"
python3 - "$WT" "$TMP/a" "$TMP/a-w" > "$TMP/out" 2>&1 <<'PY'
import importlib.util, subprocess, sys
spec = importlib.util.spec_from_file_location("wtmod", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
main, wt = sys.argv[2], sys.argv[3]
orig = m._commit_pending
def sneaky(w, state):   # a commit lands between the receipt check and the merge loop
    open(wt + "/late.sh", "w").write("echo late\n")
    subprocess.run(["git", "-C", wt, "add", "late.sh"], check=True)
    subprocess.run(["git", "-C", wt, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "late"], check=True)
    return orig(w, state)
m._commit_pending = sneaky
r = m.automerge(main, wt, keep=True, run_gate=False)
print("RESULT", r)
PY
[ "$(G "$TMP/a" rev-parse HEAD)" = "$M0" ] && grep -q "needs_gate" "$TMP/out" \
  && ok "HEAD changed after the receipt check: needs_gate, main not moved" \
  || fail "main moved or no needs_gate: $(tail -5 "$TMP/out")"
[ "$FAILS" = 0 ]
