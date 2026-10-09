#!/usr/bin/env bash
# Regression test: bin/post-fix-gate.py's cost must not grow with one process (or one full read) per file (audit 2026-10-09).
#  A12 one git process per changed file: 600 changed files cost ~1235 git calls (~601 `git show <ref>:<path>`, ~400
#      `git cat-file -e`, ~202 `git diff -U0`), ~4 s of fork/exec. The per-file kinds must not grow with the file count,
#      in the working-tree audit and in --staged (pre-commit) alike, and the verdicts must stay the same.
#  A13 tree_fingerprint (`git add -A` into a temp index + `git write-tree`) ran 3 times per --full run that finds a
#      receipt; the value taken before the suites is reused where nothing ran in between: 2.
#  A14 check_anti_false_green read and sha256-hashed every proof image on every run (warnings only).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REALGIT="$(command -v git)"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TMP/git.log"
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/bin/git"

# N source files and N/2 existing tests, all changed; one test also has a CHANGED line (an edit), one new test file.
N=40
mk() {
  local d="$TMP/$1" i=0
  mkdir -p "$d/src" "$d/tests" && cd "$d" || exit 1
  git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  while [ $i -lt $N ]; do printf 'def f%d():\n    return %d\n' $i $i > src/mod_$i.py; i=$((i + 1)); done
  i=0
  while [ $i -lt $((N / 2)) ]; do
    printf 'from src.mod_%d import f%d\n\n\ndef test_f%d():\n    assert f%d() == %d\n' $i $i $i $i $i > tests/test_mod_$i.py
    i=$((i + 1))
  done
  printf 'KEY = "AKIA%s"\n' ABCDEFGHIJKLMNOP > src/legacy.py      # already in HEAD: a warning, never a block
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
  git add -A && git commit -qm init
  i=0; while [ $i -lt $N ]; do printf 'def g%d():\n    return %d\n' $i $i >> src/mod_$i.py; i=$((i + 1)); done
  i=1
  while [ $i -lt $((N / 2)) ]; do
    printf '\n\ndef test_g%d():\n    assert f%d() + 1 == %d\n' $i $i $((i + 1)) >> tests/test_mod_$i.py; i=$((i + 1))
  done
  printf 'from src.mod_0 import f0\n\n\ndef test_f0():\n    assert f0() == 0 or True\n' > tests/test_mod_0.py   # an edit
  printf 'from src.mod_1 import f1\n\n\ndef test_new():\n    assert f1() == 1\n' > tests/test_new.py
  printf 'KEY = "AKIA%s"\nX = 1\n' ABCDEFGHIJKLMNOP > src/legacy.py
}
gate() {
  : > "$TMP/git.log"
  OUT="$(PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$PWD" POSTFIX_GATE_FORCE_FULL=1 python3 "$GATE" --matrix "$PWD/matrix.json" \
         --lang en --json "$@" 2>&1)"; RC=$?
  JSON="$(printf '%s\n' "$OUT" | grep '^{' | tail -1)"
}
j() { printf '%s' "$JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1" 2>/dev/null; }
# per-file git calls: git show <ref>:<path>, cat-file -e / -s / blob, diff -U0, check-attr
per_file() { grep -cE '^-C [^ ]+ (show [^ ]*:|cat-file (-e|-s|blob) |diff -U0|check-attr )' "$TMP/git.log"; }

# ── A12: the working-tree audit ─────────────────────────────────────────────────────────────────────────────
mk wt
gate --run-tests --full
n="$(per_file)"; total="$(wc -l < "$TMP/git.log" | tr -d ' ')"
[ "$n" -le 6 ] && ok "A12: $((N * 3 / 2 + 2)) changed files cost $n per-file git calls ($total git calls in all)" \
  || bad "A12: $((N * 3 / 2 + 2)) changed files cost $n per-file git calls ($total in all): one per file"
[ "$RC" = 2 ] && ok "A12: verdict unchanged: UNVERIFIED for the one edited existing test (exit 2)" || bad "A12: exit $RC, want 2"
[ "$(j 'd["tests_touched"]')" = "['tests/test_mod_0.py']" ] && ok "A12: only tests/test_mod_0.py is an edited test (appends are not)" \
  || bad "A12: tests_touched $(j 'd["tests_touched"]'), want ['tests/test_mod_0.py']"
[ "$(j 'd["static"]["secrets"]')" = 0 ] && ok "A12: the key already in HEAD is not a new finding" || bad "A12: secrets $(j 'd["static"]')"
printf '%s\n' "$OUT" | grep -q "src/legacy.py:1: AWS Access Key ID — already in HEAD" && ok "A12: ... and is still warned about" \
  || bad "A12: the pre-existing key warning is gone"

# ── A12: --staged (pre-commit) ───────────────────────────────────────────────────────────────────────────────
git add -A
gate --staged
n="$(per_file)"
[ "$n" -le 6 ] && ok "A12: --staged on $((N * 3 / 2 + 2)) staged files costs $n per-file git calls" \
  || bad "A12: --staged on $((N * 3 / 2 + 2)) staged files costs $n per-file git calls: one per file"
[ "$RC" = 2 ] && [ "$(j 'd["static_ok"]')" = True ] && ok "A12: --staged verdict unchanged (static clean, exit 2)" \
  || bad "A12: --staged exit $RC static_ok $(j 'd["static_ok"]')"
printf 'TOKEN = "AKIA%s"\n' QRSTUVWXYZABCDEF >> src/mod_3.py && git add src/mod_3.py
gate --staged
[ "$RC" = 1 ] && ok "A12: --staged still REJECTs a new key in one of many files" || bad "A12: --staged exit $RC with a new key, want 1"

# ── A13: tree_fingerprint is taken twice per --full run that finds a receipt, not three times ────────────────────
mk fp
git checkout -q -- tests/test_mod_0.py && rm -f tests/test_new.py src/legacy.py && git checkout -q -- src/legacy.py
gate --run-tests --full
[ "$RC" = 0 ] && [ -f .git/postfix-gate/full_pass.json ] && ok "A13: first --full run PASS with a receipt" || bad "A13: first run exit $RC"
printf '# more\n' >> src/mod_5.py
gate --run-tests --full
w="$(grep -c 'write-tree' "$TMP/git.log")"
[ "$RC" = 0 ] && [ "$w" -le 2 ] && ok "A13: a --full run that finds an older receipt fingerprints the tree $w times" \
  || bad "A13: exit $RC, the tree was fingerprinted $w times (want <= 2)"
gate --run-tests --full
[ "$RC" = 0 ] && [ "$(j 'd["regression_tests"][0].get("mode")')" = cached ] && ok "A13: the next run on the same content reuses the receipt" \
  || bad "A13: no reuse on unchanged content (exit $RC, mode $(j 'd["regression_tests"][0].get("mode")'))"

# ── A14: an unchanged proof image is not read and hashed again on the next run ────────────────────────────────────
mk proofs
mkdir -p reports
i=0
while [ $i -lt 30 ]; do
  python3 -c 'import os,sys; open(sys.argv[1],"wb").write(b"\x89PNG\r\n\x1a\n" + os.urandom(20000))' "reports/proof-$i.png"
  i=$((i + 1))
done
touch -t 202001010000 reports/*.png     # older than POSTFIX_PROOF_SINCE: references only, never judged by run_proof_block
res="$(CLAUDE_PROJECT_DIR="$PWD" python3 - "$GATE" <<'EOF' 2>&1
import hashlib, importlib.util, shutil, sys, os
spec = importlib.util.spec_from_file_location("gate", sys.argv[1])
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
hashed = []
class Counting:
    def __getattr__(self, name):
        return getattr(hashlib, name)
    def sha256(self, data=b"", *a, **k):
        if len(data) > 1000:
            hashed.append(len(data))
        return hashlib.sha256(data, *a, **k)
g.hashlib = Counting()
r1 = g.check_anti_false_green()
n1 = len(hashed); hashed.clear()
r2 = g.check_anti_false_green()
n2 = len(hashed); hashed.clear()
shutil.copyfile("reports/proof-1.png", "reports/proof-copy.png")
r3 = g.check_anti_false_green()
n3 = len(hashed); hashed.clear()
data = open("reports/proof-2.png", "rb").read()
open("reports/proof-2.png", "wb").write(open("reports/proof-3.png", "rb").read())   # same size, new content
os.utime("reports/proof-2.png", (1700000000, 1700000000))
r4 = g.check_anti_false_green()
n4 = len(hashed)
import re
dups = lambda r: next((re.search(r"\d+", f).group(0) for f in r[1] if "SHA-256" in f), "0")   # "<n> proof images with identical SHA-256"
print("RUN", n1, n2, n3, n4, r1[2], r2[2], dups(r1), dups(r3), dups(r4))
EOF
)"
set -- $(printf '%s\n' "$res" | grep '^RUN ')
if [ "${1:-}" != RUN ]; then bad "A14: the harness failed: $(printf '%s' "$res" | tail -3)"
else
  [ "$2" = 30 ] && ok "A14: first run hashes the 30 images" || bad "A14: first run hashed $2 images, want 30"
  [ "$3" = 0 ] && ok "A14: an unchanged image is not hashed again on the next run" || bad "A14: the next run hashed $3 unchanged images again"
  [ "$6" = 30 ] && [ "$7" = 30 ] && ok "A14: both runs still count the 30 images" || bad "A14: image counts $6 / $7"
  [ "$8" = 0 ] && [ "$9" = 1 ] && ok "A14: a byte copy is still reported as a duplicate (images hashed for it: $4)" \
    || bad "A14: duplicates before/after a byte copy: $8 / $9"
  [ "$5" -ge 1 ] && [ "${10}" = 2 ] && ok "A14: an image rewritten with the same size is hashed again ($5) and its duplicate found" \
    || bad "A14: rewritten image: hashed $5, duplicates ${10} (want 2)"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_git_batching: all tests passed" || { echo "❌ test_gate_git_batching: $FAILS failed"; exit 1; }
