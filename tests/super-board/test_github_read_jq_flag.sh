#!/usr/bin/env bash
# super-board-github-read.py: lệnh đọc có cờ --jq/-q/--template làm gh in chữ thường thay vì JSON, nên lần nào cũng không qua
# bước kiểm JSON. Với kind quota đã chặn sớm (exit 64, không halt). Các kind có hình dạng JSON cố định khác (issue,
# comments, metadata) không có chốt đó: một lệnh `--kind issue -- issue view 32 --json body -q .body` bị thử lại 3 lần rồi ghi
# file halt (exit 79), cả board dừng, và `--resume` phát lại đúng lệnh nên hỏng lần nào cũng thế (22/10 19:55, 23/10 08:45 và
# 09:02, cùng một lệnh). Luật: lỗi người gọi biết trước khi gọi gh: exit 64 kèm dạng đúng, không retry, không halt.
# kind head và state cần --jq in chuỗi (xem FORMS), kind json/object cho phép --jq ra JSON: không bị chặn.
# gh giả, offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-ghread-jq.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
case " $* " in
  *" pr view "*"--json state"*) printf 'OPEN\n' ;;
  *" issue view "*" -q "*|*" issue view "*" --jq "*) printf 'b\n' ;;
  *" issue view "*) echo '{"number":5,"title":"t","body":"b"}' ;;
  *" api "*" --jq "*) echo '{"headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","body":"b"}' ;;
  *) echo 'unexpected' >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 GH_CALLS="$TMP/calls"
export SB_GITHUB_READ_STRICT=1   # chế độ của merge gate và runner: kiểm sai hình dạng thì halt cả board

run() { rm -f "$TMP/halt.json" "$TMP/calls"; python3 "$READ" "$@" >"$TMP/out" 2>"$TMP/err"; echo $?; }
halted() { [ -e "$TMP/halt.json" ] && echo yes || echo no; }
ghcalls() { if [ -e "$TMP/calls" ]; then wc -l < "$TMP/calls" | tr -d ' '; else echo 0; fi; }

rc=$(run --kind issue -- issue view 32 --json body -q .body)
[ "$rc" = 64 ] && [ "$(halted)" = no ] && ok "-q on kind issue: exit 64, board not halted" \
  || fail "-q on kind issue: rc=$rc halt=$(halted) ($(tail -1 "$TMP/err"))"
[ "$(ghcalls)" = 0 ] && ok "-q on kind issue: rejected before gh was called" || fail "-q on kind issue: gh was called $(ghcalls) time(s)"
grep -q "Valid form: --kind issue" "$TMP/err" && ok "-q on kind issue: message names the valid form" || fail "no valid form in: $(tail -1 "$TMP/err")"

rc=$(run --kind issue -- issue view 32 --json body --jq .body)
[ "$rc" = 64 ] && [ "$(halted)" = no ] && ok "--jq on kind issue: exit 64, board not halted" \
  || fail "--jq on kind issue: rc=$rc halt=$(halted)"

rc=$(run --kind metadata -- pr view 5 --json files -q .files)
[ "$rc" = 64 ] && [ "$(halted)" = no ] && [ "$(ghcalls)" = 0 ] && ok "-q on kind metadata: exit 64, no halt, gh not called" \
  || fail "-q on kind metadata: rc=$rc halt=$(halted) gh=$(ghcalls)"

rc=$(run --kind comments -- api repos/o/r/issues/5/comments --paginate --slurp --jq .x)
[ "$rc" = 64 ] && [ "$(halted)" = no ] && [ "$(ghcalls)" = 0 ] && ok "--jq on kind comments: exit 64, no halt, gh not called" \
  || fail "--jq on kind comments: rc=$rc halt=$(halted) gh=$(ghcalls)"

rc=$(run --kind issue -- issue view 5 --json body --template '{{.body}}')
[ "$rc" = 64 ] && [ "$(halted)" = no ] && [ "$(ghcalls)" = 0 ] && ok "--template on kind issue: exit 64, no halt, gh not called" \
  || fail "--template on kind issue: rc=$rc halt=$(halted) gh=$(ghcalls)"

rc=$(run --kind issue -- issue view 5 --json body --jq=.body)
[ "$rc" = 64 ] && [ "$(halted)" = no ] && ok "--jq=VALUE form on kind issue: exit 64, no halt" || fail "--jq=VALUE: rc=$rc halt=$(halted)"

rc=$(run --kind issue -- issue view 5 --json number,title,body)
[ "$rc" = 0 ] && [ "$(halted)" = no ] && ok "plain issue read still works" || fail "plain issue read: rc=$rc halt=$(halted)"

# kind body nhận --jq ra JSON (super-board-pr-body.sh dùng `api repos/.../pulls/N --jq '{headRefOid: .head.sha, body: ...}').
rc=$(run --kind body -- api repos/o/r/pulls/5 --jq '{headRefOid: .head.sha, body: (.body // "")}')
[ "$rc" = 0 ] && [ "$(halted)" = no ] && ok "kind body keeps its --jq form that prints JSON" || fail "kind body --jq: rc=$rc halt=$(halted) ($(tail -1 "$TMP/err"))"

# kind state cần --jq in chuỗi (FORMS): không bị chặn.
rc=$(run --kind state -- pr view 5 --json state --jq .state)
[ "$rc" = 0 ] && [ "$(halted)" = no ] && ok "kind state keeps its --jq string form" || fail "kind state: rc=$rc halt=$(halted) ($(tail -1 "$TMP/err"))"

[ "$FAILS" -eq 0 ] && { echo "✅ test_github_read_jq_flag: all passed"; exit 0; } || { echo "❌ test_github_read_jq_flag: $FAILS failed"; exit 1; }
