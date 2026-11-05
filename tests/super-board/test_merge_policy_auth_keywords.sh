#!/usr/bin/env bash
# #1028: từ khoá auth `bcrypt` khớp chuỗi con làm `libcrypto_utils` (GeelyEx2 PR #143) bị gắn human-gate auth (exit 7).
# Khớp theo ranh giới từ: tên thật (`bcrypt.hash(`, `require('bcrypt')`, `bcryptjs`) vẫn cần người, `libcrypto` thì auto.
# Đi đúng đường của merge gate: github-read (gh giả) → file diff → merge-policy. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-policy-money.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
printf '{"merge_policy":{"default":"auto"}}' > "$TMP/cfg.json"
printf '#!/usr/bin/env bash\ncat "$FAKE_DIFF"\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_GITHUB_READ_STRICT=1

# $1 tên, $2 dòng thêm, $3 dòng bị xoá ('' = không có), $4 mong đợi: money | auto
check() {
  python3 - "$TMP/in.diff" "$2" "$3" <<'PY'
import sys
rm = '-' + sys.argv[3] + '\n' if sys.argv[3] else ''
hunk = '@@ -1,1 +1,1 @@\n' + rm if rm else '@@ -1,1 +1,2 @@\n ctx\n'
body = ('diff --git a/app/x.ts b/app/x.ts\nindex 1111111..2222222 100644\n--- a/app/x.ts\n+++ b/app/x.ts\n'
        + hunk + '+' + sys.argv[2] + '\n')
open(sys.argv[1], 'wb').write(body.encode('utf-8'))
PY
  d=0; [ -n "$3" ] && d=1
  printf '{"files":[{"path":"app/x.ts","additions":1,"deletions":%s}],"labels":[],"body":"","additions":1,"deletions":%s,"changedFiles":1}' "$d" "$d" > "$TMP/meta.json"
  rm -f "$TMP/halt.json"
  FAKE_DIFF="$TMP/in.diff" python3 "$READ" --kind diff --meta "$TMP/meta.json" -- pr diff 9 --repo o/r > "$TMP/out.diff" 2>"$TMP/err" \
    || { fail "$1: github-read từ chối ($(tail -1 "$TMP/err"))"; return; }
  plan="$(python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta.json" --diff "$TMP/out.diff" 2>&1)"
  case "$4:$plan" in
    money:*'"money"'*) ok "$1: cần người duyệt" ;;
    auth:*'"auth"'*) ok "$1: cần người duyệt (auth)" ;;
    schema:*'"schema"'*) ok "$1: cần người duyệt" ;;
    auto:*'"human": []'*) ok "$1: vẫn auto" ;;
    *) fail "$1: muốn $4, được: $plan" ;;
  esac
}
check "đối chứng âm: libcrypto_utils (GeelyEx2 PR #143)" 'import libcrypto_utils' '' auto
check "đối chứng âm: libcrypto.so" 'load("libcrypto.so.3")' '' auto
check "bcrypt.hash(" 'const h = await bcrypt.hash(pw, 10);' '' auth
check "require('bcrypt')" "const b = require('bcrypt');" '' auth
check "bcryptjs" "import bcryptjs from 'bcryptjs'" '' auth
check "go crypto/bcrypt" 'import "golang.org/x/crypto/bcrypt"' '' auth
check "python import bcrypt" 'import bcrypt' '' auth
check "jwt.sign" 'const t = jwt.sign(payload, key);' '' auth
check "password_hash" 'user.password_hash = h' '' auth
check "service_role" 'const k = env.SUPABASE_SERVICE_ROLE;' '' auth

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_policy_auth_keywords: PASS"; exit 0; } || { echo "test_merge_policy_auth_keywords: FAIL ($FAILS)"; exit 1; }
