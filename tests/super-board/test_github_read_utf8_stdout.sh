#!/usr/bin/env bash
# #124: github-read ghi stdout bằng UTF-8 bytes, không theo locale. Dưới locale không UTF-8 đặt tường minh
# (en_US.ISO8859-1, PYTHONUTF8=0, PYTHONCOERCECLOCALE=0): U+2028 làm UnicodeEncodeError, NEL (U+0085) bị mã hoá thành
# byte 0x85 rồi merge-policy đọc lại bằng UTF-8 thành U+FFFD → DROP<NEL>TABLE lọt always_human.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-read-utf8.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
printf '{"files":[{"path":"app/x.sql","additions":1,"deletions":0}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/meta.json"
printf '{"merge_policy":{"default":"auto"}}' > "$TMP/cfg.json"
printf '#!/usr/bin/env bash\ncat "$FAKE_DIFF"\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_GITHUB_READ_STRICT=1

check() {  # $1 tên, $2 ký tự ngăn trước DROP, $3 ký tự giữa DROP và TABLE (python escape)
  python3 - "$TMP/in.diff" "$2" "$3" <<'PY'
import sys
before = sys.argv[2].encode().decode('unicode_escape')
between = sys.argv[3].encode().decode('unicode_escape')
body = ('diff --git a/app/x.sql b/app/x.sql\nnew file mode 100644\nindex 0000000..1111111\n--- /dev/null\n+++ b/app/x.sql\n'
        '@@ -0,0 +1,1 @@\n+select 1;' + before + 'DROP' + between + 'TABLE users;\n')
open(sys.argv[1], 'wb').write(body.encode('utf-8'))
PY
  rm -f "$TMP/halt.json"
  FAKE_DIFF="$TMP/in.diff" LC_ALL=en_US.ISO8859-1 PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 \
    python3 "$READ" --kind diff --meta "$TMP/meta.json" -- pr diff 9 --repo o/r > "$TMP/out.diff" 2>"$TMP/err"
  rc=$?
  if [ "$rc" != 0 ]; then fail "$1: github-read rc=$rc ($(tail -1 "$TMP/err"))"; return; fi
  if cmp -s "$TMP/in.diff" "$TMP/out.diff"; then ok "$1: output khớp byte với UTF-8 gốc"; else fail "$1: output không khớp byte"; fi
  plan="$(python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta.json" --diff "$TMP/out.diff" 2>&1)"
  case "$plan" in *'"schema"'*) ok "$1: merge-policy ra schema" ;; *) fail "$1: DROP TABLE lọt: $plan" ;; esac
}
check "U+2028 trước DROP" '\u2028' ' '
check "NEL giữa DROP và TABLE" ' ' '\x85'
[ "$FAILS" = 0 ] || { echo "$FAILS lỗi"; exit 1; }
echo "OK"
