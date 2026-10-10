#!/usr/bin/env bash
# Test for skills/devkit-audit/scripts/devkit_metrics.py: the daily DevKit audit needs the same numbers every day, read-only, in one command
# (2026-10-10: the analysis was written by hand twice in one session). Checks the numbers on a fixture run log with known answers: hook share,
# a hook run that repeats the previous hook run's state within 30 minutes (same exit, n_changed and per-suite verdicts), the overhead outside
# the suites, the top suites, the checklist header, the context sizes, a repo with no log, malformed log lines, and that nothing in the repo changes.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
M="$DEVKIT_DIR/skills/devkit-audit/scripts/devkit_metrics.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
[ -f "$M" ] || { echo "✖ missing $M"; echo "❌ test_devkit_metrics: script not found"; exit 1; }

R="$TMP/repo"; mkdir -p "$R/.git" "$R/.agents/context"
( cd "$R" && git init -q . && git config user.email t@t && git config user.name t && echo x > a.txt && git add a.txt && git commit -qm init )
mkdir -p "$R/.git/postfix-gate"
printf '%s\n' '# AGENTS' > "$R/AGENTS.md"
printf '%s\n' 'profile rules' > "$R/.agents/context/profile-rules.md"
printf '%s\n' '# 🧪 Regression Checklist' '' '**An toàn 93% (41/44)** · ❌ 0 · 🔁 0 · ⏳ 3 chờ · 🟡 REPORTED 0' '' '**Bug không có test hồi quy nào chặn tái phát: 2** (1 chưa có test · 1 có test nhưng gate không chạy)' > "$R/.agents/CHECKLIST.md"
python3 - "$R/.git/postfix-gate/runs.jsonl" <<'PY'
import json, sys, time
now = int(time.time())
def run(dt, src, mode, exit_, n, suites, total, verdict):
    sw = round(sum(s[2] for s in suites if s[2] is not None), 2)
    return {"v": 1, "epoch": now - dt, "ts": "x", "source": src, "mode": mode, "exit": exit_, "verdict": verdict, "n_changed": n,
            "docs_only": False, "no_test_only": False, "deferred": False, "busy": False, "reused_full_pass": False, "suites": suites, "suites_wall_s": sw, "total_wall_s": total}
FAIL = [["A", "FAIL", 100.0]]
rows = [
    run(9000, "hook", "impacted", 1, 3, FAIL, 120.0, "FAIL"),
    run(8700, "hook", "impacted", 1, 3, FAIL, 120.0, "FAIL"),     # repeat 1 (300 s later, same state)
    run(8400, "hook", "impacted", 1, 3, FAIL, 120.0, "FAIL"),     # repeat 2
    run(4000, "hook", "impacted", 1, 3, FAIL, 120.0, "FAIL"),     # same state but 4400 s later: not a repeat
    run(3000, "cli", "full", 0, 2, [["A", "PASS", 50.0], ["B", "PASS", 10.0]], 70.0, "PASS"),
    run(2000, "hook", "impacted", 2, 1, [["A", "PASS", 10.0]], 15.0, "UNTESTED"),
    run(1700, "hook", "impacted", 2, 1, [["A", "PASS", 10.0]], 15.0, "UNTESTED"),   # repeat 3
]
with open(sys.argv[1], "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
    f.write("not json\n")
    f.write('{"v": 2, "epoch": 1}\n')
PY
# Stop-hook logs (the real formats of <repo>/.claude/audit-gate/*.log): one line per Stop event in testsourceset_gate.log ([SID=…]), a line
# starting with BLOCK / block is a block, an old line (40 days) is outside the window
mkdir -p "$R/.claude/audit-gate"
python3 - "$R/.claude/audit-gate" <<'PY'
import os, sys, time
d = sys.argv[1]
def stamp(dt): return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - dt))
def write(name, rows):
    with open(os.path.join(d, name), "w") as f:
        f.write("\n".join(rows) + "\n")
# one Stop event writes SEVERAL lines in testsourceset_gate.log (same second); the BLOCK line shares the second of the first s1 event
ev = [(3000 - 100 * i, "s1") for i in range(5)] + [(1000 - 100 * i, "s2") for i in range(2)]
lines = []
for dt, sid in ev:
    lines += [f"{stamp(dt)} [SID={sid}] SCOPE — repo-wide", f"{stamp(dt)} [SID={sid}] SKIP — no ./gradlew", f"{stamp(dt)} [SID={sid}] PASS — x"]
lines.append(f"{stamp(3000)} [SID=s1] BLOCK — compile failed")
lines.append(f"{stamp(2900)} [SID=s1] RELEASE after 3 attempts — x")
lines.append(f"{stamp(2800)} [SID=s1] BLOCK suppressed after 3 attempts (anti-loop) — x")
lines.append(f"{stamp(2700)} [SID=s1] BLOCK re-used (tree unchanged fp=abc) — no compile")
lines.append(f"{stamp(2700)} [SID=s1] BLOCK (attempt 2, re-used) — x")
write("testsourceset_gate.log", lines)
write("proof_gate.log", [f"[{stamp(40 * 86400)}] block session=s1 attempt=9 cited=- gate=ok"] +
                        [f"[{stamp(2000 - 100 * i)}] block session=s1 attempt={i + 1} cited=- gate=ok" for i in range(3)] +
                        [f"[{stamp(900)}] pass session=s2", f"[{stamp(800)}] pass session=s2"])
write("test_evidence_gate.log", [f"[{stamp(2500)}] BLOCK — problems=1 repeat=[] redcheck=[] check7=False", f"[{stamp(2400)}] BLOCK — problems=0 repeat=[] redcheck=['T'] check7=False",
                                 f"[{stamp(2300)}] RELEASED on re-Stop #2 — claim still unverified", f"[{stamp(2200)}] reminder (once per session) — x"])
# the first three lines carry the fingerprint of the hook runs r1, r2, r3 (same seconds as their runs.jsonl records): r1 and r2 the same tree, r3 another
write("regression_gate.log", [f"{stamp(9000)} block fp=AAA attempt=1 exit=1", f"{stamp(8700)} block fp=AAA attempt=2 exit=1", f"{stamp(8400)} block fp=BBB attempt=1 exit=1",
                              f"{stamp(2600)} block fp=abc attempt=4 exit=2",
                              f"{stamp(700)} block fp=CCC attempt=1 exit=2", f"{stamp(700)} release: session cap sid=s1 blocks=3", f"{stamp(500)} pass fp=abc exit=0", f"{stamp(400)} skip: work in progress (status line 'x') sid=s1"])
write("claim_check.log", [f"[{stamp(1900)}] BLOCK — unsourced citations: [] | unbacked past-actions: ['build']", f"[{stamp(1800)}] no citations / past-action claims — pass"])
write("review_gate.log", [f"[{stamp(1700)}] BLOCK (attempt 1/3) — unreviewed code: ['a.py']", f"[{stamp(1600)}] BLOCK (attempt 2/3) — unreviewed code: ['a.py']",
                          f"[{stamp(1550)}] BLOCK suppressed after 3 attempts (anti-loop) — x", f"[{stamp(1500)}] no uncommitted code (.py|.go) — pass"])
write("security_gate.log", [f"[{stamp(1400)}] flagged=0 unreviewed=0 — pass", f"[{stamp(1300)}] BLOCK — unreviewed=['x'] attempt=1", f"[{stamp(1290)}] BLOCK — unreviewed=['x'] attempt=2", f"[{stamp(1280)}] RELEASE after 3 reminders — x"])
PY
# a repo of hostile data: one good run, an epoch that overflows, a NaN wall time, malformed suites, a 200000-deep nesting, parallel suites (the
# suites add up to more than the wall time)
R2="$TMP/hostile"; mkdir -p "$R2/.git" && ( cd "$R2" && git init -q . ) && mkdir -p "$R2/.git/postfix-gate"
python3 - "$R2/.git/postfix-gate/runs.jsonl" <<'PY'
import json, sys, time
now = int(time.time())
BASE = {"v": 1, "mode": "impacted", "verdict": "PASS", "docs_only": False, "no_test_only": False, "deferred": False, "busy": False, "reused_full_pass": False}
good = {**BASE, "epoch": now - 100, "source": "hook", "exit": 0, "n_changed": 1, "suites": [["X", "PASS", 5.0]], "suites_wall_s": 5.0, "total_wall_s": 6.0}
nan = {**BASE, "epoch": now - 60, "source": "hook", "exit": 0, "n_changed": 1, "suites": [[["x"], "PASS", 1]], "total_wall_s": float("nan")}
par = {**BASE, "epoch": now - 30, "source": "cli", "mode": "full", "exit": 0, "n_changed": 2, "suites": [["P", "PASS", 60.0], ["Q", "PASS", 60.0]], "suites_wall_s": 120.0, "total_wall_s": 50.0}
listy = {**BASE, "epoch": now - 20, "source": "hook", "exit": 0, "n_changed": 1, "suites": [["P", ["x"], 1.0]], "suites_wall_s": 1.0, "total_wall_s": 2.0}
runA = {**BASE, "epoch": now - 400, "source": "hook", "exit": 0, "n_changed": 5, "suites": [["Y", "PASS", 1.0]], "suites_wall_s": 1.0, "total_wall_s": 2.0}
runB = {**runA, "epoch": now - 300}
runC = {**runA, "epoch": now - 250, "n_changed": 6}
with open(sys.argv[1], "w") as f:
    f.write(json.dumps(good) + "\n")
    f.write(json.dumps(listy) + "\n")
    f.write(json.dumps(runA) + "\n")
    f.write(json.dumps(runB) + "\n")
    f.write(json.dumps(runC) + "\n")
    f.write('{"v": 1, "epoch": 1e20, "source": "hook", "exit": 0, "n_changed": 1}\n')
    f.write(json.dumps(nan) + "\n")
    f.write("[" * 200000 + "\n")
    f.write(json.dumps(par) + "\n")
PY
mkdir -p "$R2/.claude/audit-gate" && printf '%s block fp=ZZZ attempt=1 exit=1\n' "$(python3 -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - 400)))')" > "$R2/.claude/audit-gate/regression_gate.log"
# a 18 MB log whose newest lines are at the END: only the tail may be read
R3="$TMP/biglog"; mkdir -p "$R3/.claude/audit-gate" && ( cd "$R3" && git init -q . )
python3 - "$R3/.claude/audit-gate/testsourceset_gate.log" <<'PY'
import sys, time
old = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - 40 * 86400))
with open(sys.argv[1], "w") as f:
    for i in range(300000):
        f.write(f"{old} [SID=old{i % 7}] SKIP — no ./gradlew padding padding padding\n")
    for i in range(10):
        f.write(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - 10 * i)) + " [SID=new] SKIP — no ./gradlew\n")
PY
snap() {   # a hash of every file's path and content in the tree, .git included
  python3 -I - "$1" <<'PY'
import hashlib, os, sys
h = hashlib.sha256()
for root, dirs, files in os.walk(sys.argv[1]):
    dirs.sort()
    for f in sorted(files):
        p = os.path.join(root, f)
        h.update(os.path.relpath(p, sys.argv[1]).encode())
        try:
            h.update(open(p, "rb").read())
        except OSError:
            pass
print(h.hexdigest())
PY
}
before="$(snap "$R")"

python3 -I "$M" --repo "$R" --since-days 30 --json > "$TMP/out.json" 2> "$TMP/err"; rc=$?
[ "$rc" = 0 ] && ok "runs and exits 0" || fail "exit $rc: $(head -c 300 "$TMP/err")"
check() {   # check <label> <python expression over d (the repo's record)>
  if python3 -I - "$TMP/out.json" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["repos"][0]
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
  then ok "$1"; else fail "$1 — got: $(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1]))["repos"][0]; print({k: d.get(k) for k in ("gate","checklist","sizes")})' "$TMP/out.json" 2>&1 | head -c 600)"; fi
}
check "7 valid runs, 2 malformed lines ignored"          "d['gate']['runs'] == 7 and d['gate']['ignored'] == 2"
check "hook runs: 6 of 7"                                 "d['gate']['hook_runs'] == 6"
check "wall: 120*4 + 70 + 15*2 = 580 s = 9.67 min"        "abs(d['gate']['wall_min'] - 9.67) < 0.01"
check "hook wall 510 s = 8.5 min, share 88%"              "abs(d['gate']['hook_wall_min'] - 8.5) < 0.01 and d['gate']['hook_share_pct'] == 88"
check "2 hook runs repeat: r2 (same fingerprint) 120 s and r7 (no fingerprint, same state) 15 s; r3 differs by fingerprint although the proxy matches" "d['gate']['repeat']['runs'] == 2 and abs(d['gate']['repeat']['wall_min'] - 2.25) < 0.01"
check "three hook runs have a fingerprint from regression_gate.log" "d['gate']['fp_known_runs'] == 3"
check "repeats split by exit code: 1 at exit 1, 1 at exit 2" "d['gate']['repeat']['by_exit']['1']['runs'] == 1 and d['gate']['repeat']['by_exit']['2']['runs'] == 1"
check "overhead outside the suites: median 20 s, n=7, none negative" "d['gate']['overhead_s']['p50'] == 20.0 and d['gate']['overhead_s']['n'] == 7 and d['gate']['overhead_s']['negative'] == 0"
check "top suite is A: 7 runs, FAIL x4 PASS x3"           "d['gate']['top_suites'][0]['id'] == 'A' and d['gate']['top_suites'][0]['status'] == {'FAIL': 4, 'PASS': 3}"
check "checklist header parsed: 93% 41/44, 3 waiting, 2 bugs without a guard" "d['checklist'] == {'safe_pct': 93, 'passed': 41, 'total': 44, 'waiting': 3, 'no_guard': 2}"
check "context sizes: AGENTS.md + profile rules in bytes" "d['sizes']['agents_md'] == 9 and d['sizes']['profile_rules'] == 14"
check "git: a branch name, nothing dirty, 3 untracked entries" "bool(d['git']['branch']) and d['git']['dirty'] == 0 and d['git']['untracked'] == 3"
check "lock status is reported"                           "d['lock']['exit'] in (0, 3)"

check "Stop events: 7 (sid, second) pairs although 22 log lines, 2 sessions" "d['stop']['events'] == 7 and d['stop']['sessions'] == 2"
check "events per session: median 3.5, max 5"              "d['stop']['per_session'] == {'median': 3.5, 'max': 5}"
check "events by day: the local days of the seven offsets" "d['stop']['by_day'] == dict(__import__('collections').Counter(__import__('time').strftime('%Y-%m-%d', __import__('time').localtime(__import__('time').time() - dt - 5)) for dt in (3000, 2900, 2800, 2700, 2600, 1000, 900))) or sum(d['stop']['by_day'].values()) == 7 and len(d['stop']['by_day']) == 2"
check "real blocks per hook: a stop the hook let go (attempt above 2, suppressed, RELEASED) is a release, not a block; 40-day-old lines are outside" "d['stop']['blocks'] == {'claim_check': 1, 'proof_gate': 2, 'regression_gate': 3, 'review_gate': 2, 'security_gate': 2, 'test_evidence_gate': 2, 'testsourceset_gate': 2}"
check "releases per hook" "d['stop']['released'] == {'proof_gate': 1, 'regression_gate': 2, 'review_gate': 1, 'security_gate': 1, 'test_evidence_gate': 1, 'testsourceset_gate': 2}"
check "real blocks total 14, 2.0 per Stop event"          "d['stop']['blocks_total'] == 14 and d['stop']['blocks_per_event'] == 2.0"

after="$(snap "$R")"
[ "$before" = "$after" ] && ok "read-only: the repo is unchanged" || fail "the script changed the repo"

E="$TMP/empty"; mkdir -p "$E" && ( cd "$E" && git init -q . )
python3 -I "$M" --repo "$E" --json > "$TMP/empty.json" 2>&1; rc=$?
{ [ "$rc" = 0 ] && python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1]))["repos"][0]; assert d["gate"]["runs"] == 0 and d["checklist"] is None and d["stop"]["events"] == 0 and d["stop"]["blocks_total"] == 0' "$TMP/empty.json"; } \
  && ok "a repo with no run log and no checklist: zeros, no crash" || fail "empty repo: exit $rc: $(head -c 300 "$TMP/empty.json")"
python3 -I "$M" --repo "$R" --since-days 30 > "$TMP/human.txt" 2>&1
grep -q 'repeat' "$TMP/human.txt" && ok "the human table mentions repeats" || fail "human output lacks the repeat line"
grep -q 'Stop' "$TMP/human.txt" && ok "the human table has the Stop-hook line" || fail "human output lacks the Stop-hook line"

python3 -I "$M" --repo "$R2" --repo "$R3" --repo "$TMP/does-not-exist" --since-days 30 --json > "$TMP/multi.json" 2> "$TMP/multi.err"; rc=$?
[ "$rc" = 0 ] && ok "hostile data, a big log and a missing path: exit 0, no traceback" || fail "exit $rc: $(tail -3 "$TMP/multi.err" | tr '\n' ' ')"
checkm() {   # checkm <label> <python expression over m = the list of repo records>
  if python3 -I - "$TMP/multi.json" "$2" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))["repos"]
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
  then ok "$1"; else fail "$1 — got: $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["repos"][0].get("gate"))' "$TMP/multi.json" 2>&1 | head -c 500)"; fi
}
checkm "hostile repo: the good, the odd-suite and the parallel run counted; epoch 1e20, NaN wall time and the 200000-deep line ignored" "m[0]['gate']['runs'] == 6 and m[0]['gate']['ignored'] == 3"
checkm "overhead: the parallel run (suites > wall) is left out and counted as negative" "m[0]['gate']['overhead_s'] == {'p50': 1.0, 'p90': 1.0, 'n': 5, 'negative': 1}"
checkm "a hook run with a fingerprint and the next one without are not a repeat (same exit, count and verdicts)" "m[0]['gate']['repeat']['runs'] == 0 and m[0]['gate']['fp_known_runs'] == 1"
checkm "an 18 MB log: the tail is read, 10 recent events found (not 0 from the old head)" "m[1]['stop']['events'] == 10"
checkm "a missing path still yields a record, the other repos are intact" "len(m) == 3 and m[2]['gate']['runs'] == 0"

# a symlinked audit-gate (it points outside the repo), a log line dated year 9999, and a corrupt git index
R4="$TMP/linked"; mkdir -p "$R4/.claude" "$TMP/outside" && ( cd "$R4" && git init -q . ) && ln -s "$TMP/outside" "$R4/.claude/audit-gate"
python3 - "$TMP/outside/testsourceset_gate.log" <<'PY'
import sys, time
with open(sys.argv[1], "w") as f:
    for i in range(3):
        f.write(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - 60 * i)) + " [SID=lnk] SKIP — x\n")
PY
R5="$TMP/future"; mkdir -p "$R5/.claude/audit-gate" && ( cd "$R5" && git init -q . )
python3 - "$R5/.claude/audit-gate/testsourceset_gate.log" <<'PY'
import sys, time
with open(sys.argv[1], "w") as f:
    f.write("9999-12-31T23:59:59 [SID=far] SKIP — x\n")
    f.write(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - 5)) + " [SID=now] SKIP — x\n")
PY
R6="$TMP/corrupt"; mkdir -p "$R6" && ( cd "$R6" && git init -q . ) && printf 'garbage' > "$R6/.git/index"
R4b="$TMP/linked2"; mkdir -p "$R4b" "$TMP/outside2/audit-gate" && ( cd "$R4b" && git init -q . ) && ln -s "$TMP/outside2" "$R4b/.claude"
python3 - "$TMP/outside2/audit-gate/testsourceset_gate.log" <<'PY'
import sys, time
with open(sys.argv[1], "w") as f:
    f.write(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - 30)) + " [SID=lnk2] SKIP — x\n")
PY
R7="$TMP/orphan"; mkdir -p "$R7/.claude/audit-gate" && ( cd "$R7" && git init -q . )
python3 - "$R7/.claude/audit-gate" <<'PY'
import os, sys, time
t = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - 30))
open(os.path.join(sys.argv[1], "testsourceset_gate.log"), "w").write(t + " [SID=o] SKIP — x\n")
open(os.path.join(sys.argv[1], "claim_check.log"), "w").write("[" + t + "] RELEASED on re-Stop #2 — claim still unverified\n")
PY
python3 -I "$M" --repo "$R4" --repo "$R5" --repo "$R6" --repo "$R4b" --repo "$R7" --since-days 30 --json > "$TMP/multi2.json" 2>> "$TMP/multi.err"; rc=$?
[ "$rc" = 0 ] && ok "symlinked audit-gate, a year-9999 line and a corrupt index: exit 0" || fail "exit $rc: $(tail -3 "$TMP/multi.err" | tr '\n' ' ')"
checkm2() {
  if python3 -I - "$TMP/multi2.json" "$2" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))["repos"]
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
  then ok "$1"; else fail "$1 — got: $(python3 -I -c 'import json,sys; print([(r.get("stop") or {}).get("events") for r in json.load(open(sys.argv[1]))["repos"]], [(r.get("git") or {}).get("dirty") for r in json.load(open(sys.argv[1]))["repos"]])' "$TMP/multi2.json" 2>&1 | head -c 300)"; fi
}
checkm2 "a symlinked audit-gate folder is not read (its log is outside the repo)" "m[0]['stop']['events'] == 0"
checkm2 "a link as the .claude folder itself is not read either" "m[3]['stop']['events'] == 0 and m[3]['sizes']['audit_gate_dir'] is None"
checkm2 "a RELEASED line with no block before it: no negative count (clamped), counted as a release" "m[4]['stop']['blocks'] == {} and m[4]['stop']['released'] == {'claim_check': 1}"
checkm2 "a log line dated year 9999 is not an event" "m[1]['stop']['events'] == 1"
checkm2 "a git failure is reported as unknown, not as a clean tree" "m[2]['git']['dirty'] is None and m[2]['git']['untracked'] is None"
for v in nan inf 1e400 0 -1; do
  python3 -I "$M" --repo "$R" --since-days "$v" --json > /dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && ok "--since-days $v is refused (exit 2)" || fail "--since-days $v: exit $rc, want 2"
done
python3 -I - "$M" <<'PY' && ok "the script keeps Python from writing bytecode into the kit" || fail "sys.dont_write_bytecode is False after importing the script (-I turns the env switch off)"
import sys
exec(compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec"), {"__file__": sys.argv[1], "__name__": "dm"})
sys.exit(0 if sys.dont_write_bytecode else 1)
PY

[ "$FAILS" -eq 0 ] && echo "✅ test_devkit_metrics: all passed" || { echo "❌ test_devkit_metrics: $FAILS failed"; exit 1; }
