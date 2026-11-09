#!/usr/bin/env bash
# Hồi quy #889: super-board-merge-policy.py lọc file bị xoá bằng matches(p, protected) phân biệt chữ hoa, nên PR xoá
# `.ENV`, `config/app.KEYSTORE`, `Google-Services.json` không vào `delete-protected` và đi auto-merge.
# Sửa: bước lọc đầu so thêm nhóm nhạy cảm trên p.lower() (như nhánh phân loại). ĐỎ trên main f74556aa.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-policy-case.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
echo '{}' > "$TMP/cfg.json"
echo '{"labels":[],"body":"","files":[{"path":"x","additions":0,"deletions":0}]}' > "$TMP/meta.json"
# del_diff <path>: diff thủ công của một file bị xoá
del_diff() {
  printf 'diff --git a/%s b/%s\ndeleted file mode 100644\nindex 1111111..0000000\n--- a/%s\n+++ /dev/null\n@@ -1 +0,0 @@\n-x\n' "$1" "$1" "$1" > "$TMP/d.diff"
}
cats() { python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta.json" --diff "$TMP/d.diff" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" ".join(sorted(h["category"] for h in d["human"] if h["category"].startswith("delete-"))))'; }

for p in ".ENV" "config/app.KEYSTORE" "Google-Services.json" "sub/.Env.local" "k/Release.JKS"; do
  del_diff "$p"
  [ "$(cats)" = "delete-protected" ] && ok "xoá $p: delete-protected" || fail "xoá $p lọt cổng: [$(cats)]"
done
# Đối chứng: tên chỉ chứa chữ keystore, không phải đuôi .keystore → vẫn auto
del_diff "docs/keystore-notes.md"
[ -z "$(cats)" ] && ok "xoá docs/keystore-notes.md vẫn auto" || fail "docs/keystore-notes.md bị chặn nhầm: [$(cats)]"
# protected_paths tự khai giữ phân biệt hoa thường
echo '{"merge_policy":{"protected_paths":["docs/Keep/**"]}}' > "$TMP/cfg.json"
del_diff "docs/keep/a.md"
[ -z "$(cats)" ] && ok "protected_paths tự khai vẫn phân biệt hoa thường" || fail "glob tự khai bị hạ chữ: [$(cats)]"
# Ca dương: glob tự khai vẫn chặn đúng đường dẫn khớp (R2)
del_diff "docs/Keep/a.md"
[ "$(cats)" = "delete-protected" ] && ok "protected_paths tự khai chặn docs/Keep/a.md" || fail "docs/Keep/a.md lọt cổng: [$(cats)]"
# Danh sách tự khai THAY mặc định: nhóm nhạy cảm không được áp thêm (R1)
del_diff ".ENV"
[ -z "$(cats)" ] && ok "protected_paths tự khai thay mặc định: .ENV vẫn auto" || fail "nhóm nhạy cảm bị áp thêm khi tự khai: [$(cats)]"
# Tự khai CÓ nhóm nhạy cảm thì file hoa vẫn bị chặn
echo '{"merge_policy":{"protected_paths":["**/.env*"]}}' > "$TMP/cfg.json"
del_diff ".ENV"
[ "$(cats)" = "delete-protected" ] && ok "tự khai **/.env* chặn .ENV" || fail ".ENV lọt dù tự khai **/.env*: [$(cats)]"
echo '{"merge_policy":{"protected_paths":[]}}' > "$TMP/cfg.json"
del_diff ".ENV"
[ -z "$(cats)" ] && ok "protected_paths=[] vẫn tắt cổng" || fail "protected_paths=[] bị bỏ qua: [$(cats)]"
[ "$FAILS" -eq 0 ] || { echo "FAILS=$FAILS"; exit 1; }
echo "PASS"
