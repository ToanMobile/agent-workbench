#!/usr/bin/env bash
# 19/10 (Goods PR #48): gh 2.100 từ chối `pr diff` khi diff chứa ký tự điều khiển terminal (log bằng chứng có mã màu ANSI):
# "the diff contains terminal escape sequences; pass --allow-escape-sequences to output it anyway", exit 1. Lệnh đọc diff
# của merge gate thử lại y nguyên 3 lần rồi ghi file halt: cả board Goods dừng vì một file log. Diff chỉ được ghi vào file để
# phân loại, không in ra terminal, nên đọc lại có cờ đó là an toàn. gh cũ không biết cờ: lần đọc đầu không bao giờ thêm cờ.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-ghread-esc-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
ESC=$(printf '\033')
{ printf 'diff --git a/x.log b/x.log\nnew file mode 100644\nindex 0000000..1111111\n--- /dev/null\n+++ b/x.log\n@@ -0,0 +1,2 @@\n'
  printf '+%s[32mPASS%s[0m\n+ok\n' "$ESC" "$ESC"; } > "$TMP/esc.diff"
{ printf 'diff --git a/y.txt b/y.txt\nnew file mode 100644\nindex 0000000..2222222\n--- /dev/null\n+++ b/y.txt\n@@ -0,0 +1,1 @@\n+plain\n'; } > "$TMP/plain.diff"
printf '{"files":[{"path":"x.log"}],"additions":2,"deletions":0}' > "$TMP/esc.meta"
printf '{"files":[{"path":"y.txt"}],"additions":1,"deletions":0}' > "$TMP/plain.meta"
# gh giả theo đúng thông báo gh 2.100.0 (đo 19/10 trên Goods PR #48)
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
case " $* " in
  *" pr diff 48 "*"--allow-escape-sequences"*) cat "$FAKE_DIR/esc.diff" ;;
  *" pr diff 48 "*) echo 'the diff contains terminal escape sequences; pass --allow-escape-sequences to output it anyway' >&2; exit 1 ;;
  *" pr diff 7 "*"--allow-escape-sequences"*) echo 'unknown flag: --allow-escape-sequences' >&2; exit 1 ;;
  *" pr diff 7 "*) cat "$FAKE_DIR/plain.diff" ;;
  *) echo 'unexpected' >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 GH_CALLS="$TMP/calls" FAKE_DIR="$TMP"
export SB_GITHUB_READ_STRICT=1   # như merge gate

python3 "$READ" --kind diff --meta "$TMP/esc.meta" -- pr diff 48 --repo o/r >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/halt.json" ] && ok "diff có ký tự ESC: đọc được (exit 0), board không halt" \
  || fail "diff có ký tự ESC: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
grep -q "PASS" "$TMP/out" && ok "nội dung diff được trả nguyên" || fail "thiếu nội dung diff trong output"
rm -f "$TMP/halt.json"; : > "$TMP/calls"

python3 "$READ" --kind diff --meta "$TMP/plain.meta" -- pr diff 7 --repo o/r >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && ! grep -q allow-escape "$TMP/calls" && ok "diff thường: một lần đọc, không thêm cờ (gh cũ không biết cờ vẫn chạy)" \
  || fail "diff thường: rc=$rc calls=$(tr '\n' '|' < "$TMP/calls")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_github_read_diff_escape: PASS"; exit 0; } || { echo "test_github_read_diff_escape: FAIL ($FAILS)"; exit 1; }
