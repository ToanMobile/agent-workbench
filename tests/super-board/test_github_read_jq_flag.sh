#!/usr/bin/env bash
# super-board-github-read.py: lệnh đọc có cờ --jq/-q/--template làm gh in chữ thường thay vì JSON, nên lần nào cũng không qua
# bước kiểm JSON. Với kind quota đã chặn sớm (exit 64, không halt). Các kind khác không có chốt đó: một lane gọi
# `--kind issue -- issue view 32 --json body -q .body` bị thử lại 3 lần rồi ghi file halt (exit 79), cả board dừng, và
# `--resume` phát lại đúng lệnh nên hỏng lần nào cũng thế (22/10 19:55 rồi 23/10 08:45, cùng một lệnh). Luật: lỗi người gọi biết
# trước khi gọi gh: exit 64 kèm dạng đúng, không retry, không halt.
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
  *" issue view "*" -q "*|*" issue view "*" --jq "*) printf 'b\n' ;;
  *" issue view "*) echo '{"number":5,"title":"t","body":"b"}' ;;
  *) echo 'unexpected' >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 GH_CALLS="$TMP/calls"
export SB_GITHUB_READ_STRICT=1   # chế độ của merge gate và runner: kiểm sai hình dạng thì halt cả board

run() { rm -f "$TMP/halt.json" "$TMP/calls"; python3 "$READ" "$@" >"$TMP/out" 2>"$TMP/err"; echo $?; }
halted() { [ -e "$TMP/halt.json" ] && echo yes || echo no; }

rc=$(run --kind issue -- issue view 32 --json body -q .body)
[ "$rc" = 64 ] && [ "$(halted)" = no ] && ok "-q on kind issue: exit 64, board not halted" \
  || fail "-q on kind issue: rc=$rc halt=$(halted) ($(tail -1 "$TMP/err"))"
[ ! -e "$TMP/calls" ] && ok "-q on kind issue: rejected before gh was called" || fail "-q on kind issue: gh was called $(wc -l < "$TMP/calls" | tr -d ' ') time(s)"
grep -q "Valid form: --kind issue" "$TMP/err" && ok "-q on kind issue: message names the valid form" || fail "no valid form in: $(tail -1 "$TMP/err")"

rc=$(run --kind issue -- issue view 32 --json body --jq .body)
[ "$rc" = 64 ] && [ "$(halted)" = no ] && ok "--jq on kind issue: exit 64, board not halted" \
  || fail "--jq on kind issue: rc=$rc halt=$(halted)"

rc=$(run --kind issue -- issue view 5 --json number,title,body)
[ "$rc" = 0 ] && [ "$(halted)" = no ] && ok "plain issue read still works" || fail "plain issue read: rc=$rc halt=$(halted)"

[ "$FAILS" -eq 0 ] && { echo "✅ test_github_read_jq_flag: all passed"; exit 0; } || { echo "❌ test_github_read_jq_flag: $FAILS failed"; exit 1; }
