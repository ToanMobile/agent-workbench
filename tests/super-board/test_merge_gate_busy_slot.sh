#!/usr/bin/env bash
# Test hồi quy T0056 (Bước 6 & Bước 7):
# - super-board-merge-gate.sh: đặt mặc định DEVKIT_GATE_SLOT_WAIT_S=1800; khi post-fix-gate thoát 4 kèm JSON .busy == true thì thoát 4 (thẻ ở lại Review), không thoát 11 (không đẩy về Build).
# - super-board-merge-train.sh: truyền json qua run_cmd tách khỏi cmd, đặt DEVKIT_GATE_SLOT_WAIT_S=1800; khi thoát 4 kèm .busy == true thì trả 3 NGAY LẬP TỨC (không retry) -> train thoát 12 (các thẻ ở lại Review).
# Tương thích bash 3.2; mọi bình luận viết bằng tiếng Việt.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MERGE_GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
TRAIN="$ROOT/.claude/bin/super-board-merge-train.sh"
PFG="$ROOT/universal-agent-devkit/bin/post-fix-gate.py"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"

# Bắt buộc gỡ CLAUDE_PROJECT_DIR / TARGET_DIR và SB_HEAVY_SLOT_HELD / DEVKIT_GATE_SLOT_HELD sau khi nạp clean_git_env.sh để kiểm tra khoá hàng đợi thật trên scratch
unset CLAUDE_PROJECT_DIR TARGET_DIR SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD DEVKIT_GATE_SLOTS DEVKIT_GATE_SLOT_WAIT_S \
      DEVKIT_SLOT_PRIORITY DEVKIT_CAPACITY DEVKIT_CAPACITY_CORES DEVKIT_CAPACITY_LOAD

FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-merge-busy-slot.XXXXXX")"
HOLDERS=""
cleanup() {
  local p
  touch "$TMP/release" 2>/dev/null || true
  for p in $HOLDERS; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
  rm -rf "$TMP"
}
trap cleanup EXIT

export SB_HEAVY_SLOT_DIR="$TMP/slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
printf '0\n' > "$TMP/load"
export DEVKIT_SLOT_LOAD_FILE="$TMP/load"
export SB_MERGE_LOAD_FILE="$TMP/load"
export SB_HEAVY_SLOT_POLL_S=0.05
export WORKTREE_TRUNK_MODE=0
export VACUITY_REVERT=0
export DEVKIT_SENTINEL_MAX_S=999999999

hold_gate_slot() {
  rm -f "$TMP/held" "$TMP/release"
  python3 - "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/held" "$TMP/release" <<'PY' &
import fcntl, os, sys, time
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
with open(sys.argv[1], "a") as fh:
    fcntl.flock(fh, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    end = time.monotonic() + 30.0
    while time.monotonic() < end and not os.path.exists(sys.argv[3]):
        time.sleep(0.03)
PY
  LAST_HOLDER=$!
  HOLDERS="$HOLDERS $LAST_HOLDER"
  local i=0
  while [ ! -f "$TMP/held" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
  [ -f "$TMP/held" ] || { fail "thiết lập: không giữ được gate-1.lock"; exit 1; }
}

release_gate_slot() {
  touch "$TMP/release"
  wait "${LAST_HOLDER:-}" 2>/dev/null || true
}

# Khởi tạo repo bare origin + repo chính có ma trận hồi quy thật để chạy post-fix-gate.py thật trong verify_commands
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid
git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
mkdir -p "$R/.agents" "$R/src"
printf '{"profile":"backend","lang":"vi"}\n' > "$R/.agents/active-profile.json"
printf 'a = 1\n' > "$R/src/a.py"
cat > "$R/suite.sh" <<SH
#!/usr/bin/env bash
echo "\${DEVKIT_GATE_SLOT_WAIT_S:-unset}" >> "$TMP/suite_wait_seen"
[ ! -e bad ]
SH
chmod +x "$R/suite.sh"
cat > "$R/.agents/regression_matrix.active.json" <<'JSON'
{"project":"sb-busy","rules":[{"component":"App","watch_files":["*"],
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
. "$ROOT/tests/super-board/lib/fake_review_fanout.sh"; sb_review_fixture "$TMP/bin"   # signed review PASS + CI checks (new gate preconditions)
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

CFG_PFG="$TMP/cfg-pfg.json"
python3 - "$PFG" "$TMP" > "$CFG_PFG" <<'PY'
import json, sys
pfg, tmp = sys.argv[1], sys.argv[2]
# Lệnh verify đầu dùng post-fix-gate.py thật; bộ đếm ghi lại mỗi lần lệnh verify được gọi
print(json.dumps({
    "base_branch": "main",
    "repo": {"path": ".", "remote": ""},
    "verify_commands": [f"python3 {pfg} --run-tests --no-checklist"]
}))
PY

CFG_WRAP="$TMP/cfg-wrap.json"
python3 - "$TMP" > "$CFG_WRAP" <<'PY'
import json, sys
tmp = sys.argv[1]
print(json.dumps({
    "base_branch": "main",
    "repo": {"path": ".", "remote": ""},
    "verify_commands": [f"printf '%s' \"${{DEVKIT_GATE_SLOT_WAIT_S:-unset}}\" > {tmp}/else_wait_seen"]
}))
PY

# ── 1. super-board-merge-gate.sh: mặc định DEVKIT_GATE_SLOT_WAIT_S=1800 ở cả 2 nhánh của run_verify_cmd_inner ──
# Quan sát ở CHÍNH lệnh post-fix-gate (trình bọc ghi biến rồi gọi gate thật): suite_env bỏ biến này khỏi suite (audit T0056).
SEEN_PFG="$TMP/seen_post-fix-gate.py"
cat > "$SEEN_PFG" <<PY
import os, subprocess, sys
open(r"$TMP/pfg_wait_seen", "w").write(os.environ.get("DEVKIT_GATE_SLOT_WAIT_S", "unset"))
sys.exit(subprocess.call([sys.executable, r"$PFG"] + sys.argv[1:]))
PY
CFG_SEEN="$TMP/cfg-seen.json"
python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[f"python3 {sys.argv[1]} --run-tests --no-checklist"]}))' "$SEEN_PFG" > "$CFG_SEEN"
card_branch 1 "src/f1.py"
rm -f "$TMP/suite_wait_seen" "$TMP/pfg_wait_seen" "$TMP/merged"
( unset DEVKIT_GATE_SLOT_WAIT_S; cd "$W/review" && DEVKIT_GATE_SLOTS=1 DEVKIT_SUITE_CACHE=0 \
    bash "$MERGE_GATE" --config "$CFG_SEEN" --pr 1 --expect-head "$(cat "$TMP/pr1.head")" ) >"$TMP/mg_def1.log" 2>&1
rc1=$?
card_branch 2 "src/f2.py"
rm -f "$TMP/else_wait_seen"
( unset DEVKIT_GATE_SLOT_WAIT_S; cd "$W/review" && DEVKIT_GATE_SLOTS=1 \
    bash "$MERGE_GATE" --config "$CFG_WRAP" --pr 2 --expect-head "$(cat "$TMP/pr2.head")" ) >"$TMP/mg_def2.log" 2>&1
rc2=$?
if [ "$rc1" -eq 0 ] && [ "$(cat "$TMP/pfg_wait_seen" 2>/dev/null)" = "1800" ] \
   && [ "$rc2" -eq 0 ] && [ "$(cat "$TMP/else_wait_seen" 2>/dev/null)" = "1800" ]; then
  ok "1. merge-gate: cả hai nhánh run_verify_cmd_inner đều export mặc định DEVKIT_GATE_SLOT_WAIT_S=1800"
else
  fail "1. merge-gate default wait: rc1=$rc1 (seen='$(cat "$TMP/pfg_wait_seen" 2>/dev/null)') rc2=$rc2 (else='$(cat "$TMP/else_wait_seen" 2>/dev/null)')"
fi

# ── 2. super-board-merge-gate.sh: slot gate bận (exit 4, .busy == true) -> thoát 4 (thẻ ở lại Review), không thoát 11, không merge ──
card_branch 3 "src/f3.py"
rm -f "$TMP/merged" "$TMP/suite_wait_seen"
rm -rf "$R/.git/super-board/verified-trees"
hold_gate_slot
( cd "$W/review" && DEVKIT_GATE_SLOTS=1 DEVKIT_GATE_SLOT_WAIT_S=1 DEVKIT_SUITE_CACHE=0 \
    bash "$MERGE_GATE" --config "$CFG_PFG" --pr 3 --expect-head "$(cat "$TMP/pr3.head")" ) >"$TMP/mg_busy.log" 2>&1
rc_busy=$?
release_gate_slot
if [ "$rc_busy" -eq 4 ] && [ ! -f "$TMP/merged" ] && [ ! -f "$TMP/suite_wait_seen" ] \
   && [ -z "$(ls "$R/.git/super-board/verified-trees" 2>/dev/null)" ]; then
  ok "2. merge-gate: post-fix-gate exit 4 busy -> merge-gate exit 4 (không ra 11, không merge, không ghi verified-tree)"
else
  fail "2. merge-gate busy: rc=$rc_busy (muốn 4) merged=$(cat "$TMP/merged" 2>/dev/null) log=$(tail -6 "$TMP/mg_busy.log")"
fi

# ── 3. Đối chứng merge-gate: PR làm suite đỏ thật (exit 1) hoặc exit 4 nhưng .busy == false (untested_exit) vẫn thoát 11 ──
card_branch 4 "bad"
rm -f "$TMP/merged"
( cd "$W/review" && DEVKIT_GATE_SLOTS=1 DEVKIT_GATE_SLOT_WAIT_S=2 DEVKIT_SUITE_CACHE=0 \
    bash "$MERGE_GATE" --config "$CFG_PFG" --pr 4 --expect-head "$(cat "$TMP/pr4.head")" ) >"$TMP/mg_red.log" 2>&1
rc_red=$?
FAKE_UNTESTED="$TMP/fake_untested_post-fix-gate.py"
cat > "$FAKE_UNTESTED" <<'PY'
import json, sys
print("POST-FIX AUDIT GATE VERDICT: UNTESTED — missing tool")
if "--json" in sys.argv:
    print(json.dumps({"exit_code": 4, "busy": False, "budget_exhausted": False}))
sys.exit(4)
PY
CFG_UNTESTED="$TMP/cfg-untested.json"
python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[f"python3 {sys.argv[1]} --run-tests"]}))' "$FAKE_UNTESTED" > "$CFG_UNTESTED"
card_branch 5 "src/f5.py"
( cd "$W/review" && bash "$MERGE_GATE" --config "$CFG_UNTESTED" --pr 5 --expect-head "$(cat "$TMP/pr5.head")" ) >"$TMP/mg_untested.log" 2>&1
rc_untested=$?
if [ "$rc_red" -eq 11 ] && [ "$rc_untested" -eq 11 ] && [ ! -f "$TMP/merged" ]; then
  ok "3. đối chứng merge-gate: suite đỏ thật (exit 1) và exit 4 nhưng .busy == false đều giữ exit 11"
else
  fail "3. đối chứng merge-gate: rc_red=$rc_red rc_untested=$rc_untested (đều muốn 11)"
fi

# ── 4. super-board-merge-train.sh: slot gate bận -> truyền json qua run_cmd tách khỏi cmd, KHÔNG retry (chạy đúng 1 lần), return 3 -> exit 12 ──
WRAP_PFG="$TMP/count_post-fix-gate.py"
cat > "$WRAP_PFG" <<PY
import os, subprocess, sys
with open(r"$TMP/train_verify.count", "a") as fh:
    fh.write(os.environ.get("DEVKIT_GATE_SLOT_WAIT_S", "unset") + "\n")
sys.exit(subprocess.call([sys.executable, r"$PFG"] + sys.argv[1:]))
PY
CFG_TRAIN="$TMP/cfg-train.json"
python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[f"python3 {sys.argv[1]} --run-tests --no-checklist"]}))' "$WRAP_PFG" > "$CFG_TRAIN"

card_branch 6 "src/f6.py"
card_branch 7 "src/f7.py"
rm -f "$TMP/train_verify.count" "$TMP/merged"
hold_gate_slot
( cd "$W/review" && DEVKIT_GATE_SLOTS=1 DEVKIT_GATE_SLOT_WAIT_S=1 DEVKIT_SUITE_CACHE=0 \
    bash "$TRAIN" --config "$CFG_TRAIN" --prs 6,7 ) >"$TMP/train_busy.log" 2>&1
rc_train_busy=$?
release_gate_slot
n_runs=$(wc -l < "$TMP/train_verify.count" 2>/dev/null | tr -d ' ' || echo 0)
if [ "$rc_train_busy" -eq 12 ] && [ "$n_runs" = "1" ] && [ ! -f "$TMP/merged" ] \
   && ! grep -q "train-red" "$TMP/train_busy.log" \
   && grep -q "train-result: 6 timeout" "$TMP/train_busy.log" \
   && grep -q "train-result: 7 timeout" "$TMP/train_busy.log" \
   && ! grep -q -- "--json" "$TMP/train_busy.log"; then
  ok "4. merge-train: exit 4 busy trả 3 NGAY LẬP TỨC (1 lần chạy, không retry, cmd log sạch không dính --json) -> train exit 12, giữ thẻ ở Review"
else
  fail "4. merge-train busy: rc=$rc_train_busy (muốn 12) n_runs=$n_runs (muốn 1) log=$(tail -8 "$TMP/train_busy.log")"
fi

# ── 5. super-board-merge-train.sh: khi slot rảnh và gỡ DEVKIT_GATE_SLOT_WAIT_S -> export mặc định 1800, verify 1 lần và merge cả 2 PR (exit 0) ──
rm -f "$TMP/train_verify.count" "$TMP/merged"
( unset DEVKIT_GATE_SLOT_WAIT_S; cd "$W/review" && DEVKIT_GATE_SLOTS=1 DEVKIT_SUITE_CACHE=0 \
    bash "$TRAIN" --config "$CFG_TRAIN" --prs 6,7 ) >"$TMP/train_ok.log" 2>&1
rc_train_ok=$?
n_ok_runs=$(wc -l < "$TMP/train_verify.count" 2>/dev/null | tr -d ' ' || echo 0)
wait_val="$(head -1 "$TMP/train_verify.count" 2>/dev/null || true)"
merged_all="$(sort "$TMP/merged" 2>/dev/null | tr '\n' ' ')"
if [ "$rc_train_ok" -eq 0 ] && [ "$n_ok_runs" = "1" ] && [ "$wait_val" = "1800" ] && [ "$merged_all" = "6 7 " ]; then
  ok "5. merge-train khi slot rảnh: mặc định DEVKIT_GATE_SLOT_WAIT_S=1800, verify 1 lần, merge cả 2 PR (exit 0)"
else
  fail "5. merge-train ok: rc=$rc_train_ok n_runs=$n_ok_runs wait='$wait_val' merged='$merged_all' log=$(tail -6 "$TMP/train_ok.log")"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "✅ test_merge_gate_busy_slot: tất cả PASS"
  exit 0
fi
echo "❌ test_merge_gate_busy_slot: $FAILS lỗi"
exit 1
