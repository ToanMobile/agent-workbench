#!/usr/bin/env bash
# #1000 mục 1: super-board-qa-report.py --head/--base (ghim sha QA, T0255) không được lọt:
#  P1 dòng tiêu đề `[qa] [report] … @ <sha>` là lời khai; head chỉ được nhắc ở thân ("head <sha> tới sau lượt tôi chạy") không làm report
#     thành report của head (code cũ: token là tiền tố của head -> bỏ ghim).
#  P2 commit merge sửa tay (evil merge) sau sha QA -> code chưa QA (code cũ: --no-merges bỏ sót). P3 merge giải conflict bằng tay -> như P2.
#  P3c đối chứng: gộp main sạch sau sha QA -> qua. P3u: merge driver union sạch (dạng autosync #570) -> qua.
#  P1b/P1d chặn hồi quy của luật tiêu đề: token tiêu đề không phải commit, hay chỉ là sha main -> lời khai lấy từ thân.
#  P4 head bị amend / force-push (sha QA không còn là tổ tiên của head) với code khác -> từ chối (code cũ: bỏ qua).
#  P4c đối chứng: amend chỉ đổi message (cùng cây) -> qua.
#  P5 report không có sha ở tiêu đề, thân nêu hai sha nhánh, sha cũ còn code sau đó -> từ chối (code cũ: lấy sha "tốt nhất" -> qua).
#  P6 base không đọc được -> thoát 2 (không quyết định được), không lặng lẽ bỏ ghim (code cũ: thoát 0).
# Offline, git thật, gọi thẳng checker.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QA="$ROOT/.claude/bin/super-board-qa-report.py"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qa-stale.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
git init -q -b main "$R" && cd "$R" || exit 1
git config user.email t@t && git config user.name t && git config commit.gpgsign false
echo a > a && echo b > b && git add -A && git commit -qm M0
meta() {   # meta <comment-body>
  python3 -c 'import json,sys; print(json.dumps({"body":"","author":{"login":"owner"},"comments":[{"body":sys.argv[1],"authorAssociation":"OWNER","author":{"login":"owner"}}]}))' "$1" > "$TMP/meta.json"
}
check() {   # check <head> [base]: rc + stdout vào $rc/$out
  rc=0; out=$(python3 "$QA" --meta "$TMP/meta.json" --head "$1" --repo "$R" --base "${2:-main}" 2>"$TMP/err") || rc=$?
}
refused() { if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '^qa-report: '; then ok "từ chối: $1"; else fail "muốn exit 1 + qa-report: cho '$1' (exit $rc): $out $(cat "$TMP/err")"; fi; }
passed() { if [ "$rc" -eq 0 ]; then ok "qua: $1"; else fail "muốn exit 0 cho '$1' (exit $rc): $out $(cat "$TMP/err")"; fi; }
branch() {   # branch <name>: nhánh mới từ main, một commit code -> $Q
  git checkout -q -b "$1" main && echo "$1" > c && git add c && git commit -qm "$1: build" && Q=$(git rev-parse HEAD)
}
qa_at() { meta "[qa] [report] ✅ pass · PR #5 @ ${1:0:10}
Did: ran tests${2:+
$2}
✅ Done: AC1"; }

# P1
branch p1; echo fix >> c && git commit -qam "p1: code after QA"; H=$(git rev-parse HEAD)
qa_at "$Q" "Note: head ${H:0:8} arrived after my run"; check "$H"; refused "P1 tiêu đề nêu sha cũ, thân chỉ nhắc head"

# P1b (Grok plan review P2): token tiêu đề không phải commit -> không làm lời khai; sha cũ ở thân còn code sau -> vẫn từ chối
meta "[qa] [report] ✅ pass · PR #5 @ deadbee1
Did: tested ${Q:0:10}
✅ Done: AC1"; check "$H"; refused "P1b token tiêu đề không phải commit, thân nêu sha cũ"
# P1c (dạng chuẩn writing-standard: tiêu đề không có sha, sha ở thân + URL ảnh raw/<sha>/) nêu đúng head -> qua
meta "[qa] [report] ✅ pass
Did: tested ${H:0:10}
![s](https://raw.githubusercontent.com/o/r/${H}/docs/super-board/runs/x/s.png)
✅ Done: AC1"; check "$H"; passed "P1c dạng chuẩn, thân + URL ảnh nêu head"

# P1d (advisor): tiêu đề chỉ nêu sha của main (không phải sha nhánh) -> không làm lời khai; sha cũ ở thân còn code sau -> vẫn từ chối
meta "[qa] [report] ✅ pass · PR #5 @ $(git rev-parse --short=10 main)
Did: tested ${Q:0:10}
✅ Done: AC1"; check "$H"; refused "P1d tiêu đề chỉ nêu sha main, thân nêu sha cũ"

# P2 evil merge: gộp main, sửa tay code trong commit merge
branch p2; git checkout -q main && echo m2 > m && git add m && git commit -qm "main: m2"
git checkout -q p2 && git merge -q --no-ff --no-commit main 2>/dev/null; echo evil >> c && git add c && git commit -qm "merge main (hand-edited)"
[ "$(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = 3 ] || fail "P2 fixture: HEAD không phải commit merge"
H=$(git rev-parse HEAD); qa_at "$Q"; check "$H"; refused "P2 commit merge sửa tay sau sha QA"

# P3 merge giải conflict bằng tay
git checkout -q main && echo main-b > b && git commit -qam "main: b"
git checkout -q -b p3 "$(git rev-parse main~1)" && echo p3 > c && git add c && git commit -qm "p3: build" && Q=$(git rev-parse HEAD)
echo p3-b > b && git commit -qam "p3: b"; Q=$(git rev-parse HEAD)
git merge -q main >/dev/null 2>&1; echo resolved > b && git add b && git commit -qm "merge main (conflict resolved)" -q
H=$(git rev-parse HEAD); qa_at "$Q"; check "$H"; refused "P3 merge giải conflict bằng tay sau sha QA"

# P3c gộp main sạch sau sha QA
branch p3c; git checkout -q main && echo m3 > m3 && git add m3 && git commit -qm "main: m3"
git checkout -q p3c && git merge -q --no-edit main; H=$(git rev-parse HEAD)
qa_at "$Q"; check "$H"; passed "P3c chỉ gộp main sạch sau sha QA"

# P3u (advisor: autosync #570 đẩy merge(X, base) dựng bằng driver gộp): file merge=union hai phía cùng sửa, `git merge` tự gộp
#     sau sha QA -> merge sạch theo driver, qua.
git checkout -q main && printf 'log.txt merge=union\n' > .gitattributes && echo base > log.txt && git add .gitattributes log.txt \
  && git commit -qm "main: union file"
branch p3u; echo pr-line >> log.txt && git commit -qam "p3u: log line" && Q=$(git rev-parse HEAD)
git checkout -q main && echo main-line >> log.txt && git commit -qam "main: log line"
git checkout -q p3u && git merge -q --no-edit main >/dev/null 2>&1; H=$(git rev-parse HEAD)
[ "$(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = 3 ] || fail "P3u fixture: merge union không tạo commit merge"
qa_at "$Q"; check "$H"; passed "P3u merge driver union sạch sau sha QA"

# P4 amend có đổi code
branch p4; echo amended >> c && git add c && git commit -q --amend -m "p4: build (amended)"; H=$(git rev-parse HEAD)
qa_at "$Q"; check "$H"; refused "P4 sha QA bị amend khỏi lịch sử head, code khác"

# P4c amend chỉ đổi message
branch p4c; git commit -q --amend -m "p4c: build (message only)"; H=$(git rev-parse HEAD)
qa_at "$Q"; check "$H"; passed "P4c amend chỉ đổi message (cùng cây)"

# P5 không sha ở tiêu đề; thân nêu Q0 (còn code sau) và Q1 (không code sau)
branch p5; Q0=$Q; echo more >> c && git commit -qam "p5: more code"; Q1=$(git rev-parse HEAD)
mkdir -p docs/super-board/runs/x && echo ok > docs/super-board/runs/x/s.md && git add docs && git commit -qm "qa evidence"; H=$(git rev-parse HEAD)
meta "[qa] [report] ✅ pass · PR #5
Did: tested ${Q0:0:10} and ${Q1:0:10}
✅ Done: AC1"; check "$H"; refused "P5 thân nêu hai sha nhánh, sha cũ còn code sau"

# P6 base không đọc được
qa_at "$Q0"; check "$H" no-such-base
[ "$rc" -eq 2 ] && ok "P6 base không đọc được -> thoát 2" || fail "P6 muốn exit 2 (exit $rc): $out $(cat "$TMP/err")"

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
