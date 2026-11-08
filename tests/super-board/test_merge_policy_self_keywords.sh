#!/usr/bin/env bash
# Bản đồng bộ kit c45755c9 (Idle-Plaza-3D PR #86, OfficeReader PR #300): dòng danh sách từ khoá
# `"keywords": ["jwt.sign", …]` của chính merge-policy là dòng thêm, nên policy tự gắn human-gate auth (exit 7).
# File định nghĩa luật (SELF_POLICY_PATHS) không bị quét từ khoá/pattern; file khác cùng PR, đổi tên vào đó
# hay đường dẫn chỉ trùng đuôi thì vẫn bị quét. Đi đúng đường của merge gate: github-read (gh giả) → diff → policy.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-policy-self.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
printf '{"merge_policy":{"default":"auto"}}' > "$TMP/cfg.json"
printf '#!/usr/bin/env bash\ncat "$FAKE_DIFF"\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_GITHUB_READ_STRICT=1

KW='        "keywords": ["jwt.sign", "password_hash", "service_role"],'

# $1 tên, $2 mong đợi (auth | auto), rồi từng cặp: "<đường dẫn cũ>|<đường dẫn mới>" "<dòng thêm>"
check() {
  name="$1" want="$2"; shift 2
  python3 - "$TMP/in.diff" "$TMP/meta.json" "$@" <<'PY'
import json, sys
out, files = "", []
args = sys.argv[3:]
for i in range(0, len(args), 2):
    old, new = args[i].split("|")
    out += f"diff --git a/{old} b/{new}\n"
    if old != new:
        out += f"similarity index 90%\nrename from {old}\nrename to {new}\n"
    out += f"index 1111111..2222222 100644\n--- a/{old}\n+++ b/{new}\n@@ -1,1 +1,2 @@\n ctx\n+{args[i + 1]}\n"
    files.append({"path": new, "additions": 1, "deletions": 0})
open(sys.argv[1], "wb").write(out.encode("utf-8"))
json.dump({"files": files, "labels": [], "body": "", "additions": len(files), "deletions": 0,
           "changedFiles": len(files)}, open(sys.argv[2], "w"))
PY
  rm -f "$TMP/halt.json"
  FAKE_DIFF="$TMP/in.diff" python3 "$READ" --kind diff --meta "$TMP/meta.json" -- pr diff 9 --repo o/r > "$TMP/out.diff" 2>"$TMP/err" \
    || { fail "$name: github-read từ chối ($(tail -1 "$TMP/err"))"; return; }
  plan="$(python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta.json" --diff "$TMP/out.diff" 2>&1)"
  case "$want:$plan" in
    auth:*'"auth"'*) ok "$name: cần người duyệt (auth)" ;;
    auto:*'"human": []'*) ok "$name: auto" ;;
    *) fail "$name: muốn $want, được: $plan" ;;
  esac
}
P=.claude/bin/super-board-merge-policy.py
S=.claude/skills/super-board/references/config-schema.json
check "danh sách từ khoá trong merge-policy.py (PR #86/#300)" auto "$P|$P" "$KW"
check "danh sách từ khoá trong config-schema.json" auto "$S|$S" '"keywords": ["jwt.sign", "bcrypt", "password_hash"] },'
check "đối chứng âm: cùng dòng trong file app" auth "app/x.ts|app/x.ts" "$KW"
check "đối chứng âm: PR có merge-policy.py và file app gọi jwt.sign" auth "$P|$P" "$KW" "app/x.ts|app/x.ts" 'const t = jwt.sign(p, k);'
check "đối chứng âm: đổi tên file app thành merge-policy.py" auth "app/token.ts|$P" 'const t = jwt.sign(p, k);'
check "đối chứng âm: đường dẫn chỉ trùng đuôi" auth "vendor/$P|vendor/$P" "$KW"
check "đối chứng âm: pattern bcrypt trong file app" auth "app/x.ts|app/x.ts" 'const h = bcrypt.hash(pw);'

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_policy_self_keywords: PASS"; exit 0; } || { echo "test_merge_policy_self_keywords: FAIL ($FAILS)"; exit 1; }
