#!/usr/bin/env bash
# Port từ upstream EricTechPro/super-board #67 (19/10):
# 1. github-read: validate() tách diff bằng splitlines() nên dòng thay đổi chứa VT, FF, U+2028 hay CR lẻ bị đọc thành
#    "diff hunk data missing" → 3 lần thử rồi halt cả board. Chỉ được tách theo \n, và đọc stdout của gh dạng bytes.
# 2. approval: GitHub chỉ điền closingIssuesReferences cho PR vào nhánh mặc định; PR vào nhánh khác (staging) thì lấy
#    "fixes/closes/resolves #N" cùng repo trong body, đọc trong cùng snapshot ghim head. Tham chiếu repo khác bị bỏ.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
APPROVAL="$ROOT/.claude/bin/super-board-approval.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-upstream-6667.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# --- 1. diff có ký tự VT, FF, U+2028 và CR lẻ trong dòng thêm ---
python3 - "$TMP/odd.diff" <<'PY'
import sys
body = ('diff --git a/x.txt b/x.txt\nnew file mode 100644\nindex 0000000..1111111\n--- /dev/null\n+++ b/x.txt\n'
        '@@ -0,0 +1,4 @@\n+form\ffeed\n+vertical\x0btab\n+line sep\n+lone\rcr\n')
open(sys.argv[1], 'wb').write(body.encode('utf-8'))
PY
printf '{"files":[{"path":"x.txt"}],"additions":4,"deletions":0}' > "$TMP/odd.meta"

# --- 2. trang GraphQL của approval; base/body/default do biến môi trường quyết định ---
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" pr diff 9 "*) cat "$FAKE_DIR/odd.diff" ;;
  *" graphql "*) python3 -c '
import json, os
pr = {"headRefOid": "a" * 40, "state": "OPEN", "baseRefName": os.environ["FAKE_BASE"], "body": os.environ["FAKE_BODY"],
      "closingIssuesReferences": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                                  "nodes": [{"number": 3, "repository": {"nameWithOwner": "o/r"}}] if os.environ["FAKE_BASE"] == "main" else []}}
print(json.dumps([{"data": {"repository": {"defaultBranchRef": {"name": "main"}, "pullRequest": pr}}}]))' ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 FAKE_DIR="$TMP"
export SB_GITHUB_READ_STRICT=1

python3 "$READ" --kind diff --meta "$TMP/odd.meta" -- pr diff 9 --repo o/r >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/halt.json" ] && ok "diff có VT/FF/U+2028/CR lẻ: đọc được, board không halt" \
  || fail "diff có VT/FF/U+2028/CR lẻ: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
cmp -s "$TMP/out" "$TMP/odd.diff" && ok "diff trả về nguyên byte (CR lẻ không thành \\n)" || fail "diff trả về bị đổi so với gh"
rm -f "$TMP/halt.json"

issues() {  # $1 base, $2 body → danh sách issue liên kết, hoặc ERR:<lỗi>
  FAKE_BASE="$1" FAKE_BODY="$2" python3 - "$APPROVAL" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('approval', sys.argv[1]); mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
try:
    head, found = mod.GitHub('o/r').pr(7)
    print(','.join(str(n) for n in sorted(found)) or 'none')
except Exception as error:
    print(f'ERR:{error}')
PY
}
got="$(issues staging 'Fixes #12 and closes: #14; resolves other/repo#99')"
[ "$got" = "12,14" ] && ok "PR vào staging: lấy fixes/closes cùng repo từ body, bỏ repo khác" || fail "PR vào staging: got '$got', want '12,14'"
got="$(issues staging 'mentions #12 without a keyword')"
[ "$got" = "none" ] && ok "PR vào staging: #N không kèm từ khoá thì không liên kết" || fail "không từ khoá: got '$got', want 'none'"
got="$(issues main 'Fixes #12')"
[ "$got" = "3" ] && ok "PR vào nhánh mặc định: chỉ dùng closingIssuesReferences như cũ" || fail "nhánh mặc định: got '$got', want '3'"

echo
[ "$FAILS" -eq 0 ] && { echo "test_upstream_66_67: PASS"; exit 0; } || { echo "test_upstream_66_67: FAIL ($FAILS)"; exit 1; }
