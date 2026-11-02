#!/usr/bin/env bash
# 02/11 (lane rmlock): khoá merge nằm ở ${REPO_PATH}/.claude/super-board/inflight/merge.lock, mà config không có repo.path thì
# REPO_PATH = "." = worktree của lane gọi gate. Mỗi worktree một khoá: #911 và #912 verify song song 21:31–21:56, nhiều PR verify
# xanh 20–35 phút rồi GitHub từ chối vì main đã dời (#883 #910 #911 #881 #885). Khoá phải nằm trong git common dir, chung cho mọi
# worktree của một repo: gate ở worktree B thấy khoá gate ở worktree A đang giữ, chờ tới khi A nhả; khoá ở common dir mà pid đã
# chết vẫn được reap như cũ; REPO_PATH không phải repo git thì giữ đường cũ và nói ra. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-lock-shared-test.XXXXXX")"
trap 'touch "$TMP/release" 2>/dev/null; kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; rm -rf "$TMP"' EXIT
R="$TMP/repo"; WA="$TMP/wt-a"; WB="$TMP/wt-b"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" worktree add -q -b lane-a "$WA"
git -C "$R" worktree add -q -b lane-b "$WB"

# gh giả: luôn thất bại, nên sau khi lấy khoá gate dừng ở bước đọc PR, không chạm GitHub thật. FAKE_HOLD (chỉ gate A) giữ lệnh gh tới
# khi file đó xuất hiện (tối đa 25 s, dưới timeout 30 s của github-read): gate A nằm trong khoá đúng lúc gate B tới.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
if [ -n "${FAKE_HOLD:-}" ]; then n=0; while [ ! -e "$FAKE_HOLD" ] && [ "$n" -lt 250 ]; do sleep 0.1; n=$((n + 1)); done; fi
echo "fake gh: $*" >&2
exit 1
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export SB_GITHUB_RETRY_DELAY=0 SB_HEAVY_SLOT_DIR="$TMP/slots"
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"]}' > "$CFG"
# Mỗi lượt gate một file halt riêng: gh giả thất bại ghi halt, và `--check` (trước khoá) của gate sau không được dừng vì nó.
# mktemp -u, không phải bộ đếm: lượt chạy nền (&) là subshell, bộ đếm của nó không về cha và hai lượt sẽ dùng chung một file.
gate() { local dir="$1" pr="$2" halt; shift 2; halt=$(mktemp -u "$TMP/halt.XXXXXX")
  ( cd "$dir" && SB_GITHUB_HALT_FILE="$halt" bash "$GATE" --config "$CFG" --pr "$pr" --expect-head deadbeef "$@" ); }
# wait_log <file> <pattern>: tối đa 20 s.
wait_log() { local n=0; while ! grep -q "$2" "$1" 2>/dev/null; do [ "$n" -ge 200 ] && return 1; sleep 0.1; n=$((n + 1)); done; }
hold_a() { rm -f "$TMP/release"; ( export FAKE_HOLD="$TMP/release"; gate "$WA" 5 --lock-timeout 5 ) >"$1" 2>&1 & A=$!
  wait_log "$1" 'lock taken' || fail "gate A (worktree A) never took the merge lock: $(tail -3 "$1" | tr '\n' '|')"; }

# ── 1. A giữ khoá ở worktree A; B ở worktree B với --lock-timeout 0 không được lấy khoá: exit 4.
hold_a "$TMP/a1.log"
gate "$WB" 6 --lock-timeout 0 >"$TMP/b1.log" 2>&1; rc=$?
[ "$rc" -eq 4 ] && grep -q 'could not take the merge lock' "$TMP/b1.log" \
  && ok "worktree B sees the lock held by worktree A: exit 4, not a second lock" \
  || fail "worktree B took its own merge lock while A held one (rc=$rc): $(grep 'merge-gate' "$TMP/b1.log" | head -3 | tr '\n' '|')"
touch "$TMP/release"; wait "$A" 2>/dev/null

# ── 2. B chờ trong lúc A giữ, rồi lấy khoá ngay khi A nhả.
hold_a "$TMP/a2.log"
gate "$WB" 6 --lock-timeout 30 >"$TMP/b2.log" 2>&1 & B=$!
sleep 2
grep -q 'lock taken' "$TMP/b2.log" && fail "worktree B took the lock while A still held it" \
  || ok "worktree B waits while worktree A holds the lock"
touch "$TMP/release"; wait "$A" 2>/dev/null; wait "$B" 2>/dev/null
grep -q 'lock taken' "$TMP/b2.log" && ok "  … and takes it once A releases" \
  || fail "worktree B never took the lock after A released: $(grep 'merge-gate' "$TMP/b2.log" | head -3 | tr '\n' '|')"

# ── 3. Khoá ở git common dir do pid đã chết để lại: B reap ngay như cũ (holder_gone), lấy khoá, nhả khi thoát.
GCD=$(cd "$WB" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
LOCK="$GCD/super-board/merge.lock"
sleep 0 & DEAD=$!; wait "$DEAD" 2>/dev/null
mkdir -p "$LOCK"; date +%s > "$LOCK/at"; echo "$DEAD" > "$LOCK/pid"; echo "$DEAD" > "$LOCK/pgid"; hostname > "$LOCK/host"; echo 9 > "$LOCK/pr"
gate "$WB" 6 --lock-timeout 5 >"$TMP/c3.log" 2>&1; rc=$?
grep -q "reaping a lock whose holder pid $DEAD" "$TMP/c3.log" && grep -q 'lock taken' "$TMP/c3.log" && [ "$rc" -ne 4 ] \
  && ok "a dead holder's lock in the git common dir is reaped at once" \
  || fail "dead holder's lock in the common dir not reaped (rc=$rc): $(grep 'merge-gate' "$TMP/c3.log" | head -3 | tr '\n' '|')"
[ ! -e "$LOCK" ] && ok "  … and the gate releases the common-dir lock on exit" || fail "common-dir lock left behind: $(ls "$LOCK" 2>&1)"

# ── 4. Khoá ở common dir của pid còn sống: không bị reap, B thoát 4, khoá giữ nguyên.
sleep 300 & LIVE=$!
mkdir -p "$LOCK"; date +%s > "$LOCK/at"; echo "$LIVE" > "$LOCK/pid"; ps -o pgid= -p "$LIVE" | tr -d ' ' > "$LOCK/pgid"
hostname > "$LOCK/host"; echo 9 > "$LOCK/pr"
gate "$WA" 5 --lock-timeout 0 >"$TMP/d4.log" 2>&1; rc=$?
[ "$rc" -eq 4 ] && [ "$(cat "$LOCK/pid" 2>/dev/null)" = "$LIVE" ] \
  && ok "a live holder's lock in the common dir is kept: exit 4" || fail "live holder lock: rc=$rc pid=$(cat "$LOCK/pid" 2>/dev/null)"
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null; rm -rf "$LOCK"

# ── 5. REPO_PATH không phải repo git: không có common dir thì giữ đường cũ dưới REPO_PATH và nói ra.
P="$TMP/plain"; mkdir -p "$P"
( export GIT_CEILING_DIRECTORIES="$TMP"; gate "$P" 7 --lock-timeout 5 ) >"$TMP/e5.log" 2>&1
grep -q 'no git common dir' "$TMP/e5.log" && grep -q 'inflight/merge.lock' "$TMP/e5.log" \
  && ok "no git common dir: the gate keeps the per-checkout lock path and says so" \
  || fail "no-git fallback not reported: $(grep 'merge-gate' "$TMP/e5.log" | head -3 | tr '\n' '|')"

echo "---"; [ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
