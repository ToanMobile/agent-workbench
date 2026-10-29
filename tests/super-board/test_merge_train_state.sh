#!/usr/bin/env bash
# Test hồi quy #562: super-board-merge-train.sh ghi <git-common-dir>/super-board/merge-train.state (pid, started_at, step, `pr <N> <sha> <ref>`)
# suốt lúc chạy và xoá khi thoát (xong, TERM). Train thứ hai bị chặn (exit 4) không được xoá file của train đang chạy.
# Offline: `gh` giả, origin bare, merge gate giả (preflight chờ cờ $TMP/release để test kịp đọc file lúc train đang chạy).
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-train-state.XXXXXX")"
TRAIN_PID=""
trap '[ -z "$TRAIN_PID" ] || kill "$TRAIN_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"; echo a > "$R/a"
git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-7-x origin/main
git -C "$R" checkout -q issue-7-x; echo 7 > "$R/f7"; git -C "$R" add f7; git -C "$R" commit -qm c7
git -C "$R" push -q origin issue-7-x; git -C "$R" checkout -q main
git -C "$R" rev-parse issue-7-x > "$TMP/pr7.head"
SHA=$(cat "$TMP/pr7.head")

mkdir -p "$TMP/bin" "$TMP/sbbin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $(cat "$FAKE_DIR/pr$n.head")" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
for f in "$ROOT"/.claude/bin/*; do ln -s "$f" "$TMP/sbbin/$(basename "$f")"; done
rm -f "$TMP/sbbin/super-board-merge-gate.sh"
# TRAIN_SRC: chạy test với bản train khác (bản cũ để thấy ĐỎ); mặc định là bản trong repo.
if [ -n "${TRAIN_SRC:-}" ]; then rm -f "$TMP/sbbin/super-board-merge-train.sh"; cp "$TRAIN_SRC" "$TMP/sbbin/super-board-merge-train.sh"; fi
cat > "$TMP/sbbin/super-board-merge-gate.sh" <<'SH'
#!/usr/bin/env bash
# preflight: ghi dấu "đã vào gate" rồi chờ cờ release; mọi lời gọi khác (dry-run, merge) trả 0.
case " $* " in
  *" --preflight "*)
    : > "$FAKE_DIR/in-gate"
    i=0; while [ ! -e "$FAKE_DIR/release" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
    echo "preflight: ok" ;;
esac
exit 0
SH
chmod +x "$TMP/sbbin/super-board-merge-gate.sh"
TRAIN="$TMP/sbbin/super-board-merge-train.sh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1
unset SB_MERGE_CALLER SB_MERGE_QUEUE SB_BOARD_WORKER
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"]}\n' > "$CFG"
STATE="$R/.git/super-board/merge-train.state"

wait_for() {  # wait_for <file> : tối đa 30 s
  local i=0; while [ ! -e "$1" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done; [ -e "$1" ]
}
start_train() { rm -f "$TMP/release" "$TMP/in-gate"; ( cd "$R" && exec bash "$TRAIN" --config "$CFG" --prs "7:$SHA" ) >"$TMP/train.log" 2>&1 & TRAIN_PID=$!; }

# ── 1. Train đang chạy gate: file state có pid sống, step gate, dòng PR kèm sha và ref; xong thì file biến mất.
start_train
if wait_for "$TMP/in-gate"; then ok "train reached the gate"; else fail "train never reached the gate: $(tail -5 "$TMP/train.log")"; fi
if [ -f "$STATE" ] && grep -q "^pid ${TRAIN_PID}\$" "$STATE" && grep -q '^step gate$' "$STATE" \
   && grep -q "^pr 7 ${SHA} issue-7-x\$" "$STATE" && grep -qE '^started_at [0-9]+$' "$STATE"; then
  ok "state file while gating: pid, step gate, started_at, pr 7 <sha> <ref>"
else fail "state file wrong while gating: $(cat "$STATE" 2>/dev/null || echo '<missing>')"; fi

# ── 2. Train thứ hai (khoá bận) thoát 4 và KHÔNG xoá file của train đang chạy.
( cd "$R" && bash "$TRAIN" --config "$CFG" --prs "7:$SHA" ) >"$TMP/train2.log" 2>&1; rc=$?
[ "$rc" -eq 4 ] && ok "second train: exit 4 (lock busy)" || fail "second train: exit $rc: $(tail -3 "$TMP/train2.log")"
[ -f "$STATE" ] && grep -q "^pid ${TRAIN_PID}\$" "$STATE" && ok "exit 4 left the running train's state file alone" || fail "exit 4 removed or changed the state file"

touch "$TMP/release"; wait "$TRAIN_PID"; rc=$?; TRAIN_PID=""
[ "$rc" -eq 0 ] && ok "train finished: exit 0" || fail "train exit $rc: $(tail -5 "$TMP/train.log")"
[ ! -e "$STATE" ] && [ ! -e "$STATE.tmp" ] && ok "state file removed after a normal exit" || fail "state file left behind after exit 0"

# ── 3. TERM: file state bị xoá qua trap.
start_train
wait_for "$TMP/in-gate" >/dev/null; [ -f "$STATE" ] && ok "state file present before TERM" || fail "no state file before TERM"
kill -TERM "$TRAIN_PID"; touch "$TMP/release"; wait "$TRAIN_PID" 2>/dev/null; TRAIN_PID=""
[ ! -e "$STATE" ] && ok "state file removed after TERM" || fail "state file left behind after TERM"

[ "$FAILS" -eq 0 ] && { echo "PASS test_merge_train_state"; exit 0; }
echo "FAIL test_merge_train_state: $FAILS"; exit 1
