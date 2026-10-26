#!/usr/bin/env bash
# Pha 2, lớp bảo đảm 1 (lane E): merge train cũ chạy 0 lần trên 73 PR vì reviewer/builder tự gọi merge gate. Khi merge queue bật
# (config merge_queue.enabled hoặc SB_MERGE_QUEUE=1; SB_MERGE_QUEUE=0 luôn tắt), gọi gate trực tiếp mà không có
# SB_MERGE_CALLER ∈ {train,queue} và không --standalone → exit 13, dòng `merge-queue: label the PR merge-queue …`, không verify, không
# đụng khoá. --preflight chỉ chạy các kiểm rẻ trước verify (head, policy, qa-report, ac-check, needs-you), không scratch, không khoá,
# không needs_you_notify; sạch → exit 0 `preflight: ok`. Các dòng approval-request:/human-gate:/needs-you: vẫn ra stdout.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
unset SB_MERGE_QUEUE SB_MERGE_CALLER SB_NOTIFY_SKIP
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-queue-guard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
# Gate chạy từ bản sao bin: approval/notify giả, không đụng bản thật.
cp -R "$ROOT/.claude/bin" "$TMP/gatebin"
GATE="$TMP/gatebin/super-board-merge-gate.sh"
cat > "$TMP/gatebin/super-board-approval.py" <<'PY'
#!/usr/bin/env python3
import json, sys
if "--request" in sys.argv:
    print('approval-request: {"fake":true}')
else:
    print(json.dumps({"approved": False}))
PY
cat > "$TMP/gatebin/super-board-notify.py" <<PY
#!/usr/bin/env python3
import sys
open("$TMP/notify.log", "a").write(" ".join(sys.argv[1:]) + "\n")
PY
: > "$TMP/notify.log"

O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/review-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" push -q origin "$H:refs/heads/issue-6-x"
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"; cp "$TMP/pr5.diff" "$TMP/pr6.diff"
printf '{"files":[{"path":"b"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr5.meta"
# PR 6: cùng code, body khai một bước chỉ người làm được (needs-you).
printf '{"files":[{"path":"b"}],"labels":[],"body":"needs-you: run the live backfill","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr6.meta"
echo "$H" > "$TMP/pr5.head"; echo "$H" > "$TMP/pr6.head"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/gh.calls"
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"title"*) echo "card $n" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "fake gh: this test never merges" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
mkcfg() {  # mkcfg <file> <merge_queue.enabled> <merge_policy.default>
  python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},
    "merge_policy":{"default":sys.argv[3]},
    "merge_queue":{"enabled":sys.argv[2]=="true","enabled_at":None,"batch_max":6,"max_wait_min":60},
    "verify_commands":["touch " + sys.argv[4]]}))' "$1" "$2" "$3" "$TMP/verified" > "$1"
}
CFG_ON="$TMP/cfg-on.json"; CFG_OFF="$TMP/cfg-off.json"; CFG_HUMAN="$TMP/cfg-human.json"
mkcfg "$CFG_ON" true auto; mkcfg "$CFG_OFF" false auto; mkcfg "$CFG_HUMAN" true human
LINE='merge-queue: label the PR merge-queue instead of calling the gate directly'
LOCK="$WT/.claude/super-board/inflight/merge.lock"

# gate <pr> <env…> -- <args…>: chạy gate từ worktree reviewer, stdout/stderr tách riêng, xoá dấu verify trước mỗi lượt.
gate() {
  local pr="$1"; shift
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  rm -f "$TMP/verified"; : > "$TMP/gh.calls"; : > "$TMP/notify.log"
  # Biên nhận cây (#226, sb_verified_tree_receipt): lần chạy đầu của test này in "verify skipped: this exact merged tree was already
  # verified" ở lượt thứ hai. Xoá nó để dấu verify phản ánh đúng lượt này.
  rm -rf "$R/.git/super-board/verified-trees"
  ( cd "$WT" && env ${envs[@]+"${envs[@]}"} bash "$GATE" --pr "$pr" "$@" ) >"$TMP/out" 2>"$TMP/err"; RC=$?
}
# Khoá merge của một gate khác còn sống (pid của shell test): gate thường với --lock-timeout 0 thoát 4 ngay.
plant_lock() {
  mkdir -p "$LOCK"; echo $$ > "$LOCK/pid"; date +%s > "$LOCK/at"; echo 99 > "$LOCK/pr"
  ps -o pgid= -p $$ | tr -d ' ' > "$LOCK/pgid"; hostname > "$LOCK/host"
}
unplant_lock() { rm -rf "$LOCK"; }
verified() { [ -e "$TMP/verified" ]; }
why() { echo "rc=$RC out=[$(tail -3 "$TMP/out" | tr '\n' '|')] err=[$(tail -3 "$TMP/err" | tr '\n' '|')]"; }

# ── 1. queue bật trong config + gọi trực tiếp. Ca này khẳng định: exit 13, đúng dòng trên stdout, file dấu verify vắng, pid khoá
#       giữ nguyên, gh.calls rỗng.
plant_lock
gate 5 -- --config "$CFG_ON" --expect-head "$H" --lock-timeout 0
[ "$RC" -eq 13 ] && grep -qxF "$LINE" "$TMP/out" && ! verified \
  && ok "queue on (config) + direct call: exit 13 with the label line, nothing verified" \
  || fail "queue on + direct call, want 13 and the line: $(why)"
[ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ] && [ ! -s "$TMP/gh.calls" ] \
  && ok "the refused call left the merge lock alone and read nothing from GitHub" \
  || fail "lock pid=$(cat "$LOCK/pid" 2>/dev/null) gh calls=$(wc -l < "$TMP/gh.calls")"

# ── 2. SB_MERGE_QUEUE=1 bật dù config tắt; SB_MERGE_CALLER lạ không được miễn
gate 5 SB_MERGE_QUEUE=1 -- --config "$CFG_OFF" --expect-head "$H" --lock-timeout 0
[ "$RC" -eq 13 ] && grep -qxF "$LINE" "$TMP/out" && ok "SB_MERGE_QUEUE=1 turns the guard on over a config that is off" || fail "SB_MERGE_QUEUE=1: $(why)"
gate 5 SB_MERGE_CALLER=reviewer -- --config "$CFG_ON" --expect-head "$H" --lock-timeout 0
[ "$RC" -eq 13 ] && ok "SB_MERGE_CALLER=reviewer is not a queue caller: exit 13" || fail "SB_MERGE_CALLER=reviewer: $(why)"
# --preflight / --dry-run gọi trực tiếp cũng bị chặn (chỉ train/queue dùng chúng).
gate 5 -- --config "$CFG_ON" --expect-head "$H" --preflight
[ "$RC" -eq 13 ] && ! verified && ok "a direct --preflight is refused too while the queue is on" || fail "direct --preflight: $(why)"
unplant_lock

# ── 3. Người gọi hợp lệ đi tiếp: train, queue, --standalone
for caller in train queue; do
  gate 5 "SB_MERGE_CALLER=$caller" -- --config "$CFG_ON" --expect-head "$H" --dry-run
  [ "$RC" -eq 0 ] && verified && ! grep -q '^merge-queue:' "$TMP/out" \
    && ok "SB_MERGE_CALLER=$caller passes the guard and verifies" || fail "SB_MERGE_CALLER=$caller: $(why)"
done
gate 5 -- --config "$CFG_ON" --expect-head "$H" --dry-run --standalone
[ "$RC" -eq 0 ] && verified && ok "--standalone (super-review outside the board) passes the guard and verifies" || fail "--standalone: $(why)"

# ── 4. Đường lùi: SB_MERGE_QUEUE=0 tắt dù config bật; config tắt thì như cũ
gate 5 SB_MERGE_QUEUE=0 -- --config "$CFG_ON" --expect-head "$H" --dry-run
[ "$RC" -eq 0 ] && verified && ok "SB_MERGE_QUEUE=0 keeps the old behaviour over a config that is on" || fail "SB_MERGE_QUEUE=0: $(why)"
gate 5 -- --config "$CFG_OFF" --expect-head "$H" --dry-run
[ "$RC" -eq 0 ] && verified && ok "queue off in config: the direct call verifies as before" || fail "queue off: $(why)"

# ── 5. --preflight sạch: exit 0 `preflight: ok`, không verify, không scratch, không chờ/lấy khoá (khoá của gate khác đang giữ)
plant_lock
gate 5 SB_MERGE_CALLER=train -- --config "$CFG_ON" --expect-head "$H" --preflight --lock-timeout 0
[ "$RC" -eq 0 ] && grep -qxF 'preflight: ok' "$TMP/out" && ! verified \
  && ok "clean --preflight: exit 0 with 'preflight: ok', nothing verified" || fail "clean preflight: $(why)"
[ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ] && ! ls -d "$R/.claude/worktrees/.merge-scratch-"* >/dev/null 2>&1 \
  && ! grep -q 'pr merge' "$TMP/gh.calls" \
  && ok "--preflight did not wait for the held merge lock, built no scratch tree, merged nothing" \
  || fail "preflight touched lock/scratch/merge: lock pid=$(cat "$LOCK/pid" 2>/dev/null) $(ls -d "$R/.claude/worktrees/".merge-scratch-* 2>/dev/null)"

# ── 6. --preflight với policy cần người: exit 7, human-gate:/approval-request: trên stdout, không notify, không verify
gate 5 SB_MERGE_CALLER=train -- --config "$CFG_HUMAN" --expect-head "$H" --preflight --lock-timeout 0
[ "$RC" -eq 7 ] && grep -q '^human-gate: ' "$TMP/out" && grep -q '^approval-request: ' "$TMP/out" && ! verified \
  && ok "--preflight on a human-merge policy: exit 7, human-gate and approval-request on stdout, nothing verified" \
  || fail "preflight human policy, want 7: $(why)"
[ ! -s "$TMP/notify.log" ] && ok "--preflight sends no needs-you notice" || fail "preflight notified: $(cat "$TMP/notify.log")"

# ── 7. --preflight với bước chỉ người làm (needs-you): exit 8 trước verify, không chờ verify rồi mới báo
gate 6 SB_MERGE_CALLER=train -- --config "$CFG_ON" --expect-head "$H" --preflight --lock-timeout 0
[ "$RC" -eq 8 ] && grep -qxF 'needs-you: run the live backfill' "$TMP/out" && grep -q '^approval-request: ' "$TMP/out" \
  && ! verified && [ ! -s "$TMP/notify.log" ] \
  && ok "--preflight on a needs-you PR: exit 8 with the needs-you line, no verify, no notice" || fail "preflight needs-you, want 8: $(why)"

# ── 8. --preflight khi head đã đổi: exit 6 như gate
gate 5 SB_MERGE_CALLER=train -- --config "$CFG_ON" --expect-head 0000000000000000000000000000000000000000 --preflight --lock-timeout 0
[ "$RC" -eq 6 ] && ! verified && ok "--preflight on a moved head: exit 6" || fail "preflight head moved, want 6: $(why)"
unplant_lock

# ── 9. --dry-run không gửi needs-you notice (plan v4 mục 4: chỉ báo một lần lúc chuyển Blocked)
gate 5 SB_MERGE_CALLER=train -- --config "$CFG_HUMAN" --expect-head "$H" --dry-run
[ "$RC" -eq 7 ] && [ ! -s "$TMP/notify.log" ] && ok "--dry-run on a human-merge policy: exit 7, no notice" || fail "dry-run notice: $(why) notify=$(cat "$TMP/notify.log")"
# Đường lùi SB_MERGE_QUEUE=0: --dry-run vẫn gửi tin như cũ. Nguồn: super-board-merge-train.sh:242 gọi gate --dry-run từng PR, PR bị
# chặn ra khỏi chuỗi; grep approve-button/notify trong merge-train.sh và super-board-run.sh (26/10) không có chỗ gửi nào khác.
gate 5 SB_MERGE_QUEUE=0 -- --config "$CFG_HUMAN" --expect-head "$H" --dry-run
[ "$RC" -eq 7 ] && grep -q '^approve-button ' "$TMP/notify.log" \
  && ok "SB_MERGE_QUEUE=0 --dry-run on a human-merge policy still sends the approve notice" \
  || fail "queue-off dry-run notice: $(why) notify=$(cat "$TMP/notify.log")"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
