#!/usr/bin/env bash
# Test hồi quy #190 cho `super-board-github-read.py --halt --verify` và `--reconcile` với `gh` giả (offline).
# 22/10 06:31: gh pr merge lỗi GraphQL 5xx → halt rc=79 do một lần GHI chưa rõ kết quả; board đứng 2g47 chờ người đọc lại
# GitHub. --reconcile đọc lại đúng lần ghi đó: đã áp dụng → lưu trữ halt kèm bằng chứng (exit 0); chưa áp dụng (exit 10) hay
# không kiểm chứng được (exit 11) → giữ nguyên halt, không đụng gì. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-ghreconcile-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
# gh giả: STUB_PR_STATE = trạng thái PR (MERGED/OPEN/FAIL); STUB_COMMENTS = JSON các trang comment (hoặc FAIL).
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
case "$1 $2" in
  "pr view")
    [ "${STUB_PR_STATE:-FAIL}" = FAIL ] && { echo 'HTTP 502' >&2; exit 1; }
    echo "{\"state\":\"$STUB_PR_STATE\"}" ;;
  "api repos/{owner}/{repo}/issues/9/comments")
    [ "${STUB_COMMENTS:-FAIL}" = FAIL ] && { echo 'HTTP 502' >&2; exit 1; }
    echo "$STUB_COMMENTS" ;;
  *) echo 'unexpected' >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" GH_CALLS="$TMP/calls"
unset SB_GITHUB_READ_STRICT
: > "$TMP/calls"

run() { python3 "$READ" "$@" >"$TMP/out" 2>"$TMP/err"; echo $?; }
halted() { [ -e "$TMP/halt.json" ]; }

# --halt --verify lưu spec vào bản ghi; spec sai bị từ chối (exit 64) và không halt.
rc=$(run --halt "merge response failed" --verify '{"kind":"bogus"}')
[ "$rc" = 64 ] && ! halted && ok "a malformed --verify is refused (64) and halts nothing" || fail "bad --verify: rc=$rc halted=$(halted && echo y || echo n)"
rc=$(run --halt "merge response failed" --verify '{"kind":"pr-merged","pr":7}')
[ "$rc" = 79 ] && [ "$(jq -r .verify.pr "$TMP/halt.json")" = 7 ] && ok "--halt --verify saves the verify spec in the halt record" || fail "halt with verify: rc=$rc $(cat "$TMP/halt.json" 2>/dev/null)"

# Đã áp dụng: PR MERGED → exit 0, halt được lưu trữ kèm bằng chứng.
STUB_PR_STATE=MERGED rc=$(STUB_PR_STATE=MERGED run --reconcile)
if [ "$rc" = 0 ] && ! halted && grep -q 'MERGED' "$TMP"/github-halt-reconciled-*.json 2>/dev/null; then
  ok "PR MERGED → reconciled (exit 0), halt archived with the evidence"
else fail "merged: rc=$rc halted=$(halted && echo y || echo n) err=$(cat "$TMP/err")"; fi
rm -f "$TMP"/github-halt-reconciled-*.json "$TMP/halt.json"

# Chưa áp dụng: PR còn OPEN → exit 10, halt giữ nguyên.
run --halt "merge response failed" --verify '{"kind":"pr-merged","pr":7}' >/dev/null
rc=$(STUB_PR_STATE=OPEN run --reconcile)
[ "$rc" = 10 ] && halted && ok "PR still OPEN → exit 10, halt kept" || fail "open: rc=$rc halted=$(halted && echo y || echo n)"

# Không kiểm chứng được: lần đọc hỏng → exit 11, halt giữ nguyên (không bao giờ coi lỗi đọc là 'đã áp dụng').
rc=$(STUB_PR_STATE=FAIL run --reconcile)
[ "$rc" = 11 ] && halted && ok "verifying read fails → exit 11, halt kept" || fail "read fail: rc=$rc"
rm -f "$TMP/halt.json"

# Halt không có spec (writer cũ): exit 11.
run --halt "legacy halt" >/dev/null
rc=$(run --reconcile)
[ "$rc" = 11 ] && halted && ok "halt without a verify spec → exit 11, halt kept" || fail "no spec: rc=$rc"
rm -f "$TMP/halt.json"

# Comment: marker có trong một trang → áp dụng; vắng → chưa áp dụng.
run --halt "comment outcome unknown" --verify '{"kind":"comment","issue":9,"marker":"[orchestrator] back to Ready"}' >/dev/null
rc=$(STUB_COMMENTS='[[{"body":"hi"}],[{"body":"[orchestrator] back to Ready · x"}]]' run --reconcile)
[ "$rc" = 0 ] && ! halted && ok "comment marker found on page 2 → reconciled" || fail "comment found: rc=$rc"
rm -f "$TMP"/github-halt-reconciled-*.json
run --halt "comment outcome unknown" --verify '{"kind":"comment","issue":9,"marker":"[orchestrator] back to Ready"}' >/dev/null
rc=$(STUB_COMMENTS='[[{"body":"hi"}]]' run --reconcile)
[ "$rc" = 10 ] && halted && ok "comment marker absent → exit 10, halt kept" || fail "comment absent: rc=$rc"
rm -f "$TMP/halt.json"

# Halt mang một lần ĐỌC đã lưu (operation): --reconcile từ chối, exit 64 (replay bằng --resume).
echo '{"reason":"r","attempts":3,"at":1,"operation":{"args":["pr","view","1"],"kind":"json","meta":null}}' > "$TMP/halt.json"
rc=$(run --reconcile)
[ "$rc" = 64 ] && halted && ok "a halt with a saved read is refused by --reconcile (use --resume)" || fail "operation halt: rc=$rc"

[ "$FAILS" -eq 0 ] && echo "✅ test_github_read_reconcile: all passed" || { echo "❌ test_github_read_reconcile: $FAILS failed"; exit 1; }
