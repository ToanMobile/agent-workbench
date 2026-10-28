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

# (g) uninstall understands the folded-from marker pair (R9): the section leaves AGENTS.md whole and CLAUDE.md comes back
# without a marker line; a section written before the markers (only `moved from`) still restores
python3 -B -I - "$DEVKIT_DIR" "$TMP" <<'PY' && ok "uninstall: folded-from marker pair removed from AGENTS.md and not copied into the restored file" || fail "uninstall left a folded-from marker (R9)"
import os, subprocess, sys
dk, tmp = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(dk, "scripts", "governance"))
import devkit_uninstall as u
fold = os.path.join(dk, "scripts", "governance", "fold_agent_file.py")
block = "<!-- universal-agent-devkit:start -->\nkit\n<!-- universal-agent-devkit:end -->\n"
for tag, legacy in (("new", False), ("legacy", True)):
    p = os.path.join(tmp, "u_" + tag); os.makedirs(p)
    open(os.path.join(p, "CLAUDE.md"), "w").write("proj line A\nline B\n")
    open(os.path.join(p, "AGENTS.md"), "w").write("# own\n\n" + block)
    subprocess.run([sys.executable, fold, os.path.join(p, "CLAUDE.md"), os.path.join(p, "AGENTS.md")], check=True, capture_output=True)
    if legacy:   # the format before the markers existed
        t = open(os.path.join(p, "AGENTS.md")).read()
        t = "\n".join(l for l in t.split("\n") if not l.startswith("<!-- folded-from:"))
        open(os.path.join(p, "AGENTS.md"), "w").write(t)
    os.remove(os.path.join(p, "CLAUDE.md"))
    u.unfold_agent_files(u.Plan(p, True), p)
    agents = open(os.path.join(p, "AGENTS.md")).read()
    restored = open(os.path.join(p, "CLAUDE.md")).read()
    assert "folded-from" not in agents and "moved from" not in agents and "line B" not in agents, (tag, agents)
    assert restored == "proj line A\nline B\n", (tag, restored)
PY

# (c) intent names
python3 -B -I - "$DEVKIT_DIR/scripts/context" <<'PY' && ok "collab hint fires for ARCHITECTURE_REFACTOR / SECURITY / DEPRECATION_MIGRATION" || fail "collab hint silent for a real intent name"
import sys
sys.path.insert(0, sys.argv[1])
import enrich_context as e
for intent in ("ARCHITECTURE_REFACTOR", "SECURITY", "DEPRECATION_MIGRATION"):
    assert e.antigravity_collab_hint("đổi tên một hàm nhỏ trong module", {"detected_intents": [intent]}, "."), intent
assert not e.antigravity_collab_hint("đổi tên một hàm nhỏ trong module", {"detected_intents": ["BUG_FIX"]}, "."), "BUG_FIX must stay silent"
PY

# (h) #547: devkit_clean dọn thêm đường dẫn runtime super-board đã gitignore cũ hơn --days, giữ nguyên 100% file tracked, đường dẫn không
# gitignore và mục mới/hôm nay.
P6="$TMP/p6"; TODAY="$(date +%Y-%m-%d)"
mkdir -p "$P6/docs/super-board/runs/issue-1" \
         "$P6/docs/super-board/runs/2020-01-01-workers" \
         "$P6/docs/super-board/runs/2020-01-02-workers" \
         "$P6/docs/super-board/runs/${TODAY}-workers" \
         "$P6/docs/super-board/runs/keep-unignored" \
         "$P6/.claude/super-board"
cat > "$P6/.gitignore" <<'GI'
.claude/super-board/last-merge-verify-pr-*.log
docs/super-board/runs/*-workers/
GI
echo "tracked summary" > "$P6/docs/super-board/runs/issue-1/summary.md"
echo "force tracked" > "$P6/docs/super-board/runs/2020-01-01-workers/tracked.md"
echo "ignored old worker" > "$P6/docs/super-board/runs/2020-01-02-workers/worker.log"
echo "ignored today worker" > "$P6/docs/super-board/runs/${TODAY}-workers/worker.log"
echo "unignored note" > "$P6/docs/super-board/runs/keep-unignored/note.md"
(
  cd "$P6" && git init -q . && git config user.email t@t && git config user.name t
  git add .gitignore docs/super-board/runs/issue-1/summary.md
  git add -f docs/super-board/runs/2020-01-01-workers/tracked.md
  git commit -qm init
)
mkdir -p "$P6/.git/super-board"
echo "old git verify" > "$P6/.git/super-board/last-merge-verify-pr-10.log"
echo "fresh git verify" > "$P6/.git/super-board/last-merge-verify-pr-11.log"
echo "old claude verify" > "$P6/.claude/super-board/last-merge-verify-pr-20.log"
echo "fresh claude verify" > "$P6/.claude/super-board/last-merge-verify-pr-21.log"
touch -t 202001010000 \
  "$P6/docs/super-board/runs/issue-1/summary.md" \
  "$P6/docs/super-board/runs/issue-1" \
  "$P6/docs/super-board/runs/2020-01-01-workers/tracked.md" \
  "$P6/docs/super-board/runs/2020-01-01-workers" \
  "$P6/docs/super-board/runs/2020-01-02-workers/worker.log" \
  "$P6/docs/super-board/runs/2020-01-02-workers" \
  "$P6/docs/super-board/runs/keep-unignored/note.md" \
  "$P6/docs/super-board/runs/keep-unignored" \
  "$P6/.git/super-board/last-merge-verify-pr-10.log" \
  "$P6/.claude/super-board/last-merge-verify-pr-20.log"
python3 "$DEVKIT_DIR/scripts/governance/devkit_clean.py" "$P6" --days=7 --apply --keep-state >/dev/null 2>&1
[ ! -e "$P6/docs/super-board/runs/2020-01-02-workers" ] \
  && [ ! -e "$P6/.git/super-board/last-merge-verify-pr-10.log" ] \
  && [ ! -e "$P6/.claude/super-board/last-merge-verify-pr-20.log" ] \
  && ok "devkit_clean removes gitignored old super-board verify logs and *-workers dirs" \
  || fail "devkit_clean missed old super-board runtime files"
[ -f "$P6/docs/super-board/runs/issue-1/summary.md" ] \
  && [ -f "$P6/docs/super-board/runs/2020-01-01-workers/tracked.md" ] \
  && [ -f "$P6/docs/super-board/runs/${TODAY}-workers/worker.log" ] \
  && [ -f "$P6/docs/super-board/runs/keep-unignored/note.md" ] \
  && [ -f "$P6/.git/super-board/last-merge-verify-pr-11.log" ] \
  && [ -f "$P6/.claude/super-board/last-merge-verify-pr-21.log" ] \
  && ok "devkit_clean preserves tracked files, unignored dirs, and fresh/today runtime logs" \
  || fail "devkit_clean deleted protected or fresh files"

# (h2) #547: worktree phụ (.git là file) tìm đúng commondir để xoá .git/super-board/*.log cũ, giữ YYYY-MM-DD-<slug>-workers hôm nay (kể cả mtime cũ),
# không văng lỗi khi gặp thư mục con chỉ đọc, và lọc sạch toàn bộ GIT_* (kể cả GIT_CONFIG_COUNT / core.excludesFile / core.fsmonitor).
P6_OTHER="$TMP/p6_other"; P6_WT="$TMP/p6_wt"
mkdir -p "$P6_OTHER"
printf 'docs/super-board/runs/keep-unignored/\n' > "$TMP/decoy_excludes"
printf '#!/bin/sh\necho PWNED > "%s/fsm_ran"\n' "$TMP" > "$TMP/fsm.sh" && chmod +x "$TMP/fsm.sh"
( cd "$P6_OTHER" && git init -q . && printf 'docs/super-board/runs/*-workers/\n' > .gitignore && git add .gitignore && git -c user.email=a@b -c user.name=a commit -qm init )
( cd "$P6" && git -c user.email=a@b -c user.name=a commit --allow-empty -qm "base" && git worktree add -q "$P6_WT" -b wt-clean-check )
mkdir -p "$P6_WT/docs/super-board/runs/2020-01-03-workers" \
         "$P6_WT/docs/super-board/runs/2020-01-04-workers/ro_sub" \
         "$P6_WT/docs/super-board/runs/${TODAY}-myboard-workers" \
         "$P6_WT/docs/super-board/runs/keep-unignored" \
         "$P6/.git/super-board"
echo "tracked in wt" > "$P6_WT/docs/super-board/runs/2020-01-03-workers/must_keep.md"
echo "ro worker" > "$P6_WT/docs/super-board/runs/2020-01-04-workers/ro_sub/w.log"
echo "unignored in wt" > "$P6_WT/docs/super-board/runs/keep-unignored/keep.md"
( cd "$P6_WT" && git add -f docs/super-board/runs/2020-01-03-workers/must_keep.md )
echo "writing live today" > "$P6_WT/docs/super-board/runs/${TODAY}-myboard-workers/live.log"
chmod 555 "$P6_WT/docs/super-board/runs/2020-01-04-workers/ro_sub"
touch -t 202001010000 \
  "$P6_WT/docs/super-board/runs/2020-01-03-workers/must_keep.md" "$P6_WT/docs/super-board/runs/2020-01-03-workers" \
  "$P6_WT/docs/super-board/runs/2020-01-04-workers/ro_sub/w.log" "$P6_WT/docs/super-board/runs/2020-01-04-workers/ro_sub" "$P6_WT/docs/super-board/runs/2020-01-04-workers" \
  "$P6_WT/docs/super-board/runs/${TODAY}-myboard-workers/live.log" "$P6_WT/docs/super-board/runs/${TODAY}-myboard-workers" \
  "$P6_WT/docs/super-board/runs/keep-unignored/keep.md" "$P6_WT/docs/super-board/runs/keep-unignored"
echo "old commondir verify log" > "$P6/.git/super-board/last-merge-verify-pr-30.log"
touch -t 202001010000 "$P6/.git/super-board/last-merge-verify-pr-30.log"
GIT_DIR="$P6_OTHER/.git" GIT_WORK_TREE="$P6_WT" \
  GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0="$TMP/decoy_excludes" \
  GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1="$TMP/fsm.sh" \
  python3 -I "$DEVKIT_DIR/scripts/governance/devkit_clean.py" "$P6_WT" --days=7 --apply --keep-state >/dev/null 2>&1; wt_rc=$?
chmod -R u+rwX "$P6_WT/docs/super-board/runs/2020-01-04-workers" 2>/dev/null || true
[ "$wt_rc" = 0 ] \
  && [ -f "$P6_WT/.git" ] \
  && [ ! -e "$P6/.git/super-board/last-merge-verify-pr-30.log" ] \
  && [ ! -e "$P6_WT/docs/super-board/runs/2020-01-04-workers" ] \
  && [ -f "$P6_WT/docs/super-board/runs/2020-01-03-workers/must_keep.md" ] \
  && [ -f "$P6_WT/docs/super-board/runs/${TODAY}-myboard-workers/live.log" ] \
  && [ -f "$P6_WT/docs/super-board/runs/keep-unignored/keep.md" ] \
  && [ ! -f "$TMP/fsm_ran" ] \
  && ok "linked worktree (.git file) cleans commondir log + ro_sub workers, scrubs GIT_*/GIT_CONFIG_*, keeps YYYY-MM-DD-<slug>-workers, and ignores fsmonitor" \
  || fail "linked worktree / GIT_* scrub check failed (rc=$wt_rc, log30=$([ -e "$P6/.git/super-board/last-merge-verify-pr-30.log" ] && echo y || echo n), ro04=$([ -e "$P6_WT/docs/super-board/runs/2020-01-04-workers" ] && echo y || echo n), tracked=$([ -f "$P6_WT/docs/super-board/runs/2020-01-03-workers/must_keep.md" ] && echo y || echo n), today=$([ -f "$P6_WT/docs/super-board/runs/${TODAY}-myboard-workers/live.log" ] && echo y || echo n), unig=$([ -f "$P6_WT/docs/super-board/runs/keep-unignored/keep.md" ] && echo y || echo n), fsm=$([ -f "$TMP/fsm_ran" ] && echo y || echo n))"

# (h3) #547: thư mục super-board không đọc được (chmod 000) ghi cảnh báo "clean: cannot read" ra stderr, vẫn exit 0 và dọn sạch các mục khác.
P6_UNREAD="$TMP/p6_unread"
mkdir -p "$P6_UNREAD/.claude/super-board" \
         "$P6_UNREAD/.claude/audit-gate" \
         "$P6_UNREAD/docs/super-board/runs/2020-01-05-workers"
cat > "$P6_UNREAD/.gitignore" <<'GI'
.claude/super-board/last-merge-verify-pr-*.log
docs/super-board/runs/*-workers/
GI
( cd "$P6_UNREAD" && git init -q . && git add .gitignore && git -c user.email=t@t -c user.name=t commit -qm init )
mkdir -p "$P6_UNREAD/.git/super-board"
echo "blocked log" > "$P6_UNREAD/.claude/super-board/last-merge-verify-pr-99.log"
echo "old git log" > "$P6_UNREAD/.git/super-board/last-merge-verify-pr-40.log"
echo "old worker" > "$P6_UNREAD/docs/super-board/runs/2020-01-05-workers/w.log"
echo "old audit" > "$P6_UNREAD/.claude/audit-gate/old_hook.log"
touch -t 202001010000 \
  "$P6_UNREAD/.claude/super-board/last-merge-verify-pr-99.log" \
  "$P6_UNREAD/.git/super-board/last-merge-verify-pr-40.log" \
  "$P6_UNREAD/docs/super-board/runs/2020-01-05-workers/w.log" \
  "$P6_UNREAD/docs/super-board/runs/2020-01-05-workers" \
  "$P6_UNREAD/.claude/audit-gate/old_hook.log"
chmod 000 "$P6_UNREAD/.claude/super-board"
python3 -I "$DEVKIT_DIR/scripts/governance/devkit_clean.py" "$P6_UNREAD" --days=7 --apply --keep-state >"$TMP/h3.out" 2>"$TMP/h3.err"; h3_rc=$?
chmod 700 "$P6_UNREAD/.claude/super-board" 2>/dev/null || true
if [ "$h3_rc" = 0 ] \
   && grep -qF "clean: cannot read" "$TMP/h3.err" \
   && [ ! -e "$P6_UNREAD/.git/super-board/last-merge-verify-pr-40.log" ] \
   && [ ! -e "$P6_UNREAD/docs/super-board/runs/2020-01-05-workers" ] \
   && [ ! -e "$P6_UNREAD/.claude/audit-gate/old_hook.log" ]; then
  ok "unreadable super-board dir (chmod 000) logs 'clean: cannot read' to stderr, exits 0, and cleans remaining items"
else
  fail "unreadable super-board dir check failed (rc=$h3_rc, err='$(cat "$TMP/h3.err")')"
fi

# (i) #547: scratch_cleanup.py --prune gọi devkit_clean (--days=7 --apply --keep-state) tối đa 1 lần mỗi 24h cho từng repo, giữ state.
P7="$TMP/p7"; A7="$P7/.claude/audit-gate"; SR7="$TMP/sr7"; CP7="$TMP/cp7"; TT7="$TMP/tt7"
mkdir -p "$A7" "$P7/.agents" "$SR7" "$CP7" "$TT7"
( cd "$P7" && git init -q . && git config devkit.trunkMode false )
echo "old" > "$A7/old1.log"; touch -t 202001010000 "$A7/old1.log"
echo "{}" > "$A7/approved.json"; touch -t 202001010000 "$A7/approved.json"
echo "owed" > "$A7/worktree_merge_gate.state"; touch -t 202001010000 "$A7/worktree_merge_gate.state"
echo "1" > "$A7/.testsourceset_attempts_s1"; touch -t 202001010000 "$A7/.testsourceset_attempts_s1"
DEVKIT_SCRATCH_ROOT="$SR7" DEVKIT_CLAUDE_PROJECTS="$CP7" DEVKIT_TEST_TMP_ROOT="$TT7" DEVKIT_CLEAN_PROJECT="$P7" \
  python3 -I "$DEVKIT_DIR/scripts/governance/scratch_cleanup.py" --prune --keep 00000000-0000-4000-8000-000000000000 >/dev/null 2>&1
[ ! -e "$A7/old1.log" ] && [ -f "$A7/approved.json" ] && [ -f "$A7/worktree_merge_gate.state" ] && [ -f "$A7/.testsourceset_attempts_s1" ] \
  && ok "scratch_cleanup --prune runs devkit_clean (--keep-state) and keeps *.json / *.state / .testsourceset_attempts*" \
  || fail "scratch_cleanup --prune did not run devkit_clean --keep-state: $(ls -a "$A7" | tr '\n' ' ')"
echo "old2" > "$A7/old2.log"; touch -t 202001010000 "$A7/old2.log"
DEVKIT_SCRATCH_ROOT="$SR7" DEVKIT_CLAUDE_PROJECTS="$CP7" DEVKIT_TEST_TMP_ROOT="$TT7" DEVKIT_CLEAN_PROJECT="$P7" \
  python3 -I "$DEVKIT_DIR/scripts/governance/scratch_cleanup.py" --prune --keep 00000000-0000-4000-8000-000000000000 >/dev/null 2>&1
[ ! -e "$A7/old1.log" ] && [ -f "$A7/old2.log" ] \
  && ok "scratch_cleanup --prune throttles devkit_clean to at most once per 24h per repo" \
  || fail "scratch_cleanup --prune ran devkit_clean twice within 24h (or never ran)"

# (i2) #547: khi devkit_clean trả mã khác 0, prune_project_runtime ghi ngữ cảnh lỗi vào cả stderr lẫn devkit-scratch-cleanup.log
FAKE_GOV="$TMP/fake_gov"; mkdir -p "$FAKE_GOV"
cp "$DEVKIT_DIR/scripts/governance/scratch_cleanup.py" "$FAKE_GOV/scratch_cleanup.py"
printf '#!/usr/bin/env python3\nimport sys\nsys.stderr.write("simulated clean boom\\n")\nsys.exit(3)\n' > "$FAKE_GOV/devkit_clean.py"
rm -f "$SR7"/.devkit-clean-* "$SR7/devkit-scratch-cleanup.log"
DEVKIT_SCRATCH_ROOT="$SR7" DEVKIT_CLAUDE_PROJECTS="$CP7" DEVKIT_TEST_TMP_ROOT="$TT7" DEVKIT_CLEAN_PROJECT="$P7" \
  python3 -I "$FAKE_GOV/scratch_cleanup.py" --prune --keep 00000000-0000-4000-8000-000000000000 >"$TMP/p7_err.out" 2>&1
grep -q "devkit_clean failed.*rc=3.*simulated clean boom" "$TMP/p7_err.out" \
  && grep -q "devkit_clean failed.*rc=3.*simulated clean boom" "$SR7/devkit-scratch-cleanup.log" 2>/dev/null \
  && ok "prune_project_runtime logs non-zero devkit_clean exit with context to both stderr and cleanup log" \
  || fail "prune_project_runtime missed stderr/log context: err='$(cat "$TMP/p7_err.out")' log='$(cat "$SR7/devkit-scratch-cleanup.log" 2>/dev/null || true)'"

if [ "$FAILS" -ne 0 ]; then echo "governance cleanup/fold/intent: $FAILS FAILED"; exit 1; fi
echo "governance cleanup/fold/intent: all checks passed"
