#!/usr/bin/env bash
# #984 (a): ai giữ slot pool 'gate', giữ bao lâu, ở pha nào. Đo 01–04/11: p90 chờ của merge gate (steps.lock) 1283,5 s là chờ pool gate
# (test_run.lock của .merge-scratch-* là riêng từng scratch), nhưng runs.jsonl không ghi người giữ. Lượt gate giữ slot thật ghi trường
# gate_slot {repo, slot, n, prio, waited_s, t_acq, t_rel, held_s, outside_suites_s, released}; hết giờ chờ ghi {timed_out, waited_s};
# lượt không xin slot (cha đã giữ: DEVKIT_GATE_SLOT_HELD=1) không có trường. gate_speed_report.py in giây giữ theo loại lượt và theo repo
# (--holders-log thêm runs.jsonl của repo khác), và giây giữ trong lúc merge gate của log chính đang chờ.
# (h1) slot giữ thật, DEVKIT_SLOT_PRIORITY=merge: gate_slot đủ trường, t_acq ≤ t_rel, held_s ≥ thời gian suite
# (h2) DEVKIT_GATE_SLOT_HELD=1: không có gate_slot (dòng giữ nguyên bộ trường cũ)
# (h3) gate-1 bị giữ, DEVKIT_GATE_SLOT_WAIT_S=1: lượt BUSY ghi gate_slot.timed_out và waited_s, không có t_acq
# (r1) báo cáo trên 2 log giả: giây giữ theo loại (merge/task/stop/full) và theo repo, giây giữ trong lúc merge gate chờ
# (r2) log kiểu cũ (không gate_slot): không in mục người giữ
# Tương thích bash 3.2 và Python 3.9; chỉ stdlib.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
REPORT="$DEVKIT_DIR/scripts/governance/gate_speed_report.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-gate-slot-holder.XXXXXX")"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
HOLDER=""
cleanup() {
  touch "$TMP/release" 2>/dev/null || true
  [ -n "$HOLDER" ] && { kill "$HOLDER" 2>/dev/null || true; wait "$HOLDER" 2>/dev/null || true; }
  rm -rf "$TMP"
}
trap cleanup EXIT

FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

unset CLAUDE_PROJECT_DIR TARGET_DIR SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD DEVKIT_GATE_SLOTS DEVKIT_GATE_SLOT_WAIT_S \
      DEVKIT_SLOT_PRIORITY GATE_TOTAL_BUDGET_S DEVKIT_CAPACITY DEVKIT_CAPACITY_CORES DEVKIT_CAPACITY_LOAD DEVKIT_SLOT_ADVISORY_HELD \
      TEST_RUN_LOCK_BUSY_FAST
export WORKTREE_TRUNK_MODE=0
export VACUITY_REVERT=0
export SB_HEAVY_SLOT_DIR="$TMP/slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
printf '0\n' > "$TMP/load"
export DEVKIT_SLOT_LOAD_FILE="$TMP/load"
export SB_HEAVY_SLOT_POLL_S=0.05
export DEVKIT_GATE_SLOTS=1
export DEVKIT_SENTINEL_MAX_S=999999999

R="$TMP/repo"
make_repo() {
  rm -rf "$R" && mkdir -p "$R/src" "$R/.agents"
  git -C "$R" init -q -b main
  git -C "$R" config user.email t@example.invalid
  git -C "$R" config user.name t
  printf '.claude/\n' > "$R/.gitignore"
  printf '{"profile":"backend","lang":"vi"}\n' > "$R/.agents/active-profile.json"
  printf 'x = 1\n' > "$R/src/app.py"
  printf '#!/usr/bin/env bash\nsleep 1\nexit 0\n' > "$R/run_suite.sh"
  chmod +x "$R/run_suite.sh"
  cat > "$R/.agents/regression_matrix.active.json" <<JSON
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-H","name":"h","command":"bash run_suite.sh"}]}]}
JSON
  git -C "$R" add -A && git -C "$R" commit -qm init
  printf 'x = 2\n' > "$R/src/app.py"
}

last_line() {   # dòng cuối runs.jsonl của repo fixture (rỗng khi chưa có)
  tail -n 1 "$R/.git/postfix-gate/runs.jsonl" 2>/dev/null || true
}

# ── (h1) ──
make_repo
DEVKIT_SLOT_PRIORITY=merge CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/h1.out" 2>&1
rc=$?
H1="$(last_line)"
if python3 -I - "$H1" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
g = r.get("gate_slot")
assert isinstance(g, dict), "no gate_slot in %r" % sorted(r)
assert g.get("slot") == "gate-1" and g.get("n") == 1 and g.get("prio") == "merge", g
assert g.get("repo") == "repo", g
assert isinstance(g.get("t_acq"), (int, float)) and isinstance(g.get("t_rel"), (int, float)) and g["t_acq"] <= g["t_rel"], g
assert g.get("held_s", 0) >= 1.0, g
assert 0 <= g.get("outside_suites_s", -1) < g["held_s"], g
assert g.get("released") == "end" and isinstance(g.get("waited_s"), (int, float)) and "timed_out" not in g, g
PY
then
  ok "(h1) slot giữ thật: gate_slot ghi repo, slot, n, prio=merge, t_acq ≤ t_rel, held_s ≥ suite, released=end"
else
  fail "(h1) rc=$rc line=$H1 $(tail -4 "$TMP/h1.out" | tr '\n' ' ')"
fi

# ── (h2) ──
make_repo
DEVKIT_GATE_SLOT_HELD=1 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/h2.out" 2>&1
rc=$?
H2="$(last_line)"
if [ -n "$H2" ] && python3 -I -c 'import json,sys; r=json.loads(sys.argv[1]); sys.exit(0 if "gate_slot" not in r and r.get("suites") else 1)' "$H2"; then
  ok "(h2) cha đã giữ slot (DEVKIT_GATE_SLOT_HELD=1): dòng không có gate_slot"
else
  fail "(h2) rc=$rc line=$H2"
fi

# ── (h3) ──
make_repo
python3 - "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" <<'PY' &
import fcntl, os, sys, time
with open(sys.argv[1], "a") as fh:
    fcntl.flock(fh, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    end = time.monotonic() + 60
    while time.monotonic() < end and not os.path.exists(sys.argv[3]):
        time.sleep(0.03)
PY
HOLDER=$!
i=0
while [ ! -f "$TMP/held" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
DEVKIT_GATE_SLOT_WAIT_S=1 CLAUDE_PROJECT_DIR="$R" DEVKIT_SUITE_CACHE=0 \
  python3 "$GATE" --run-tests --full --json --no-checklist >"$TMP/h3.out" 2>&1
rc=$?
touch "$TMP/release"; wait "$HOLDER" 2>/dev/null || true; HOLDER=""
H3="$(last_line)"
if [ "$rc" -eq 4 ] && python3 -I - "$H3" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
g = r.get("gate_slot")
assert r.get("verdict") == "BUSY" and isinstance(g, dict), r
assert g.get("timed_out") is True and g.get("waited_s", 0) >= 0.9 and "t_acq" not in g and g.get("n") == 1, g
assert isinstance(g.get("t_gave_up"), (int, float)) and abs(g["t_gave_up"] - r["epoch"]) < 120, g
PY
then
  ok "(h3) hết giờ chờ slot: lượt BUSY ghi gate_slot.timed_out, waited_s, không t_acq"
else
  fail "(h3) rc=$rc line=$H3"
fi

# ── (r1) (r2): báo cáo ──
TZ=Asia/Ho_Chi_Minh python3 -I - "$REPORT" "$TMP" <<'PYEND'
import calendar, json, os, subprocess, sys
REPORT, TMP = sys.argv[1], sys.argv[2]
fails = 0


def chk(cond, good, why=""):
    global fails
    print(("✔ " if cond else "✖ ") + good + ("" if cond else ": " + why), flush=True)
    fails += 0 if cond else 1


T0 = calendar.timegm((2026, 11, 2, 3, 0, 0))   # 10:00 giờ VN


def rec(project, mode, source, end, wall, gs, merge_point=False, lock=0.0):
    return {"v": 1, "ts": "", "epoch": end, "project": project, "mode": mode, "source": source, "exit": 0, "verdict": "PASS",
            "fp": "f", "exit_reason": "pass", "deferred": False, "busy": False, "reused_full_pass": False, "n_changed": 1, "n_docs": 0,
            "docs_only": False, "no_test_only": False, "suites": [["X", "PASS", wall]], "suites_wall_s": wall, "force_full": False,
            "impacted_run": False, "merge_point": merge_point, "total_wall_s": wall, "steps": {"lock": lock}, "gate_slot": gs}


def slot(repo, a, b, waited=0.0):
    return {"repo": repo, "slot": "gate-1", "n": 2, "prio": "interactive", "waited_s": waited, "t_acq": a, "t_rel": b,
            "held_s": b - a, "outside_suites_s": 0.5, "released": "end"}


main = [
    # task gate giữ 1000 s từ T0
    rec("agent-workbench-r1", "scoped", "cli", T0 + 1000, 1000, slot("agent-workbench", T0, T0 + 1000)),
    # merge gate chờ 600 s (T0+200 → T0+800) rồi giữ 300 s
    rec(".merge-scratch-AAA", "scoped", "cli", T0 + 1100, 900, dict(slot("agent-workbench", T0 + 800, T0 + 1100, 600.0), prio="merge"),
        merge_point=True, lock=600.0),
    # Stop hook giữ 100 s, nightly full giữ 50 s (ngoài lúc merge chờ)
    rec("agent-workbench", "impacted", "hook", T0 + 2100, 100, slot("agent-workbench", T0 + 2000, T0 + 2100)),
    rec("agent-workbench", "full", "cli", T0 + 3050, 50, slot("agent-workbench", T0 + 3000, T0 + 3050)),
    # merge gate hết giờ chờ 100 s (T0+2000 → T0+2100) đúng lúc Stop hook giữ: BUSY, gate_slot.timed_out
    dict(rec(".merge-scratch-BBB", "scoped", "cli", T0 + 2110, 110, {"repo": "agent-workbench", "n": 2, "prio": "merge", "waited_s": 100.0,
                                                                   "timed_out": True, "t_gave_up": T0 + 2100}, merge_point=True,
             lock=100.0), verdict="BUSY", busy=True),
]
other = [
    # repo app giữ slot thứ hai 400 s, chồng 300 s lên lúc merge chờ (T0+500 → T0+900)
    rec("GeelyEx2", "impacted", "cli", T0 + 900, 400, slot("GeelyEx2", T0 + 500, T0 + 900)),
]
for name, rs in (("main.jsonl", main), ("other.jsonl", other)):
    with open(os.path.join(TMP, name), "w") as fh:
        for r in rs:
            fh.write(json.dumps(r) + "\n")
p = subprocess.run([sys.executable, REPORT, "--log", os.path.join(TMP, "main.jsonl"), "--holders-log", os.path.join(TMP, "other.jsonl"),
                    "--since", "2026-11-01", "--until", "2026-11-03"], capture_output=True, text=True)
out = p.stdout
lines = {l.split(":", 1)[0]: l for l in out.splitlines() if l.startswith("gate slot ")}
chk(p.returncode == 0, "(r1) báo cáo chạy với --holders-log", "rc=%d %s" % (p.returncode, p.stderr[-300:]))
kind = lines.get("gate slot held by kind", "")
chk("merge=300s" in kind and "task=1400s" in kind and "stop=100s" in kind and "full=50s" in kind,
    "(r1) giây giữ theo loại lượt (mọi log): merge 300, task 1400 (scoped + impacted cli, gồm repo app), stop 100, full 50", repr(kind))
repo = lines.get("gate slot held by repo", "")
chk("agent-workbench=1450s" in repo and "GeelyEx2=400s" in repo, "(r1) giây giữ theo repo, gồm repo của --holders-log", repr(repo))
mw = lines.get("gate slot held while a merge gate waited", "")
chk("waits=2" in mw and "timed_out=1" in mw and "wait=700s" in mw and "task=900s" in mw and "stop=100s" in mw
    and "agent-workbench=700s" in mw and "GeelyEx2=300s" in mw,
    "(r1) 2 lượt merge chờ 700 s (1 hết giờ): task giữ 900 s (600 workbench + 300 GeelyEx2), stop 100 s", repr(mw))
held = lines.get("gate slot held outside the suites step", "")
chk("2.5s" in held and "1850s" in held, "(r1) pha: giây giữ ngoài bước suites / tổng giây giữ", repr(held))
chk("merge gate (.merge-scratch-*): n=2" in out, "(r1) dòng chỉ số #983 vẫn in như cũ", out[-400:])
old = [dict(r) for r in main]
for r in old:
    r.pop("gate_slot")
with open(os.path.join(TMP, "old.jsonl"), "w") as fh:
    for r in old:
        fh.write(json.dumps(r) + "\n")
p = subprocess.run([sys.executable, REPORT, "--log", os.path.join(TMP, "old.jsonl"), "--since", "2026-11-01", "--until", "2026-11-03"],
                   capture_output=True, text=True)
chk(p.returncode == 0 and "gate slot " not in p.stdout, "(r2) log cũ không có gate_slot: không in mục người giữ", p.stdout[-300:])
sys.exit(1 if fails else 0)
PYEND
[ $? -eq 0 ] || FAILS=$((FAILS + 1))

echo
if [ "$FAILS" -eq 0 ]; then
  echo "✅ test_gate_slot_holder_log: tất cả PASS"
  exit 0
fi
echo "❌ test_gate_slot_holder_log: $FAILS FAIL"
exit 1
