#!/usr/bin/env bash
# Regression test: bin/regression_checklist.py mark_stale — a watched file deleted AFTER a
# `+dirty` PASS run makes the row STALE. record_results keeps the files already deleted when it
# recorded (`deleted`), so only those are "what ran"; a file gone since then is a change.
#  - dirty run, then a watched file removed → STALE
#  - control: the file was already deleted when the run was recorded → still PASS
#  - an old result without `deleted` keeps the old rule (dirty run: a missing file is no hit)
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

new_repo() {
  P="$TMP/p$RANDOM"; mkdir -p "$P/src/a" "$P/.agents"
  ( cd "$P" && git init -q . && git config user.email t@t && git config user.name t
    echo "x = 1" > src/a/x.py; echo "y = 1" > src/a/y.py
    git add -A && git commit -qm init )
}
# record <keep_deleted:1|0>: a PASS of REG-A (watches src/a/*) at <sha>+dirty, via the module
record() {
  python3 - "$P" "$DEVKIT_DIR" "$1" <<'PY'
import sys, pathlib, subprocess
sys.path.insert(0, sys.argv[2] + "/bin"); import regression_checklist as r
p = pathlib.Path(sys.argv[1]); d = r.load(p)
d["items"]["REG-A"] = {"id": "REG-A", "kind": "test", "component": "A", "watch_files": ["src/a/*"],
                       "command": "true", "last": None, "history": []}
sha = subprocess.run(["git", "-C", str(p), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
r.record_results(d, [{"id": "REG-A", "status": "PASS", "exit_code": 0}], task=None, commit=f"{sha}+dirty", project=p)
if sys.argv[3] == "0":
    d["items"]["REG-A"]["last"].pop("deleted", None)       # a result written before `deleted` existed
r.save(p, d)
PY
}
stale() { python3 - "$P" "$DEVKIT_DIR" <<'PY'
import sys, pathlib
sys.path.insert(0, sys.argv[2] + "/bin"); import regression_checklist as r
p = pathlib.Path(sys.argv[1]); d = r.load(p); r.mark_stale(d, p)
it = d["items"]["REG-A"]; print("STALE" if it.get("stale_since") else "PASS", ",".join(it.get("stale_files", [])))
PY
}

# dirty run (x edited), then y deleted → STALE
new_repo; cd "$P"; echo "x = 2" > src/a/x.py
record 1; sleep 1.1
[ "$(stale | cut -d' ' -f1)" = PASS ] && ok "dirty PASS, nothing changed since → PASS" || fail "baseline: $(stale)"
rm src/a/y.py
out="$(stale)"
[ "${out%% *}" = STALE ] && printf '%s' "$out" | grep -q "src/a/y.py" \
  && ok "watched file deleted after a +dirty run → STALE (names the file)" || fail "deleted after dirty run: $out"

# control: y already deleted when the run was recorded → what ran → still PASS
new_repo; cd "$P"; rm src/a/y.py
record 1; sleep 1.1
[ "$(stale | cut -d' ' -f1)" = PASS ] && ok "file already deleted at record time → not STALE" || fail "deleted before run: $(stale)"
python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['REG-A']['last'].get('deleted'))" \
  | grep -q "src/a/y.py" && ok "record_results stores the tree's deleted files in the run result" || fail "no deleted list"

# an old result without `deleted`: today's rule (dirty run, missing file → no hit)
new_repo; cd "$P"; echo "x = 2" > src/a/x.py
record 0; sleep 1.1; rm src/a/y.py
[ "$(stale | cut -d' ' -f1)" = PASS ] && ok "old dirty result without 'deleted' keeps the old behaviour" || fail "old result: $(stale)"

[ "$FAILS" -eq 0 ] && echo "✅ test_stale_deleted: all passed" || { echo "❌ test_stale_deleted: $FAILS failed"; exit 1; }
