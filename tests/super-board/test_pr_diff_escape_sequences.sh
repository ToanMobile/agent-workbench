#!/usr/bin/env bash
# Test hồi quy: `gh pr diff` từ chối in diff có ký tự điều khiển terminal ("the diff contains terminal escape sequences; pass
# --allow-escape-sequences"). 2026-10-18, GeelyEx2 PR #45: log QA có mã màu ANSI, đọc `pr diff` (kind diff, bắt buộc) lỗi 3 lần, board
# GeelyEx2 halt (github-halt.json), merge gate PR #70 không chạy được dù #70 không liên quan. Sửa: gặp đúng lỗi đó thì đọc lại với
# --allow-escape-sequences; lỗi khác vẫn retry/halt như cũ. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READER="$ROOT/.claude/bin/super-board-github-read.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"

# gh giả: `pr diff` thiếu cờ thì từ chối y như gh thật; có cờ thì in diff có mã màu ANSI.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case " $* " in
  *" pr diff "*)
    case " $* " in
      *" --allow-escape-sequences "*) ;;
      *) echo "the diff contains terminal escape sequences; pass --allow-escape-sequences to output it anyway" >&2; exit 1 ;;
    esac
    printf 'diff --git a/q.log b/q.log\nnew file mode 100644\nindex 0000000..1111111\n--- /dev/null\n+++ b/q.log\n@@ -0,0 +1 @@\n+\033[32mok\033[0m\n'
    ;;
  *) echo "unexpected gh call: $*" >&2; exit 2 ;;
esac
GH
chmod +x "$TMP/bin/gh"
echo '{"files":[{"path":"q.log","additions":1,"deletions":0}],"additions":1,"deletions":0,"changedFiles":1,"labels":[],"body":""}' > "$TMP/meta.json"

read_diff() {
  PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 \
    python3 "$READER" --kind diff --meta "$TMP/meta.json" -- pr diff 1 --repo o/r
}

OUT="$(read_diff 2>"$TMP/err")"; RC=$?
if [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q "ok" && [ ! -e "$TMP/halt.json" ]; then
  ok "diff with ANSI escapes is read (retried with --allow-escape-sequences), no board halt"
else
  fail "diff with ANSI escapes: rc=$RC halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
fi

# Lỗi khác của gh vẫn halt như cũ (không nuốt lỗi).
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "HTTP 502 bad gateway" >&2; exit 1
GH
rm -f "$TMP/halt.json"
read_diff >/dev/null 2>&1; RC=$?
[ "$RC" != 0 ] && [ -e "$TMP/halt.json" ] && ok "other gh failure still halts the board" \
  || fail "other gh failure no longer halts (rc=$RC)"

[ "$FAILS" -eq 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
