#!/usr/bin/env bash
# 19/10 (review của PR #117): github-read giờ nhận diff có VT/FF/U+2028/CR lẻ trong dòng thêm (trước đó halt = an toàn).
# merge-policy vẫn đọc diff bằng universal newlines (CR lẻ → \n) rồi splitlines(): phần chữ sau ký tự đó thành một dòng
# KHÔNG bắt đầu bằng '+', nên từ khoá always_human ("drop table", "drop column") bị bỏ qua → PR schema được auto-merge.
# Test đi đúng đường của merge gate: github-read (gh giả) → file diff → merge-policy. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-policy-nl.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
printf '{"files":[{"path":"app/x.sql","additions":1,"deletions":0}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/meta.json"
printf '{"merge_policy":{"default":"auto"}}' > "$TMP/cfg.json"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
cat "$FAKE_DIFF"
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_GITHUB_READ_STRICT=1

check() {  # $1 tên, $2 ký tự ngăn (python escape) trước câu lệnh schema, $3 khoảng trắng giữa DROP và TABLE (mặc định ' '),
           # $4 tiền tố của nội dung dòng thêm (mặc định 'select 1;'; '++i; ' cho dòng diff bắt đầu bằng '+++')
  python3 - "$TMP/in.diff" "$2" "${3:- }" "${4:-select 1;}" <<'PY'
import sys
sep = sys.argv[2].encode().decode('unicode_escape')
body = ('diff --git a/app/x.sql b/app/x.sql\nnew file mode 100644\nindex 0000000..1111111\n--- /dev/null\n+++ b/app/x.sql\n'
        '@@ -0,0 +1,1 @@\n+' + sys.argv[4] + sep + 'DROP' + sys.argv[3].encode().decode('unicode_escape') + 'TABLE users;\n')
open(sys.argv[1], 'wb').write(body.encode('utf-8'))
PY
  rm -f "$TMP/halt.json"
  FAKE_DIFF="$TMP/in.diff" python3 "$READ" --kind diff --meta "$TMP/meta.json" -- pr diff 9 --repo o/r > "$TMP/out.diff" 2>"$TMP/err"
  rc=$?
  if [ "$rc" != 0 ]; then  # github-read phải nhận các diff này (test_upstream_66_67), nếu không merge-policy không được thử
    fail "$1: github-read từ chối (rc=$rc: $(tail -1 "$TMP/err")) — merge-policy chưa được kiểm"; return
  fi
  plan="$(python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta.json" --diff "$TMP/out.diff" 2>&1)"
  case "$plan" in
    *'"schema"'*) ok "$1: merge-policy vẫn thấy DROP TABLE → cần người duyệt" ;;
    *) fail "$1: DROP TABLE sau ký tự ngăn lọt qua merge-policy: $plan" ;;
  esac
}
check "đối chứng (dấu cách)" ' '
check "VT" '\x0b'
check "FF" '\x0c'
check "CR lẻ" '\r'
check "U+2028" '\u2028'
check "NEL" '\x85'
check "tab giữa DROP và TABLE" ' ' '\t'
check "hai dấu cách giữa DROP và TABLE" ' ' '  '
check "FF giữa DROP và TABLE" ' ' '\x0c'
check "dòng thêm bắt đầu bằng ++ (diff '+++i;')" ' ' ' ' '++i;'

# Diff nhiều file/nhiều hunk (ngữ cảnh, dòng '-', '\ No newline'): $2 = nội dung dòng thêm ở hunk thứ hai của file sau.
multi() {  # $1 tên, $2 dòng thêm, $3 kết quả mong đợi: schema | auto
  python3 - "$TMP/in.diff" "$2" <<'PY'
import sys
body = ('diff --git a/a.txt b/a.txt\nindex 1111111..2222222 100644\n--- a/a.txt\n+++ b/a.txt\n'
        '@@ -1,2 +1,2 @@\n keep\n-old drop\n+new\n\\ No newline at end of file\n'
        'diff --git a/app/y.sql b/app/y.sql\nindex 3333333..4444444 100644\n--- a/app/y.sql\n+++ b/app/y.sql\n'
        '@@ -1,1 +1,2 @@\n ctx\n+select 1;\n'
        '@@ -10,2 +11,2 @@\n ctx2\n-drop table gone;\n+' + sys.argv[2] + '\n')
open(sys.argv[1], 'wb').write(body.encode('utf-8'))
PY
  printf '{"files":[{"path":"a.txt","additions":1,"deletions":1},{"path":"app/y.sql","additions":2,"deletions":1}],"labels":[],"body":"","additions":3,"deletions":2,"changedFiles":2}' > "$TMP/meta2.json"
  rm -f "$TMP/halt.json"
  FAKE_DIFF="$TMP/in.diff" python3 "$READ" --kind diff --meta "$TMP/meta2.json" -- pr diff 9 --repo o/r > "$TMP/out.diff" 2>"$TMP/err" \
    || { fail "$1: github-read từ chối ($(tail -1 "$TMP/err"))"; return; }
  plan="$(python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta2.json" --diff "$TMP/out.diff" 2>&1)"
  case "$3:$plan" in
    schema:*'"schema"'*) ok "$1: thấy từ khoá → cần người duyệt" ;;
    auto:*'"human": []'*) ok "$1: không có từ khoá → vẫn auto" ;;
    *) fail "$1: muốn $3, được: $plan" ;;
  esac
}
multi "2 file, từ khoá ở hunk sau" 'DROP TABLE users;' schema
multi "đối chứng âm: chỉ dòng '-' có 'drop table', dòng thêm vô hại" 'select 2;' auto

# Header hunk không ghi số dòng ('@@ -0,0 +1 @@', git viết thế cho file mới 1 dòng) và '\ No newline' GIỮA hunk:
# đếm sai ở hai chỗ này làm dòng thêm phía sau rơi khỏi hunk → từ khoá bị bỏ qua.
shape() {  # $1 tên, $2 thân hunk (python escape), $3 additions, $4 deletions
  python3 - "$TMP/in.diff" "$2" <<'PY'
import sys
body = ('diff --git a/app/z.sql b/app/z.sql\nindex 1111111..2222222 100644\n--- a/app/z.sql\n+++ b/app/z.sql\n'
        + sys.argv[2].encode().decode('unicode_escape'))
open(sys.argv[1], 'wb').write(body.encode('utf-8'))
PY
  printf '{"files":[{"path":"app/z.sql","additions":%s,"deletions":%s}],"labels":[],"body":"","additions":%s,"deletions":%s,"changedFiles":1}' \
    "$3" "$4" "$3" "$4" > "$TMP/meta3.json"
  rm -f "$TMP/halt.json"
  FAKE_DIFF="$TMP/in.diff" python3 "$READ" --kind diff --meta "$TMP/meta3.json" -- pr diff 9 --repo o/r > "$TMP/out.diff" 2>"$TMP/err" \
    || { fail "$1: github-read từ chối ($(tail -1 "$TMP/err"))"; return; }
  plan="$(python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta3.json" --diff "$TMP/out.diff" 2>&1)"
  case "$plan" in
    *'"schema"'*) ok "$1: thấy DROP TABLE → cần người duyệt" ;;
    *) fail "$1: DROP TABLE lọt qua merge-policy: $plan" ;;
  esac
}
shape "header '@@ -0,0 +1 @@' không ghi số dòng" '@@ -0,0 +1 @@\n+DROP TABLE users;\n' 1 0
shape "'\\ No newline' giữa hunk" '@@ -1 +1,2 @@\n-old\n\\ No newline at end of file\n+new\n+DROP TABLE users;\n' 2 1

# Diff không qua github-read (header đếm thiếu): dòng '+' rơi ra ngoài hunk vẫn phải được tính, không được bỏ qua.
printf 'diff --git a/app/w.sql b/app/w.sql\n--- a/app/w.sql\n+++ b/app/w.sql\n@@ -0,0 +1 @@\n+select 1;\n+DROP TABLE users;\n' > "$TMP/short.diff"
plan="$(python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta.json" --diff "$TMP/short.diff" 2>&1)"
case "$plan" in
  *'"schema"'*) ok "header đếm thiếu: dòng '+' ngoài hunk vẫn được tính → cần người duyệt" ;;
  *) fail "header đếm thiếu: DROP TABLE ngoài hunk lọt qua merge-policy: $plan" ;;
esac

# Locale không phải UTF-8: diff (github-read ghi UTF-8) phải được đọc là UTF-8, nếu không U+2028 giữa DROP và TABLE
# không còn là khoảng trắng → từ khoá lọt.
python3 -c "import sys; open(sys.argv[1], 'wb').write('+++ b/app/v.sql\n@@ -0,0 +1 @@\n+DROP TABLE users;\n'.encode('utf-8'))" "$TMP/l1.diff"
# Chọn locale mà python thật sự giải mã khác UTF-8 (máy thiếu ISO8859-1 thì C bị ép thành C.UTF-8 → ca xanh giả).
LOC=""
for l in en_US.ISO8859-1 C; do
  enc="$(LC_ALL=$l LANG=$l PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 python3 -c 'import locale; print(locale.getpreferredencoding(False))')"
  case "$(printf %s "$enc" | tr 'A-Z' 'a-z' | tr -d '_-')" in utf8) ;; *) LOC=$l; break ;; esac
done
if [ -z "$LOC" ]; then
  echo "⚠ bỏ qua ca locale: máy không có locale nào giải mã khác UTF-8"
else
  plan="$(LC_ALL=$LOC LANG=$LOC PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta.json" --diff "$TMP/l1.diff" 2>&1)"
  case "$plan" in
    *'"schema"'*) ok "locale $LOC: DROP<U+2028>TABLE vẫn bị thấy → cần người duyệt" ;;
    *) fail "locale $LOC: DROP<U+2028>TABLE lọt qua merge-policy: $plan" ;;
  esac
fi

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_policy_odd_newlines: PASS"; exit 0; } || { echo "test_merge_policy_odd_newlines: FAIL ($FAILS)"; exit 1; }
