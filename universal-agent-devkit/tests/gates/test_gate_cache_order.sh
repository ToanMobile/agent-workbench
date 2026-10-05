#!/usr/bin/env bash
# Regression test: bin/post-fix-gate.py cached_full_pass tests the CHEAP half of its reuse key (the tree fingerprint,
# 0.25 s) before the expensive one (local_state_sha, 0.7-6.4 s on the app repos), and returns exactly what it returned
# before for every input. Both are ANDed, so a changed tree makes the local-state hash useless: it is not computed.
# 2026-10-05 (DevKit speed, Wave 1): every gate on an edited tree paid 3.8-6.4 s (GeelyEx2, OfficeReader) for a value the
# reuse decision could never use.
# 1. truth table: old cached_full_pass (reference copy below) vs the real one, byte-identical returns for every
#    combination of {tree equal / changed / unavailable} x {local state equal / changed / unlistable} x {12 receipt shapes}
# 2. calls: an edited tree computes local_state_sha 0 times; an equal tree computes it once
# 3. end to end, real git repo: edited tree -> suite re-runs; equal tree + changed .env -> suite re-runs; nothing
#    changed -> the PASS is reused
# 4. mutations of a copy of the gate: old order, local check dropped, fingerprint check dropped: each one turns this red
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/kit"
cp -R "$DEVKIT_DIR/bin" "$DEVKIT_DIR/scripts" "$DEVKIT_DIR/profiles" "$TMP/kit/"
GATE="$TMP/kit/bin/post-fix-gate.py"

mkdir -p "$TMP/repo/src" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo run >> runs.txt"}]}]}
JSON
printf 'runs.txt\n.env\n' > .gitignore
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
echo "KEY=1" > .env

# The driver: imports a gate by path, stubs the two expensive calls with counters, and checks truth table + call counts.
cat > "$TMP/driver.py" <<'PY'
import importlib.util, json, os, sys, time
gate, repo, matrix = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("pfg_under_test", gate)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
sys.path.insert(0, os.path.dirname(gate))
import tree_fp

# Reference: cached_full_pass exactly as it was before the reorder (dadd7be), bound to the module under test.
OLD = '''
def old_cached_full_pass(project_dir, matrix_arg):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import tree_fp  # noqa: PLC0415 - sibling module in bin/
        path = tree_fp.receipt_path(project_dir)
        with open(path, encoding="utf-8") as f:
            r = json.load(f)
        max_s = float(os.environ.get("DEVKIT_GATE_CACHE_MAX_S", "21600"))
    except (ImportError, OSError, ValueError, TypeError):
        return None
    if not isinstance(r, dict) or not r.get("tests"):
        return None
    if r.get("exit") != 0 and not (r.get("exit") == 4 and r.get("untested") and isinstance(r["untested"], list)):
        return None
    if time.time() - float(r.get("tested_at") or 0) > max_s:
        return None
    if r.get("result_format") != RESULT_FORMAT or r.get("matrix_sha") != _sha_file(find_matrix_path(matrix_arg)):
        return None
    if r.get("local_sha") in (None, "?") or r.get("local_sha") != local_state_sha(project_dir):
        return None
    fp = tree_fp.tree_fingerprint(project_dir)
    return r if fp and r.get("fingerprint") == fp else None
'''
mod.__dict__["__file__"] = gate
exec(compile(OLD, "old_cached_full_pass", "exec"), mod.__dict__)

calls = {"local": 0, "tree": 0}
state = {"local": "L1", "tree": "FP"}
def fake_local(project_dir):
    calls["local"] += 1
    return state["local"]
def fake_tree(project_dir):
    calls["tree"] += 1
    return state["tree"]
mod.local_state_sha = fake_local
tree_fp.tree_fingerprint = fake_tree

path = tree_fp.receipt_path(repo)
os.makedirs(os.path.dirname(path), exist_ok=True)
msha = mod._sha_file(mod.find_matrix_path(matrix))
now = time.time()
good = {"exit": 0, "tested_at": now, "result_format": mod.RESULT_FORMAT, "matrix_sha": msha, "local_sha": "L1",
        "fingerprint": "FP", "tests": [{"id": "REG-1", "status": "PASS"}]}
def v(**kw):
    d = dict(good); d.update(kw); return d
receipts = {
    "good": good,
    "missing": None,
    "not-json": "{nope",
    "not-a-dict": [1, 2],
    "no-tests": v(tests=[]),
    "exit-1": v(exit=1),
    "exit-4-untested": v(exit=4, untested=["REG-2"]),
    "exit-4-no-untested": v(exit=4),
    "too-old": v(tested_at=now - 10 ** 6),
    "other-matrix": v(matrix_sha="0" * 64),
    "other-format": v(result_format=mod.RESULT_FORMAT + 1),
    "no-format": {k: x for k, x in good.items() if k != "result_format"},
    "local-none": v(local_sha=None),
    "local-qmark": v(local_sha="?"),
    "other-fingerprint": v(fingerprint="FP-OTHER"),
}
trees = {"equal": "FP", "changed": "FP2", "unavailable": ""}
locals_ = {"equal": "L1", "changed": "L2", "unlistable": "?"}

def write(rec):
    if rec is None:
        try: os.remove(path)
        except OSError: pass
    elif isinstance(rec, str):
        open(path, "w").write(rec)
    else:
        json.dump(rec, open(path, "w"))

bad = 0; n = 0
for rname, rec in receipts.items():
    write(rec)
    for tname, tv in trees.items():
        for lname, lv in locals_.items():
            state["tree"], state["local"] = tv, lv
            old = mod.old_cached_full_pass(repo, matrix)
            new = mod.cached_full_pass(repo, matrix)
            n += 1
            if json.dumps(old, sort_keys=True) != json.dumps(new, sort_keys=True):
                bad += 1
                print("DIFF receipt=%s tree=%s local=%s old=%r new=%r" % (rname, tname, lname, old, new))
print("TABLE %d combinations, %d different" % (n, bad))
# reuse really happens in exactly one corner of the table
write(good)
state["tree"], state["local"] = "FP", "L1"
print("REUSE-OK" if mod.cached_full_pass(repo, matrix) == good else "REUSE-LOST")
for tname, tv, want in (("changed", "FP2", 0), ("unavailable", "", 0), ("equal", "FP", 1)):
    state["tree"], state["local"] = tv, "L1"
    calls["local"] = 0
    mod.cached_full_pass(repo, matrix)
    print("CALLS tree=%s local_state_sha=%d want=%d %s" % (tname, calls["local"], want, "ok" if calls["local"] == want else "BAD"))
# receipts that fail a cheap check never reach either expensive call, with any tree
for rname in ("missing", "exit-1", "too-old", "other-matrix", "other-format", "local-none", "local-qmark"):
    write(receipts[rname]); state["tree"], state["local"] = "FP", "L1"
    calls["local"] = calls["tree"] = 0
    mod.cached_full_pass(repo, matrix)
    print("CHEAP %s local=%d tree=%d" % (rname, calls["local"], calls["tree"]))
PY

run_driver() { # <gate> -> driver output
  CLAUDE_PROJECT_DIR="$TMP/repo" python3 -I "$TMP/driver.py" "$1" "$TMP/repo" "$TMP/repo/matrix.json" 2>&1
}
analyse() { # <driver output> <label>: fails counted when the label is "real"
  local out="$1" bad=0
  printf '%s\n' "$out" | grep -q '^TABLE .* 0 different$' || bad=$((bad + 1))
  printf '%s\n' "$out" | grep -q '^REUSE-OK$' || bad=$((bad + 1))
  printf '%s\n' "$out" | grep '^CALLS ' | grep -q BAD && bad=$((bad + 1))
  [ "$(printf '%s\n' "$out" | grep -c '^CALLS ')" = 3 ] || bad=$((bad + 1))
  # a receipt that fails a cheap check computes nothing expensive (the tree check only follows the cheap ones)
  printf '%s\n' "$out" | grep '^CHEAP ' | grep -qv 'local=0 tree=0$' && bad=$((bad + 1))
  echo "$bad"
}

out="$(run_driver "$GATE")"
echo "$out" | grep -E '^(TABLE|REUSE|CALLS|DIFF|Traceback)' | head -20
printf '%s\n' "$out" | grep -q '^TABLE .* 0 different$' && ok "truth table: old and new return the same for every combination" || fail "truth table differs (or the driver crashed): $(printf '%s\n' "$out" | tail -5)"
printf '%s\n' "$out" | grep -q '^REUSE-OK$' && ok "a good receipt, equal tree, equal local state is reused" || fail "the reuse corner is lost"
printf '%s\n' "$out" | grep -q '^CALLS tree=changed local_state_sha=0 ' && ok "edited tree: local_state_sha is not computed" \
  || fail "edited tree still computes local_state_sha ($(printf '%s\n' "$out" | grep '^CALLS tree=changed'))"
printf '%s\n' "$out" | grep -q '^CALLS tree=unavailable local_state_sha=0 ' && ok "no fingerprint: local_state_sha is not computed" || fail "no fingerprint still computes local_state_sha"
printf '%s\n' "$out" | grep -q '^CALLS tree=equal local_state_sha=1 ' && ok "equal tree: local_state_sha is computed exactly once" || fail "equal tree: local_state_sha not computed once"
[ "$(printf '%s\n' "$out" | grep '^CHEAP ' | grep -c 'local=0 tree=0$')" = 7 ] && ok "a receipt that fails a cheap check computes neither expensive value" \
  || fail "a failed cheap check still computed something: $(printf '%s\n' "$out" | grep '^CHEAP ')"

# 3. End to end with the real fingerprint and the real local-state hash.
runs() { [ -f runs.txt ] && wc -l < runs.txt | tr -d ' ' || echo 0; }
run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --full "$@" 2>&1; }
run_gate >/dev/null; rc=$?
[ "$rc" = 0 ] && [ "$(runs)" = 1 ] && ok "e2e setup: first full run PASS, suite ran once" || fail "e2e setup failed (exit $rc, runs $(runs))"
run_gate >/dev/null
[ "$(runs)" = 1 ] && ok "e2e: nothing changed -> the PASS is reused" || fail "e2e: nothing changed but the suite re-ran (runs $(runs))"
echo "KEY=2" > .env
run_gate >/dev/null
[ "$(runs)" = 2 ] && ok "e2e: equal tree, changed .env -> not reused (local state is still part of the key)" || fail "e2e: a changed .env reused the PASS (runs $(runs))"
echo "fun ok() = 3" > src/Core.kt
run_gate >/dev/null
[ "$(runs)" = 3 ] && ok "e2e: edited tree -> not reused" || fail "e2e: an edited tree reused the PASS (runs $(runs))"

# 4. Mutations of a copy of the gate: each must turn the driver red.
mutate() { # <name> <python replace expression on s> ; writes $TMP/kit/bin/post-fix-gate.py from the pristine copy
  cp "$DEVKIT_DIR/bin/post-fix-gate.py" "$TMP/kit/bin/mutant.py"
  python3 -I - "$TMP/kit/bin/mutant.py" "$1" <<'PY'
import re, sys
p, kind = sys.argv[1:3]
s = open(p, encoding="utf-8").read()
a = s.index("def cached_full_pass(")
b = s.index("\n\n\n", a)
body = s[a:b]
if kind == "old-order":     # the dadd7be order: local state first, then the fingerprint
    new = body[:body.index('    if r.get("local_sha") in (None, "?")')] + (
        '    if r.get("local_sha") in (None, "?") or r.get("local_sha") != local_state_sha(project_dir):\n'
        '        return None\n'
        '    fp = tree_fp.tree_fingerprint(project_dir)\n'
        '    return r if fp and r.get("fingerprint") == fp else None')
elif kind == "no-local":    # the local-state comparison dropped
    new = re.sub(r'(?s)(    if r\.get\("local_sha"\) in \(None, "\?"\)).*', r'\1:\n        return None\n    fp = tree_fp.tree_fingerprint(project_dir)\n    return r if fp and r.get("fingerprint") == fp else None', body)
elif kind == "no-fp":       # the fingerprint comparison dropped
    new = re.sub(r'(?s)(    if r\.get\("local_sha"\) in \(None, "\?"\)).*', r'\1:\n        return None\n    return r if r.get("local_sha") == local_state_sha(project_dir) else None', body)
else:
    sys.exit(2)
if new == body:
    sys.exit(3)
open(p, "w", encoding="utf-8").write(s[:a] + new + s[b:])
PY
}
for m in old-order no-local no-fp; do
  if mutate "$m"; then
    mout="$(run_driver "$TMP/kit/bin/mutant.py")"
    if [ "$(analyse "$mout")" != 0 ]; then ok "mutation '$m' turns the driver red"; else fail "mutation '$m' went unnoticed"; fi
  else
    fail "mutation '$m' could not be applied (cached_full_pass text moved?)"
  fi
done

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_cache_order: all passed" || { echo "❌ test_gate_cache_order: $FAILS failed"; exit 1; }
