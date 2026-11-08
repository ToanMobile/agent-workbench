#!/usr/bin/env bash
# Test hồi quy (05/11, chủ repo: "Hạn số merge gate chạy cùng lúc theo tải, để 3 gate không cùng tranh CPU").
# Đo thật 05/11 08:25–09:11: verify lạc quan (ngoài khoá merge) của #1007 và #1004 giữ cả 2 slot pool gate, verify TRONG khoá của #1009
# chờ slot 1662,9 s (runs.jsonl gate_slot.waited_s) trong lúc chặn mọi merge của repo; giây/test lúc chồng ≈ 1,9 × lúc chạy một mình.
# Luật mới (super-board-merge-gate.sh run_verify_cmd_inner): tải ≥ 2 × số lõi (capacity cores, v26 mục 10; SB_MERGE_OPT_LOAD_MAX ghi đè) thì verify lạc
# quan chỉ thấy N−1 slot của pool gate (N = DEVKIT_GATE_SLOTS / capacity gate_max ≥ 2): slot cuối để dành cho verify trong khoá; hết
# SB_MERGE_OPT_SLOT_WAIT_S (mặc định 900) vẫn bận thì chạy lại với cả pool — chờ có hạn rồi chạy, không bỏ verify.
#   1. tải cao, 3 merge gate cùng lúc (2 lạc quan + 1 bi quan giữ khoá): không lúc nào 2 verify lạc quan chạy suite cùng lúc; tối đa
#      N = 2 suite cùng lúc; cả 3 PR merge (exit 0)                                                       — ĐỎ trên main (2 lạc quan chồng)
#   2. tải cao, gate-1 bị giữ rồi nhả sau 3 s: verify lạc quan đợi gate-1, không lấy gate-2              — ĐỎ trên main (lấy gate-2 ngay)
#   3. tải cao, gate-1 bị giữ mãi, SB_MERGE_OPT_SLOT_WAIT_S=2: hết hạn thì chạy với cả pool (gate-2), merge — ĐỎ trên main (không có dòng log)
#   4. đối chứng tải thấp: gate-1 bị giữ ⇒ verify lạc quan lấy gate-2 ngay như cũ
#   5. đối chứng bi quan (SB_MERGE_OPTIMISTIC=0, verify trong khoá) tải cao: lấy gate-2 ngay, không bị hạn
# post-fix-gate.py THẬT trong verify_commands, khoá flock thật trong SB_HEAVY_SLOT_DIR riêng, tải giả qua SB_MERGE_LOAD_FILE (tải của
# merge gate) — DEVKIT_SLOT_LOAD_FILE = 0 để chờ tải mức suite của heavy_slot không chen vào. gh giả. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MERGE_GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
PFG="$ROOT/universal-agent-devkit/bin/post-fix-gate.py"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
unset CLAUDE_PROJECT_DIR TARGET_DIR SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD DEVKIT_GATE_SLOTS DEVKIT_GATE_SLOT_WAIT_S \
      DEVKIT_SLOT_PRIORITY DEVKIT_CAPACITY DEVKIT_CAPACITY_LOAD SB_MERGE_OPTIMISTIC SB_MERGE_OPT_LOAD_MAX SB_MERGE_OPT_SLOT_WAIT_S

FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-merge-opt-cap.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
PIDS=""
cleanup() {
  local p
  touch "$TMP/release" 2>/dev/null || true
  for p in $PIDS; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
  rm -rf "$TMP"
}
trap cleanup EXIT

export SB_HEAVY_SLOT_DIR="$TMP/slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
printf '0\n' > "$TMP/zero"
printf '0\n' > "$TMP/mload"
export DEVKIT_SLOT_LOAD_FILE="$TMP/zero" SB_MERGE_LOAD_FILE="$TMP/mload"
export DEVKIT_CAPACITY_CORES=4 DEVKIT_GATE_SLOTS=2
export SB_HEAVY_SLOT_POLL_S=0.05 WORKTREE_TRUNK_MODE=0 VACUITY_REVERT=0 DEVKIT_SENTINEL_MAX_S=999999999 DEVKIT_SUITE_CACHE=0
printf '0\n' > "$TMP/sleep"

# Giữ gate-1.lock bằng flock (như một gate khác đang chạy suite) tới khi có $TMP/release hoặc hết max_s giây
hold_gate1() {
  local max_s="$1"
  rm -f "$TMP/held" "$TMP/release"
  python3 - "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" "$max_s" <<'PY' &
import fcntl, os, sys, time
with open(sys.argv[1], "a") as fh:
    fcntl.flock(fh, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    end = time.monotonic() + float(sys.argv[4])
    while time.monotonic() < end and not os.path.exists(sys.argv[3]):
        time.sleep(0.03)
PY
  HOLDER=$!
  PIDS="$PIDS $HOLDER"
  local i=0
  while [ ! -f "$TMP/held" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
  [ -f "$TMP/held" ] || { fail "thiết lập: không giữ được gate-1.lock"; exit 1; }
}
release_gate1() { touch "$TMP/release"; wait "${HOLDER:-}" 2>/dev/null || true; }

O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid
git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
mkdir -p "$R/.agents" "$R/src"
printf '{"profile":"backend","lang":"vi"}\n' > "$R/.agents/active-profile.json"
printf 'a = 1\n' > "$R/src/a.py"
# Suite ghi: TAG của merge gate, slot pool gate đang có marker .held (của chính post-fix-gate), lúc bắt đầu và kết thúc
cat > "$R/suite.sh" <<SH
#!/usr/bin/env bash
now() { python3 -c 'import time; print("%.3f" % time.time())'; }
held=\$(cd "$SB_HEAVY_SLOT_DIR" && ls gate-*.lock.held 2>/dev/null | tr '\n' ',')
echo "start \${TAG:-none} \$(now) \$held" >> "$TMP/events"
sleep "\$(cat "$TMP/sleep")"
echo "end \${TAG:-none} \$(now)" >> "$TMP/events"
SH
chmod +x "$R/suite.sh"
cat > "$R/.agents/regression_matrix.active.json" <<'JSON'
{"project":"sb-opt-cap","rules":[{"component":"App","watch_files":["*"],
 "mandatory_regression_tests":[{"id":"REG-APP","name":"app","command":"bash suite.sh"}]}]}
JSON
git -C "$R" add -A && git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main
git -C "$R" worktree add -q --detach "$W/review" origin/main

card_branch() {
  local n="$1" f="$2"
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$n-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$n-build" "issue-$n-x"
  echo "$n" > "$W/issue-$n-build/$f"
  git -C "$W/issue-$n-build" add "$f"
  git -C "$W/issue-$n-build" commit -qm "card $n"
  git -C "$R" push -q origin "issue-$n-x"
  git -C "$R" rev-parse "issue-$n-x" > "$TMP/pr$n.head"
  git -C "$R" diff "origin/main" "issue-$n-x" > "$TMP/pr$n.diff"
  printf '{"files":[{"path":"%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$f" > "$TMP/pr$n.meta"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*)
    git -C "$FAKE_REPO" fetch -q origin main "issue-$n-x"
    tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") || exit 1
    c=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n")
    git -C "$FAKE_REPO" push -q origin "$c:refs/heads/main" && echo "$n" >> "$FAKE_DIR/merged" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

CFG="$TMP/cfg.json"
python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[f"python3 {sys.argv[1]} --run-tests --no-checklist"]}))' "$PFG" > "$CFG"

# run_gate <pr> <tag> [env …]: một merge gate thật trên PR đó, log ở $TMP/mg<pr>.log, exit vào $TMP/rc<pr>
run_gate() {
  local pr="$1" tag="$2"; shift 2
  ( cd "$W/review" && env TAG="$tag" "$@" bash "$MERGE_GATE" --config "$CFG" --pr "$pr" --expect-head "$(cat "$TMP/pr$pr.head")" ) \
    >"$TMP/mg$pr.log" 2>&1
  echo "$?" > "$TMP/rc$pr"
}
reset_case() { rm -f "$TMP/events" "$TMP/merged"; rm -rf "$R/.git/super-board/verified-trees"; }

# ── 1. tải cao, 3 merge gate cùng lúc: 2 lạc quan (A, B) + 1 bi quan giữ khoá suốt verify (L) ──
card_branch 1 "src/f1.py"; card_branch 2 "src/f2.py"; card_branch 3 "src/f3.py"
reset_case
printf '50\n' > "$TMP/mload"
printf '4\n' > "$TMP/sleep"
run_gate 1 optA & PIDS="$PIDS $!"; pa=$!
run_gate 2 optB & PIDS="$PIDS $!"; pb=$!
run_gate 3 lock SB_MERGE_OPTIMISTIC=0 & PIDS="$PIDS $!"; pl=$!
wait "$pa" "$pb" "$pl" 2>/dev/null || true
read -r OVL MAXC <<EOF
$(python3 - "$TMP/events" <<'PY'
import sys
ev = []
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) >= 3 and p[0] in ("start", "end"):
        ev.append((float(p[2]), 0 if p[0] == "end" else 1, p[1]))
ev.sort()
cur, opt, mx, ovl = 0, 0, 0, 0
for _, kind, tag in ev:
    d = 1 if kind == 1 else -1
    cur += d
    if tag.startswith("opt"):
        opt += d
    mx = max(mx, cur)
    ovl = max(ovl, opt)
print(ovl, mx)
PY
)
EOF
merged1="$(sort "$TMP/merged" 2>/dev/null | tr '\n' ' ')"
if [ "$(cat "$TMP/rc1")" = 0 ] && [ "$(cat "$TMP/rc2")" = 0 ] && [ "$(cat "$TMP/rc3")" = 0 ] && [ "$merged1" = "1 2 3 " ] \
   && [ "${OVL:-9}" -le 1 ] && [ "${MAXC:-9}" -le 2 ]; then
  ok "1. tải cao, 3 merge gate cùng lúc: tối đa 1 verify lạc quan chạy suite (đo $OVL), tối đa $MAXC ≤ 2 suite cùng lúc, cả 3 PR merge"
else
  fail "1. 3 merge gate: rc=$(cat "$TMP/rc1")/$(cat "$TMP/rc2")/$(cat "$TMP/rc3") merged='$merged1' lạc quan cùng lúc=$OVL (muốn ≤ 1) suite cùng lúc=$MAXC (muốn ≤ 2); events: $(tr '\n' ';' < "$TMP/events" 2>/dev/null)"
fi

# ── 2. tải cao, gate-1 bận rồi nhả sau 3 s: verify lạc quan đợi gate-1, không lấy slot cuối (gate-2) ──
card_branch 4 "src/f4.py"
reset_case
printf '50\n' > "$TMP/mload"; printf '0\n' > "$TMP/sleep"
hold_gate1 3
run_gate 4 opt
release_gate1
first4="$(awk '$1 == "start" {print $4; exit}' "$TMP/events" 2>/dev/null)"
if [ "$(cat "$TMP/rc4")" = 0 ] && [ "$first4" = "gate-1.lock.held," ] && grep -q "leaving the last slot" "$TMP/mg4.log"; then
  ok "2. tải cao: verify lạc quan đợi gate-1 (slot cuối gate-2 để dành cho verify trong khoá), merge exit 0"
else
  fail "2. tải cao + gate-1 bận 3 s: rc=$(cat "$TMP/rc4") slot lúc chạy suite='$first4' (muốn gate-1.lock.held,) log=$(grep -a 'merge-gate' "$TMP/mg4.log" | tail -4 | tr '\n' ';')"
fi

# ── 3. tải cao, gate-1 bận mãi, SB_MERGE_OPT_SLOT_WAIT_S=2: chờ có hạn rồi chạy với cả pool (gate-2), không bỏ verify ──
card_branch 5 "src/f5.py"
reset_case
hold_gate1 120
t0=$(date +%s)
run_gate 5 opt SB_MERGE_OPT_SLOT_WAIT_S=2
t1=$(date +%s)
release_gate1
first5="$(awk '$1 == "start" {print $4; exit}' "$TMP/events" 2>/dev/null)"
if [ "$(cat "$TMP/rc5")" = 0 ] && [ "$first5" = "gate-2.lock.held," ] && grep -q "verifying with the whole gate pool" "$TMP/mg5.log" \
   && [ $((t1 - t0)) -ge 2 ] && grep -qx 5 "$TMP/merged"; then
  ok "3. hết SB_MERGE_OPT_SLOT_WAIT_S: verify chạy với cả pool (gate-2), PR merge ($((t1 - t0)) s)"
else
  fail "3. chờ có hạn rồi chạy: rc=$(cat "$TMP/rc5") slot='$first5' (muốn gate-2.lock.held,) log=$(grep -a 'merge-gate' "$TMP/mg5.log" | tail -4 | tr '\n' ';')"
fi

# ── 4. đối chứng tải thấp: gate-1 bận ⇒ verify lạc quan lấy gate-2 ngay (hành vi cũ) ──
card_branch 6 "src/f6.py"
reset_case
printf '0\n' > "$TMP/mload"
hold_gate1 120
run_gate 6 opt
release_gate1
first6="$(awk '$1 == "start" {print $4; exit}' "$TMP/events" 2>/dev/null)"
if [ "$(cat "$TMP/rc6")" = 0 ] && [ "$first6" = "gate-2.lock.held," ] && ! grep -q "leaving the last slot" "$TMP/mg6.log"; then
  ok "4. đối chứng tải thấp: verify lạc quan lấy gate-2 ngay, không bị hạn"
else
  fail "4. tải thấp: rc=$(cat "$TMP/rc6") slot='$first6' (muốn gate-2.lock.held,)"
fi

# ── 5. đối chứng bi quan (verify trong khoá) tải cao: lấy gate-2 ngay, không bị hạn ──
card_branch 7 "src/f7.py"
reset_case
printf '50\n' > "$TMP/mload"
hold_gate1 120
run_gate 7 lock SB_MERGE_OPTIMISTIC=0
release_gate1
first7="$(awk '$1 == "start" {print $4; exit}' "$TMP/events" 2>/dev/null)"
if [ "$(cat "$TMP/rc7")" = 0 ] && [ "$first7" = "gate-2.lock.held," ] && ! grep -q "leaving the last slot" "$TMP/mg7.log"; then
  ok "5. đối chứng verify trong khoá, tải cao: lấy gate-2 ngay, không bị hạn"
else
  fail "5. verify trong khoá: rc=$(cat "$TMP/rc7") slot='$first7' (muốn gate-2.lock.held,)"
fi

if [ "$FAILS" = 0 ]; then echo "PASS test_merge_gate_opt_load_cap"; exit 0; fi
echo "FAIL test_merge_gate_opt_load_cap ($FAILS ca)"
exit 1
