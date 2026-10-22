#!/usr/bin/env bash
# #123: từ khoá always_human (schema) bỏ sót câu SQL phá huỷ hợp lệ: `DROP/**/TABLE` (comment = khoảng trắng),
# `ALTER TABLE x DROP email` (COLUMN tuỳ chọn), `TRUNCATE x` (TABLE tuỳ chọn).
# Đi đúng đường của merge gate: github-read (gh giả) → file diff → merge-policy. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-policy-sql.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
printf '{"merge_policy":{"default":"auto"}}' > "$TMP/cfg.json"
printf '#!/usr/bin/env bash\ncat "$FAKE_DIFF"\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_GITHUB_READ_STRICT=1

# $1 tên, $2 dòng thêm, $3 dòng bị xoá ('' = không có), $4 mong đợi: schema | auto
check() {
  python3 - "$TMP/in.diff" "$2" "$3" <<'PY'
import sys
rm = '-' + sys.argv[3] + '\n' if sys.argv[3] else ''
hunk = '@@ -1,1 +1,1 @@\n' + rm if rm else '@@ -1,1 +1,2 @@\n ctx\n'
body = ('diff --git a/app/x.sql b/app/x.sql\nindex 1111111..2222222 100644\n--- a/app/x.sql\n+++ b/app/x.sql\n'
        + hunk + '+' + sys.argv[2] + '\n')
open(sys.argv[1], 'wb').write(body.encode('utf-8'))
PY
  d=0; [ -n "$3" ] && d=1
  printf '{"files":[{"path":"app/x.sql","additions":1,"deletions":%s}],"labels":[],"body":"","additions":1,"deletions":%s,"changedFiles":1}' "$d" "$d" > "$TMP/meta.json"
  rm -f "$TMP/halt.json"
  FAKE_DIFF="$TMP/in.diff" python3 "$READ" --kind diff --meta "$TMP/meta.json" -- pr diff 9 --repo o/r > "$TMP/out.diff" 2>"$TMP/err" \
    || { fail "$1: github-read từ chối ($(tail -1 "$TMP/err"))"; return; }
  plan="$(python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta.json" --diff "$TMP/out.diff" 2>&1)"
  case "$4:$plan" in
    schema:*'"schema"'*) ok "$1: cần người duyệt" ;;
    auto:*'"human": []'*) ok "$1: vẫn auto" ;;
    *) fail "$1: muốn $4, được: $plan" ;;
  esac
}
check "DROP/**/TABLE" 'DROP/**/TABLE users;' '' schema
check "DROP/*x*/TABLE (comment có chữ)" 'DROP/*x*/TABLE users;' '' schema
check "ALTER TABLE ... DROP email (không COLUMN)" 'ALTER TABLE users DROP email;' '' schema
check "đối chứng âm: ALTER TABLE đứng một mình" 'ALTER TABLE users' '' auto
check "TRUNCATE users (không TABLE)" 'TRUNCATE users;' '' schema
check "TRUNCATE TABLE users (đối chứng)" 'TRUNCATE TABLE users;' '' schema
check "đối chứng âm: chỉ dòng '-' có DROP/TRUNCATE" 'select 2;' 'TRUNCATE users; ALTER TABLE users DROP email;' auto
check "đối chứng âm: ALTER TABLE ADD COLUMN" 'ALTER TABLE users ADD COLUMN age int;' '' auto
check "đối chứng âm: 'drop' trong câu khác" 'const dropdown = 1; // truncated' '' auto
check "đối chứng âm: comment thường" '/* note */ select 1;' '' auto

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_policy_sql_forms: PASS"; exit 0; } || { echo "test_merge_policy_sql_forms: FAIL ($FAILS)"; exit 1; }
