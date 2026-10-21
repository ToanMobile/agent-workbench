#!/usr/bin/env bash
# Regression test (issue #30): (a) the nightly run cleans old audit-gate files (>7 days), (b) fold_agent_file.py run again on an
# EDITED source replaces its section instead of appending a second copy, (c) antigravity_collab_hint() fires for the intent names
# the classifier really emits (SECURITY, ARCHITECTURE_REFACTOR, DEPRECATION_MIGRATION).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
NIGHTLY="$DEVKIT_DIR/scripts/governance/nightly.py"
FOLD="$DEVKIT_DIR/scripts/governance/fold_agent_file.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export HOME="$TMP/home" DEVKIT_LANG=en NIGHTLY_NOTIFY=0; mkdir -p "$HOME"

# (a) nightly cleans audit-gate: a 10-day-old file goes, a fresh one stays, even when the project has no matrix (run is skipped)
P="$TMP/p"; A="$P/.claude/audit-gate"; mkdir -p "$A" "$P/.agents"
( cd "$P" && git init -q . && git config devkit.trunkMode false )
echo old > "$A/regression_gate.log"; touch -t 202001010000 "$A/regression_gate.log"
echo new > "$A/review_gate.log"
echo '{}' > "$A/approved_x.json"; touch -t 202001010000 "$A/approved_x.json"
python3 "$NIGHTLY" run "$P" >/dev/null 2>&1
[ ! -e "$A/regression_gate.log" ] && [ -f "$A/review_gate.log" ] && ok "nightly run removes old audit-gate files, keeps fresh ones" || fail "audit-gate: $(ls "$A")"
[ -f "$A/approved_x.json" ] && ok "nightly age pass keeps old state *.json (gate memory)" || fail "state json removed by the age pass"

# (d) size cap: FRESH logs (no age to clean) totalling ~8 MB end up under 5 MB after the nightly run; .gitignore and state json stay
P2="$TMP/p2"; A2="$P2/.claude/audit-gate"; mkdir -p "$A2" "$P2/.agents"
( cd "$P2" && git init -q . && git config devkit.trunkMode false )
python3 -B -I - "$A2" <<'PY'
import os, sys
a = sys.argv[1]
line = "x" * 99 + "\n"
for name, mb in (("surfaced.jsonl", 3), ("review_gate.log", 2), ("read_ledger.tsv", 2), ("churn_guard.log", 1)):
    open(os.path.join(a, name), "w").write(line * (mb * 10486))
os.makedirs(os.path.join(a, "wg_scan"))
open(os.path.join(a, "wg_scan", "scan.json"), "w").write("y" * 1024)
open(os.path.join(a, ".gitignore"), "w").write("*\n")
open(os.path.join(a, "regression_gate.state.json"), "w").write("{}")
PY
python3 "$NIGHTLY" run "$P2" >/dev/null 2>&1
KB=$(du -sk "$A2" | cut -f1)
[ "$KB" -lt 5120 ] && [ -f "$A2/.gitignore" ] && [ -f "$A2/regression_gate.state.json" ] && [ -f "$A2/review_gate.log" ] \
  && ok "nightly caps fresh audit-gate under 5 MB ($KB KB), keeps .gitignore/state/log tails" || fail "audit-gate size cap: $KB KB"

# (e) the cap only trims log tails: fresh restore-backup, flock files and session dirs survive; small logs are never planned for a trim
P3="$TMP/p3"; A3="$P3/.claude/audit-gate"; mkdir -p "$A3/restore-backup/t1" "$A3/session_worktree" "$P3/.agents"
( cd "$P3" && git init -q . && git config devkit.trunkMode false )
python3 -B -I - "$A3" <<'PY'
import os, sys
a = sys.argv[1]
line = "x" * 99 + "\n"
for name, mb in (("surfaced.jsonl", 3), ("review_gate.log", 3), ("read_ledger.tsv", 2)):
    open(os.path.join(a, name), "w").write(line * (mb * 10486))
open(os.path.join(a, "restore-backup", "t1", "saved.txt"), "w").write("precious")
open(os.path.join(a, "restore-backup", "t1", "big.bin"), "w").write("z" * (5 * 1024 * 1024))   # keeps the folder over the cap with every log trimmed
open(os.path.join(a, "test_run.lock"), "w").write("")
open(os.path.join(a, "session_worktree", "s.json"), "w").write("{}")
PY
python3 "$NIGHTLY" run "$P3" >/dev/null 2>&1
KB3=$(du -sk "$A3" | cut -f1)
[ -f "$A3/restore-backup/t1/saved.txt" ] && [ -f "$A3/test_run.lock" ] && [ -f "$A3/session_worktree/s.json" ] && [ "$(wc -l < "$A3/review_gate.log")" -le 1000 ] \
  && ok "cap trims log tails only: fresh backup, lock and session dir survive ($KB3 KB)" || fail "cap removed live data or missed the cap ($KB3 KB): $(ls "$A3")"
P4="$TMP/p4"; A4="$P4/.claude/audit-gate"; mkdir -p "$A4"
python3 -B -I - "$A4" <<'PY'
import os, sys
for i in range(1500):
    open(os.path.join(sys.argv[1], f"s{i}.log"), "w").write("x\n" * 100)
PY
python3 "$DEVKIT_DIR/scripts/governance/devkit_clean.py" "$P4" --days=7 | grep -q "would trim" \
  && fail "cap plans a no-op trim for a log under 1000 lines" || ok "cap plans no trim for logs under 1000 lines"

# (f) state files that are not *.json (R6): the nightly age pass (10 days old) AND the cap pass (idle 2 days, cap unreachable) keep
# worktree_merge_gate.state (holds `owed`), proof_gate.state, .testsourceset_attempts*; an idle per-session marker still goes
P5="$TMP/p5"; A5="$P5/.claude/audit-gate"; mkdir -p "$A5" "$P5/.agents"
( cd "$P5" && git init -q . && git config devkit.trunkMode false )
python3 -B -I - "$A5" <<'PY'
import os, sys, time
a = sys.argv[1]
def put(name, text, age_days):
    p = os.path.join(a, name); open(p, "w").write(text)
    t = time.time() - age_days * 86400; os.utime(p, (t, t))
for n in ("worktree_merge_gate.state", "proof_gate.state", ".testsourceset_attempts_s1"):
    put(n, "owed\n", 10)            # age pass
    put("idle_" + n, "owed\n", 2)   # cap pass
put("prompt_seen_s1", "", 2)
put("surfaced.jsonl", ("x" * 99 + "\n") * (3 * 10486), 0)
put("pinned.bin", "z" * (4 * 1024 * 1024), 0)   # not removable: the cap stays over 3 MB after every log tail is cut
PY
python3 "$NIGHTLY" run "$P5" >/dev/null 2>&1
MISS=""; for n in worktree_merge_gate.state proof_gate.state .testsourceset_attempts_s1 idle_worktree_merge_gate.state idle_proof_gate.state idle_.testsourceset_attempts_s1; do
  [ -f "$A5/$n" ] || MISS="$MISS $n"; done
[ -z "$MISS" ] && [ ! -e "$A5/prompt_seen_s1" ] && ok "age and cap passes keep non-json state files, still drop idle session markers" || fail "state files removed:$MISS (prompt_seen_s1 left: $([ -e "$A5/prompt_seen_s1" ] && echo yes || echo no))"

# (b) fold: same source run twice = no change; edited source = one section, not two
F="$TMP/f"; mkdir -p "$F"
printf 'proj line A\nline B\n' > "$F/CLAUDE.md"
python3 "$FOLD" "$F/CLAUDE.md" "$F/AGENTS.md" >/dev/null; python3 "$FOLD" "$F/CLAUDE.md" "$F/AGENTS.md" >/dev/null
[ "$(grep -c '^line B$' "$F/AGENTS.md")" = 1 ] && ok "fold: same source twice stays one copy" || fail "fold twice"
printf 'proj line A\nline B edited\n' > "$F/CLAUDE.md"
python3 "$FOLD" "$F/CLAUDE.md" "$F/AGENTS.md" >/dev/null
[ "$(grep -c 'proj line A' "$F/AGENTS.md")" = 1 ] && grep -q 'line B edited' "$F/AGENTS.md" && ! grep -q '^line B$' "$F/AGENTS.md" \
  && ok "fold: edited source replaces its section (no duplicate)" || fail "fold edited: $(cat "$F/AGENTS.md")"
printf 'proj line A\n' > "$F/CLAUDE.md"
python3 "$FOLD" "$F/CLAUDE.md" "$F/AGENTS.md" >/dev/null
! grep -q 'line B' "$F/AGENTS.md" && grep -c 'proj line A' "$F/AGENTS.md" | grep -qx 1 \
  && ok "fold: a line removed from the source leaves AGENTS.md" || fail "fold removed line: $(cat "$F/AGENTS.md")"
SZ=$(wc -c < "$F/AGENTS.md"); python3 "$FOLD" "$F/CLAUDE.md" "$F/AGENTS.md" >/dev/null
[ "$(wc -c < "$F/AGENTS.md")" = "$SZ" ] && ok "fold: re-run does not grow AGENTS.md" || fail "fold grew"

# (c) intent names
python3 -B -I - "$DEVKIT_DIR/scripts/context" <<'PY' && ok "collab hint fires for ARCHITECTURE_REFACTOR / SECURITY / DEPRECATION_MIGRATION" || fail "collab hint silent for a real intent name"
import sys
sys.path.insert(0, sys.argv[1])
import enrich_context as e
for intent in ("ARCHITECTURE_REFACTOR", "SECURITY", "DEPRECATION_MIGRATION"):
    assert e.antigravity_collab_hint("đổi tên một hàm nhỏ trong module", {"detected_intents": [intent]}, "."), intent
assert not e.antigravity_collab_hint("đổi tên một hàm nhỏ trong module", {"detected_intents": ["BUG_FIX"]}, "."), "BUG_FIX must stay silent"
PY

if [ "$FAILS" -ne 0 ]; then echo "governance cleanup/fold/intent: $FAILS FAILED"; exit 1; fi
echo "governance cleanup/fold/intent: all checks passed"
