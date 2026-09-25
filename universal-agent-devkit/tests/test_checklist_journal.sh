#!/usr/bin/env bash
# Regression test: the living checklist (.agents/regression_status.json) cannot be rolled back
# silently. Incident 2026-09-24 (GeelyEx2): a subagent ran
#   git show HEAD:.agents/regression_status.json > .agents/regression_status.json
# outside the DevKit lock; ~25 red_proof PROVEN results and 32 bugs link/unlink edits vanished
# and nothing noticed.
#  - every rc.save() journals {time, writer, pid, content hash} + a bounded snapshot in
#    .agents/regression_journal/ (git-ignored by itself, never committed)
#  - rc.load() sees a file that is not the last journaled one AND lost content (a red_proof,
#    an unlink, a row, a result) → a warning naming the last good snapshot, kept until restore
#  - a normal save, or an out-of-band write that only ADDS content → no warning
#  - `agent-kit checklist restore` merges: newer red_proof per row by ts, union of links minus
#    recorded unlinks, rows added after the rollback kept
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
HOOK="$DEVKIT_DIR/hooks/session_context.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/p"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
echo "x = 1" > src/a.py
printf 'def test_a(): pass\n' > tests/test_a.py; printf 'def test_b(): pass\n' > tests/test_b.py
cat > .agents/regression_matrix.active.json <<'JSON'
{"rules":[{"component":"A","watch_files":["src/*.py","tests/*.py"],
 "mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"python3 -m pytest tests/test_a.py"},
                               {"id":"REG-B","name":"b","command":"python3 -m pytest tests/test_b.py"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
S="$P/.agents/regression_status.json"; J="$P/.agents/regression_journal"
bugid() { grep -o 'BUG-[A-Za-z0-9_-]*' | head -1; }
# A red_proof written the way scripts/red_proof.py writes it: under the lock, through rc.save.
proof() { python3 - "$DEVKIT_DIR/bin" "$P" "$1" "$2" "$3" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import regression_checklist as rc
p, bid, st, ts = sys.argv[2], sys.argv[3], sys.argv[4], float(sys.argv[5])
with rc.locked(p):
    d = rc.load(p); d["items"][bid]["red_proof"] = {"status": st, "at": "t", "ts": ts, "reason": "r"}; rc.save(p, d)
PY
}
field() { python3 -c "import json,sys;it=json.load(open('$S'))['items'].get('$1') or {};print(eval(sys.argv[1]))" "$2"; }
warned() { printf '%s' "$1" | grep -q "regression_journal/snapshots/"; }

B1="$(bash "$KIT" bugs add "Sai A" --fixed --test REG-A 2>&1 | bugid)"
B2="$(bash "$KIT" bugs add "Sai B" --fixed --test REG-A 2>&1 | bugid)"
bash "$KIT" bugs link "$B2" REG-B >/dev/null 2>&1
B4="$(bash "$KIT" bugs add "Sai D" --fixed --test REG-A 2>&1 | bugid)"
B5="$(bash "$KIT" bugs add "Sai F" --fixed 2>&1 | bugid)"
git add -A && git commit -qm "checklist committed" -q          # HEAD: no proofs, B2 → REG-A + REG-B

# The day's work, all through the DevKit.
proof "$B1" PROVEN 1000
proof "$B4" PROVEN 1000
bash "$KIT" bugs unlink "$B2" REG-B >/dev/null 2>&1
[ -f "$J/journal.jsonl" ] && [ "$(wc -l < "$J/journal.jsonl")" -ge 3 ] && ok "every save is journaled" || fail "no journal: $(ls -la "$J" 2>&1)"
head -1 "$J/journal.jsonl" | python3 -c "import json,sys;r=json.loads(sys.stdin.read());assert r['writer'] and r['pid'] and len(r['hash'])>=16 and r['at']" 2>/dev/null \
  && ok "a journal record has time, writer, pid, content hash" || fail "journal record: $(head -1 "$J/journal.jsonl" 2>&1)"

# A normal save → no warning.
out="$(bash "$KIT" bugs show 2>&1)"; out2="$(bash "$KIT" bugs add "Sai E" --fixed 2>&1)"
warned "$out$out2" && fail "normal save warned: $out2" || ok "a normal save: no warning"

# An out-of-band write that only ADDS content (a test fixture, a hand edit) → no warning.
python3 - "$S" "$B1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["items"][sys.argv[2]]["note"] = "hand edit"; json.dump(d, open(sys.argv[1], "w"))
PY
out="$(bash "$KIT" bugs show 2>&1)"
warned "$out" && fail "an additive out-of-band write warned: $out" || ok "an out-of-band write that loses nothing: no warning"

# The incident: an older copy overwrites the file outside the DevKit.
git show HEAD:.agents/regression_status.json > .agents/regression_status.json
out="$(bash "$KIT" bugs show 2>&1)"
warned "$out" && ok "rollback to an older copy → warning" || fail "rollback not detected: $out"
snap="$(printf '%s' "$out" | grep -o '\.agents/regression_journal/snapshots/[^ )]*' | head -1)"
[ -n "$snap" ] && [ -f "$P/$snap" ] && ok "the warning names the last good snapshot ($snap)" || fail "snapshot path: '$snap'"
printf '%s' "$out" | grep -q "checklist restore" && ok "the warning names the cure (agent-kit checklist restore)" || fail "no cure: $out"
ctx="$(printf '{}' | bash "$HOOK" 2>/dev/null)"
warned "$ctx" && ok "SessionStart context carries the warning" || fail "session context: $ctx"

# New work after the rollback, through the DevKit: the warning must survive these saves.
B3="$(bash "$KIT" bugs add "Sai C" --fixed --test REG-A 2>/dev/null | bugid)"   # stderr: the warning names ids
proof "$B4" INCONCLUSIVE 2000
bash "$KIT" bugs drop "$B5" >/dev/null 2>&1                    # a legitimate removal after the rollback
out="$(bash "$KIT" bugs show 2>&1)"
warned "$out" && ok "the warning survives later saves" || fail "a later save hid the rollback: $out"
out="$(bash "$KIT" health -t "$P" 2>&1)"
warned "$out" && ok "agent-kit health shows the rollback" || fail "health: $(printf '%s' "$out" | tail -3)"

out="$(bash "$KIT" checklist restore --list 2>&1)"; rc=$?
[ $rc = 0 ] && [ -n "$snap" ] && printf '%s' "$out" | grep -q "$(basename "$snap")" && ok "restore --list lists the snapshots" || fail "list: rc=$rc $out"
out="$(bash "$KIT" checklist restore 2>&1)"; rc=$?
[ $rc = 0 ] && printf '%s' "$out" | grep -q "merged" && ok "restore merges the snapshot in" || fail "restore: rc=$rc $out"
[ "$(field "$B1" "(it.get('red_proof') or {}).get('status')")" = PROVEN ] && ok "the lost PROVEN red_proof is back" || fail "B1 proof: $(field "$B1" "it.get('red_proof')")"
[ "$(field "$B4" "(it.get('red_proof') or {}).get('status')")" = INCONCLUSIVE ] && ok "a newer red_proof (by ts) wins over the snapshot" || fail "B4 proof: $(field "$B4" "it.get('red_proof')")"
[ "$(field "$B2" "'REG-B' in it.get('tests', [])")" = False ] && [ "$(field "$B2" "len(it.get('unlinked') or [])")" = 1 ] \
  && ok "the lost unlink is back (REG-B not linked again)" || fail "B2: $(field "$B2" "(it.get('tests'), it.get('unlinked'))")"
[ "$(field "$B2" "'REG-A' in it.get('tests', [])")" = True ] && ok "links not unlinked are kept" || fail "B2 lost REG-A"
[ -n "$B3" ] && [ "$(field "$B3" "it.get('title')")" = "Sai C" ] && ok "a row added after the rollback is kept" || fail "B3 lost"
[ -n "$B5" ] && [ "$(field "$B5" "it.get('title')")" = None ] && ok "a row dropped through the DevKit is not brought back" || fail "B5 resurrected"
[ "$(field "$B1" "it.get('note')")" = "hand edit" ] && ok "content only the snapshot had is merged in" || fail "note lost"
out="$(bash "$KIT" bugs show 2>&1)"
warned "$out" && fail "warning still shown after restore: $out" || ok "after restore: no warning"

# A reader outside the lock loads between a drop's file replace and its journal line: no rollback.
B6="$(bash "$KIT" bugs add "Sai G" --fixed 2>&1 | bugid)"
python3 - "$DEVKIT_DIR/bin" "$P" "$B6" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import regression_checklist as rc
p, bid = sys.argv[2], sys.argv[3]
real = rc._journal_save
def reader_first(*a, **k):
    rc.load(p)          # an unlocked reader sees the new file before its journal line
    return real(*a, **k)
rc._journal_save = reader_first
with rc.locked(p):
    d = rc.load(p); rc.drop(d, bid); rc.save(p, d)
PY
[ ! -f "$J/rollback.json" ] && ok "a drop seen mid-save by a reader is no rollback" || fail "false rollback: $(cat "$J/rollback.json")"

# Missing file with a journal → warning too.
mv "$S" "$TMP/s.json"
out="$(bash "$KIT" bugs show 2>&1)"; warned "$out" && ok "a deleted checklist → warning" || fail "delete not detected: $out"
mv "$TMP/s.json" "$S"

# Bounded and never committed.
for i in $(seq 1 30); do CHECKLIST_JOURNAL_MAX=20 CHECKLIST_SNAPSHOTS=5 bash "$KIT" bugs add "Bounded $i" --fixed >/dev/null 2>&1; done
n="$(wc -l < "$J/journal.jsonl" | tr -d ' ')"; s="$(ls "$J/snapshots" | wc -l | tr -d ' ')"
[ "$n" -le 20 ] && [ "$s" -le 6 ] && ok "journal ($n lines) and snapshots ($s) are bounded" || fail "unbounded: $n lines, $s snapshots"
git check-ignore -q .agents/regression_journal/journal.jsonl && [ -z "$(git status --porcelain -- .agents/regression_journal)" ] \
  && ok "the journal is not tracked by git" || fail "journal visible to git: $(git status --porcelain)"

# Git moved the file and nothing was lost: a branch switch, a reset or a stash puts the committed
# version of another commit in place while the last journaled content is safe in git (committed at
# the recorded HEAD, at a commit HEAD visited since, or in the stash) → a new baseline, no rollback.
Q="$TMP/q"; mkdir -p "$Q/src" "$Q/tests" "$Q/.agents"
cd "$Q" && git init -q . && git symbolic-ref HEAD refs/heads/main && git config user.email t@t && git config user.name t
echo "x = 1" > src/a.py; printf 'def test_a(): pass\n' > tests/test_a.py
cp "$P/.agents/regression_matrix.active.json" .agents/
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$Q"; P="$Q"; S="$Q/.agents/regression_status.json"; J="$Q/.agents/regression_journal"
C1="$(bash "$KIT" bugs add "Sai A tren main" --fixed --test REG-A 2>&1 | bugid)"
git add -A && git commit -qm "checklist on main"
git checkout -q -b feat
CF="$(bash "$KIT" bugs add "Sai B tren feat" --fixed --test REG-A 2>&1 | bugid)"
git add -A && git commit -qm "bug on feat"
git checkout -q main
out="$(bash "$KIT" checklist check 2>&1)"; rc=$?
[ $rc = 0 ] && ! warned "$out" && [ ! -f "$J/rollback.json" ] && ok "a branch switch back to main is no rollback" \
  || fail "branch switch flagged: rc=$rc $out"
tail -1 "$J/journal.jsonl" | python3 -c "import json,sys;r=json.loads(sys.stdin.read());assert len(r.get('head') or '')>=40" 2>/dev/null \
  && ok "a journal record carries the HEAD sha" || fail "no head in: $(tail -1 "$J/journal.jsonl")"
bash "$KIT" checklist restore >/dev/null 2>&1
[ -n "$CF" ] && [ "$(field "$CF" "it.get('title')")" = None ] && ok "restore on main does not bring the feat-only row" \
  || fail "feat row merged into main: $(field "$CF" "it.get('title')")"
git reset -q --hard; bash "$KIT" checklist check >/dev/null 2>&1
git checkout -q feat
out="$(bash "$KIT" checklist check 2>&1)"; rc=$?
[ $rc = 0 ] && ! warned "$out" && ok "a branch switch to feat is no rollback" || fail "switch to feat flagged: rc=$rc $out"
git reset -q --hard HEAD~1                                      # committed content only: nothing lost
out="$(bash "$KIT" checklist check 2>&1)"; rc=$?
[ $rc = 0 ] && ok "git reset --hard over committed content is no rollback" || fail "reset flagged: rc=$rc $out"
git checkout -q main
proof "$C1" PROVEN 1000                                         # uncommitted work …
git stash -q                                                    # … kept in the stash
out="$(bash "$KIT" checklist check 2>&1)"; rc=$?
[ $rc = 0 ] && ok "git stash of the checklist is no rollback" || fail "stash flagged: rc=$rc $out"
git stash pop -q
out="$(bash "$KIT" checklist check 2>&1)"; rc=$?
[ $rc = 0 ] && [ "$(field "$C1" "(it.get('red_proof') or {}).get('status')")" = PROVEN ] && ok "stash pop: no warning, the proof is back" \
  || fail "stash pop: rc=$rc $out"
# Still caught: HEAD moved (a code-only commit), then the committed copy overwrote uncommitted work
# that is in no commit.
proof "$C1" PROVEN 2000
echo "x = 2" > src/a.py; git add src/a.py; git commit -qm "code only"
git show HEAD:.agents/regression_status.json > .agents/regression_status.json
out="$(bash "$KIT" checklist check 2>&1)"; rc=$?
[ $rc = 1 ] && warned "$out" && ok "a code commit, then HEAD's copy over uncommitted work → rollback" \
  || fail "copy after a code-only commit not caught: rc=$rc $out"

# Two processes appending at the journal cap lose no line (read-then-replace trim under a lock).
python3 - "$DEVKIT_DIR/bin" "$Q" <<'PY'
import multiprocessing, os, sys; sys.path.insert(0, sys.argv[1]); import regression_checklist as rc
p = sys.argv[2]; os.environ["CHECKLIST_JOURNAL_MAX"] = "400"
path = rc._jdir(p, create=True) / rc.JOURNAL_NAME
path.write_text("".join('{"event": "fill"}\n' for _ in range(400)), encoding="utf-8")
def w(tag):
    for i in range(150):
        rc._append(p, {"event": "race", "tag": f"{tag}{i}"})
ctx = multiprocessing.get_context("fork")
ps = [ctx.Process(target=w, args=(t,)) for t in "ab"]
[x.start() for x in ps]; [x.join() for x in ps]
PY
n="$(grep -c '"event": "race"' "$J/journal.jsonl")"
[ "$n" = 300 ] && ok "two writers at the journal cap lose no line" || fail "concurrent appends lost lines: $n/300 kept"

[ "$FAILS" -eq 0 ] && echo "✅ test_checklist_journal: all passed" || { echo "❌ test_checklist_journal: $FAILS failed"; exit 1; }
