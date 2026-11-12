#!/usr/bin/env bash
# #1038: github-halt.json không có lệnh đọc (operation=null) + mọi inflight/<N> trỏ tới PID đã chết ⇒ lần khởi động tự đối soát:
# đọc lại issue N (chỉ đọc), lưu bản ghi vào github-halt-reconciled-<ns>.json kèm lý do, gỡ halt. PID còn sống, operation khác null,
# không có khoá nào, hay lần đọc lỗi mạng ⇒ giữ halt. Dùng `gh` giả (offline). Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
RUN="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-autoreconcile-test.XXXXXX")"
SLEEPER=""
trap '[ -z "$SLEEPER" ] || kill "$SLEEPER" 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/inflight"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
case "$1 $2" in
  "issue view") [ "${STUB_ISSUE:-OK}" = FAIL ] && { echo 'HTTP 502' >&2; exit 1; }; echo '{"state":"OPEN","assignees":[]}' ;;
  *) echo 'unexpected' >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" GH_CALLS="$TMP/calls"
unset SB_GITHUB_READ_STRICT
: > "$TMP/calls"

sleep 300 & SLEEPER=$!
DEAD=$(bash -c 'echo $$')   # PID của một bash vừa thoát: không còn sống
run() { python3 "$READ" --auto-reconcile --inflight "$TMP/inflight" >"$TMP/out" 2>"$TMP/err"; echo $?; }
halted() { [ -e "$TMP/halt.json" ]; }
reset() { rm -f "$TMP/halt.json" "$TMP"/github-halt-reconciled-*.json "$TMP"/inflight/*; : > "$TMP/calls"; }
op_null_halt() { echo '{"reason":"GitHub issue edit response failed; reconcile the write before restarting","attempts":1,"at":1,"operation":null}' > "$TMP/halt.json"; }

# 1. operation=null + khoá chết ⇒ tự gỡ, ghi bản lưu kèm lý do, đã đọc lại issue.
reset; op_null_halt
printf 'PID=%s\nLANE=qa\n' "$DEAD" > "$TMP/inflight/112"
rc=$(run)
if [ "$rc" = 0 ] && ! halted && grep -q '"reconciled"' "$TMP"/github-halt-reconciled-*.json 2>/dev/null && grep -q 'issue view 112' "$TMP/calls"; then
  ok "op-null halt + dead-PID lock → auto-reconciled, archive written, issue re-read"
else fail "dead lock: rc=$rc halted=$(halted && echo y || echo n) err=$(cat "$TMP/err")"; fi

# 2. PID còn sống ⇒ giữ halt.
reset; op_null_halt
printf 'PID=%s\nLANE=qa\n' "$SLEEPER" > "$TMP/inflight/112"
rc=$(run)
[ "$rc" != 0 ] && halted && ok "live PID → halt kept" || fail "live pid: rc=$rc"

# 3. operation khác null ⇒ giữ halt.
reset; echo '{"reason":"r","attempts":3,"at":1,"operation":{"args":["pr","view","1"],"kind":"json","meta":null}}' > "$TMP/halt.json"
printf 'PID=%s\n' "$DEAD" > "$TMP/inflight/112"
rc=$(run)
[ "$rc" != 0 ] && halted && ok "halt with a saved read → kept" || fail "operation halt: rc=$rc"

# 4. lần đối soát lỗi mạng ⇒ giữ halt, nêu lý do.
reset; op_null_halt
printf 'PID=%s\n' "$DEAD" > "$TMP/inflight/112"
rc=$(STUB_ISSUE=FAIL run)
if [ "$rc" != 0 ] && halted && ! ls "$TMP"/github-halt-reconciled-*.json >/dev/null 2>&1 && grep -q '#112' "$TMP/err"; then
  ok "network failure on re-read → halt kept, reason logged"
else fail "net fail: rc=$rc err=$(cat "$TMP/err")"; fi

# 5. không có khoá nào ⇒ không chứng minh được worker đã chết ⇒ giữ halt.
reset; op_null_halt
rc=$(run)
[ "$rc" != 0 ] && halted && ok "no inflight lock → halt kept" || fail "no locks: rc=$rc"

# 6. khoá không đọc được PID ⇒ giữ halt.
reset; op_null_halt
echo 'LANE=qa' > "$TMP/inflight/112"
rc=$(run)
[ "$rc" != 0 ] && halted && ok "lock without PID → halt kept" || fail "no pid: rc=$rc"

# 7. runner gọi bước này trước gh_checkpoint đầu tiên lúc khởi động.
a=$(grep -n -- '--auto-reconcile' "$RUN" | head -1 | cut -d: -f1)
b=$(grep -n '^gh_checkpoint$' "$RUN" | head -1 | cut -d: -f1)
if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then ok "runner calls --auto-reconcile before its first startup gh_checkpoint"
else fail "runner wiring: a=$a b=$b"; fi

if [ "$FAILS" = 0 ]; then echo "PASS"; exit 0; else echo "FAIL ($FAILS)"; exit 1; fi
