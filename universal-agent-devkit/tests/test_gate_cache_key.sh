#!/usr/bin/env bash
# Regression test: bin/post-fix-gate.py reuses a full PASS (cached_full_pass) across edits of the
# gate script that do not change how suite results are read, and re-runs once RESULT_FORMAT moves.
# 2026-09-28 (GeelyEx2): the reuse key held the sha of post-fix-gate.py itself; the DevKit source
# changed 44 times in 5 days (projects symlink the live DevKit), so the reuse almost never hit.
# Also: a receipt written with the old key (gate_sha, no result_format) is never reused, and the
# receipt still records gate_sha.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0

# A copy of the DevKit parts the gate imports, so its post-fix-gate.py can be edited freely.
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
printf 'runs.txt\n' > .gitignore
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt

run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests --full "$@" 2>&1; }
runs() { [ -f runs.txt ] && wc -l < runs.txt | tr -d ' ' || echo 0; }
receipt() { python3 - "$1" <<'PY'
import json, subprocess, sys
gd = subprocess.run(["git", "rev-parse", "--absolute-git-dir"], capture_output=True, text=True).stdout.strip()
try:
    print(json.load(open(gd + "/postfix-gate/full_pass.json")).get(sys.argv[1]))
except OSError:
    print("NO-RECEIPT")
PY
}

out="$(run_gate)"; rc=$?
if [ "$rc" != 0 ] || [ "$(runs)" != 1 ]; then
  echo "✖ setup: the first full run must PASS and run the suite once (exit $rc, runs $(runs))"
  printf '%s\n' "$out" | tail -15; exit 1
fi
echo "✔ setup: first full run PASS"

[ -n "$(receipt gate_sha | grep -v -e None -e NO-RECEIPT)" ] && echo "✔ the receipt still records gate_sha" \
  || { echo "✖ the receipt has no gate_sha ($(receipt gate_sha))"; FAILS=$((FAILS + 1)); }

# 1. A comment-only edit of the gate script: same RESULT_FORMAT -> the PASS is reused.
printf '\n# a comment that changes the sha of post-fix-gate.py, not how results are read\n' >> "$GATE"
out="$(run_gate)"; rc=$?
if [ "$rc" = 0 ] && [ "$(runs)" = 1 ]; then
  echo "✔ a comment edit of the gate reuses the full PASS"
else
  echo "✖ a comment edit of the gate re-ran the suite (exit $rc, runs $(runs)) — gate_sha is still a reuse condition"
  FAILS=$((FAILS + 1))
fi

# 2. RESULT_FORMAT bumped in the copy -> the suite runs again.
python3 - "$GATE" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s2, n = re.subn(r"(?m)^RESULT_FORMAT = (\d+)", lambda m: f"RESULT_FORMAT = {int(m.group(1)) + 1}", s, count=1)
open(p, "w", encoding="utf-8").write(s2)
sys.exit(0 if n == 1 else 1)
PY
bumped=$?
before="$(runs)"
out="$(run_gate)"; rc=$?
if [ "$bumped" = 0 ] && [ "$rc" = 0 ] && [ "$(runs)" = $((before + 1)) ]; then
  echo "✔ a RESULT_FORMAT bump re-runs the suite"
else
  echo "✖ RESULT_FORMAT bump (found=$([ "$bumped" = 0 ] && echo yes || echo no)): exit $rc, runs $before -> $(runs)"
  FAILS=$((FAILS + 1))
fi

# 3. A receipt in the old format (gate_sha, no result_format) is never reused.
python3 - <<'PY'
import json, subprocess
gd = subprocess.run(["git", "rev-parse", "--absolute-git-dir"], capture_output=True, text=True).stdout.strip()
p = gd + "/postfix-gate/full_pass.json"
r = json.load(open(p))
r.pop("result_format", None)
json.dump(r, open(p, "w"))
PY
before="$(runs)"
out="$(run_gate)"; rc=$?
if [ "$rc" = 0 ] && [ "$(runs)" = $((before + 1)) ]; then
  echo "✔ an old-format receipt (no result_format) is not reused"
else
  echo "✖ an old-format receipt was reused (exit $rc, runs $before -> $(runs))"
  FAILS=$((FAILS + 1))
fi

if [ "$FAILS" -ne 0 ]; then
  echo "gate cache key: $FAILS FAILED"; exit 1
fi
echo "gate cache key: all checks passed"
