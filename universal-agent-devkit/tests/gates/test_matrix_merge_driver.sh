#!/usr/bin/env bash
# Regression (agent-workbench #221): two branches that each append a different rule to the tail of
# .agents/regression_matrix.active.json conflicted on the last lines, so the second PR to merge went CONFLICTING
# (PR #217 vs #219, 22/10). The union merge driver `scripts/git/matrix_merge_driver.py` joins them.
#   1. two branches append different rules: merge is clean, both rules present after the base rules, in merge order
#   2. the merged matrix is still append-only against the base: the gate's matrix_additions() trusts it
#   3. both branches append the SAME rule (same id, same content): kept once
#   4. both branches append the same test id with a different command: merge FAILS (exit != 0) naming the id, never merges silently
#   5. a non-additive edit (both branches change the same existing rule) falls back to the text merge, which conflicts
#   6. githooks.sh install registers the driver and .gitattributes routes the matrix file to it
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DRIVER="$DEVKIT_DIR/scripts/git/matrix_merge_driver.py"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
M=".agents/regression_matrix.active.json"
R=""

rule() { # $1 id $2 command
  printf '{"watch_files": ["x/%s"], "mandatory_regression_tests": [{"id": "%s", "name": "n", "command": "%s"}]}' "$1" "$1" "$2"
}
write_matrix() { # $@ = rule JSON objects
  python3 - "$@" <<'PY'
import json, sys
m = {"version": 1, "project": "t", "rules": [json.loads(a) for a in sys.argv[1:]]}
open(".agents/regression_matrix.active.json", "w", encoding="utf-8").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
}
make_repo() { # a fresh repo per case; the trap removes them all
  R="$(mktemp -d "$TMP/repo.XXXXXX")" && mkdir -p "$R/.agents" && cd "$R" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  echo "$M merge=devkit-matrix" > .gitattributes
  git config merge.devkit-matrix.driver "python3 $DRIVER %O %A %B %P"
  write_matrix "$(rule BASE-1 true)"
  git add -A && git commit -qm base
}
branch_add() { # $1 branch, rest = rules appended to the base rules
  local b="$1"; shift
  git checkout -q -b "$b" main
  write_matrix "$(rule BASE-1 true)" "$@"
  git commit -qam "$b"
}
ids() { python3 -c 'import json;print(" ".join(t["id"] for r in json.load(open(".agents/regression_matrix.active.json"))["rules"] for t in r["mandatory_regression_tests"]))'; }

# 1 + 2
make_repo
branch_add a "$(rule A-1 true)"; branch_add b "$(rule B-1 true)"
git checkout -q a
if git merge --no-edit b >/dev/null 2>&1; then ok "1: two different appended rules merge clean"; else bad "1: merge conflicted"; fi
[ "$(ids)" = "BASE-1 A-1 B-1" ] && ok "1: both rules present, base first" || bad "1: ids are '$(ids)'"
python3 - "$GATE" "$R" <<'PY' && ok "2: gate trusts the merged matrix as append-only" || bad "2: matrix_additions rejected the merge"
import importlib.util, json, subprocess, sys
spec = importlib.util.spec_from_file_location("g", sys.argv[1]); g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
base = json.loads(subprocess.check_output(["git", "-C", sys.argv[2], "show", "main:.agents/regression_matrix.active.json"]))
cur = json.load(open(sys.argv[2] + "/.agents/regression_matrix.active.json"))
sys.exit(0 if g.matrix_additions(base, cur) == ["A-1", "B-1"] else 1)
PY

# 3
make_repo
branch_add a "$(rule S-1 true)"; branch_add b "$(rule S-1 true)"
git checkout -q a
git merge --no-edit b >/dev/null 2>&1 && [ "$(ids)" = "BASE-1 S-1" ] && ok "3: identical rule on both sides kept once" || bad "3: '$(ids)'"

# 4
make_repo
branch_add a "$(rule D-1 'echo a')"; branch_add b "$(rule D-1 'echo b')"
git checkout -q a
OUT="$(git merge --no-edit b 2>&1)"; RC=$?
[ $RC -ne 0 ] && echo "$OUT" | grep -q "D-1" && ok "4: same id, different command fails and names the id" || bad "4: rc=$RC out=$OUT"
git merge --abort >/dev/null 2>&1

# 5
make_repo
git checkout -q -b a main && sed -i.bak 's/"command": "true"/"command": "echo a"/' "$M" && rm -f "$M.bak" && git commit -qam a
git checkout -q -b b main && sed -i.bak 's/"command": "true"/"command": "echo b"/' "$M" && rm -f "$M.bak" && git commit -qam b
git checkout -q a
git merge --no-edit b >/dev/null 2>&1 && bad "5: overlapping edit of an existing rule merged silently" || ok "5: non-additive overlap still conflicts"
git merge --abort >/dev/null 2>&1

# 6
H="$(mktemp -d "$TMP/hooks.XXXXXX")" && cd "$H" && git init -q . && git config user.email t@t && git config user.name t
bash "$DEVKIT_DIR/scripts/git/githooks.sh" install "$H" >/dev/null 2>&1
git config --get merge.devkit-matrix.driver | grep -q matrix_merge_driver.py && grep -q "regression_matrix.active.json merge=devkit-matrix" .gitattributes \
  && ok "6: githooks install registers the driver and the attribute" || bad "6: driver/attribute missing"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
