#!/usr/bin/env bash
# Test: createTask (scripts/governance/create_task.py) không tạo thẻ của repo khác trên board của repo đang đứng.
# 22/10: agent-workbench audit 5 repo app rồi chạy createTask không --repo, nên 8 thẻ của Goods / NFH /
# GeelyEx2 / OfficeReader / Humans nằm ở Project #1; builder của board đó chỉ làm trong worktree agent-workbench,
# không merge được PR repo khác, nên thẻ kẹt Blocked. Bây giờ: tiêu đề hoặc body nêu tên repo khác mà không
# có --repo (và không --here) thì script thoát exit 64 và dừng trước bước tạo issue.
# gh giả (đầu PATH) ghi từng lệnh vào calls.jsonl. Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$DEVKIT_DIR/scripts/governance/create_task.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/bin" "$TMP/repo"
export FAKE_LOG="$TMP/calls.jsonl"
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}, ensure_ascii=False) + "\n")
if a[:2] == ["issue", "create"]:
    print("https://github.com/ToanMobile/x/issues/1"); sys.exit(0)
if a[:2] == ["project", "item-add"]:
    print(json.dumps({"id": "PVTI_1"})); sys.exit(0)
if a[:2] in (["project", "item-edit"], ["label", "create"]):
    sys.exit(0)
sys.stderr.write("fake gh: unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
cd "$TMP/repo" && git init -q . && git remote add origin https://github.com/ToanMobile/agent-workbench.git
export PATH="$TMP/bin:$PATH"

run() { : > "$FAKE_LOG"; (cd "$TMP/repo" && python3 "$CT" "$@") >"$TMP/out" 2>&1; echo $?; }
# arg đứng sau cờ trong lệnh gh đầu tiên khớp (vd: --repo → tên repo, item-add → số project)
created_in() { python3 - <<'PY'
import json, os
for l in open(os.environ["FAKE_LOG"]):
    a = json.loads(l).get("gh", [])
    if a[:2] == ["issue", "create"]:
        print(a[a.index("--repo") + 1]); break
else:
    print("NONE")
PY
}
board_of() { python3 - <<'PY'
import json, os
for l in open(os.environ["FAKE_LOG"]):
    a = json.loads(l).get("gh", [])
    if a[:2] == ["project", "item-add"]:
        print(a[2]); break
else:
    print("NONE")
PY
}

# 1. Tiêu đề nêu repo khác, không --repo → từ chối, không tạo issue.
rc=$(run --title "🔧 [chore] Neighbours-From-Hell: đồng bộ card #28" --problem "Repo hết slot worktree" --ac "- [ ] runner-bw đã gỡ")
[ "$rc" = "64" ] && ok "1a nêu Neighbours-From-Hell, không --repo → exit 64" || fail "1a exit $rc (want 64)"
[ "$(created_in)" = "NONE" ] && ok "1b không gọi gh issue create" || fail "1b đã tạo issue ở $(created_in)"
grep -q -- "--repo ToanMobile/Neighbours-From-Hell" "$TMP/out" && ok "1c thông báo chỉ đúng lệnh --repo" || fail "1c thông báo thiếu gợi ý --repo"

# 2. Chỉ nêu repo khác trong body (Problem) cũng bị bắt.
rc=$(run --title "🐛 [bug] runner: kẹt thẻ" --problem "PR #82 ở Goods-Triple-Shelf-Match-3D chưa merge" --ac "- [ ] merge")
[ "$rc" = "64" ] && [ "$(created_in)" = "NONE" ] && ok "2 tên repo trong Problem → từ chối" || fail "2 exit $rc, created=$(created_in)"

# 3. --repo đúng → tạo ở repo đó, đẩy vào board của repo đó (Project #5).
rc=$(run --repo ToanMobile/Neighbours-From-Hell --title "🔧 [chore] Neighbours-From-Hell: đồng bộ card #28" --problem "x" --ac "- [ ] y")
[ "$rc" = "0" ] && ok "3a --repo → exit 0" || fail "3a exit $rc"
[ "$(created_in)" = "ToanMobile/Neighbours-From-Hell" ] && ok "3b issue tạo ở Neighbours-From-Hell" || fail "3b tạo ở $(created_in)"
[ "$(board_of)" = "5" ] && ok "3c đẩy vào Project #5" || fail "3c board $(board_of)"

# 4. --here: chủ ý để ở repo đang đứng dù nêu tên repo khác (thẻ về kit, lấy repo khác làm ví dụ).
rc=$(run --here --title "🐛 [bug] kit: ví dụ GeelyEx2 trong thông báo" --problem "x" --ac "- [ ] y")
[ "$rc" = "0" ] && [ "$(created_in)" = "ToanMobile/agent-workbench" ] && ok "4 --here giữ ở agent-workbench" || fail "4 exit $rc, created=$(created_in)"

# 5. Chỉ nêu repo của chính mình / không nêu repo nào → như cũ.
rc=$(run --title "🐛 [bug] agent-workbench: hook chặn nhầm" --problem "x" --ac "- [ ] y")
[ "$rc" = "0" ] && [ "$(created_in)" = "ToanMobile/agent-workbench" ] && ok "5 nêu repo của chính mình → như cũ" || fail "5 exit $rc, created=$(created_in)"

# 6. Câu tóm tắt nhanh (không --title) cũng bị kiểm.
rc=$(run "dọn worktree ở OfficeReader")
[ "$rc" = "64" ] && [ "$(created_in)" = "NONE" ] && ok "6 tóm tắt nêu OfficeReader → từ chối" || fail "6 exit $rc, created=$(created_in)"

# 7. --dry-run cũng từ chối (dry-run phải cho cùng kết quả với chạy thật).
rc=$(run --dry-run --title "🔧 [chore] GeelyEx2: rebase PR" --problem "x" --ac "- [ ] y")
[ "$rc" = "64" ] && ok "7 dry-run cũng từ chối" || fail "7 exit $rc"

# 8. --from-file: ticket của backlog trong checkout này, nêu repo khác làm ngữ cảnh → vẫn tạo ở repo đang đứng.
cat > "$TMP/backlog.md" <<'MD'
### TICKET-1: ⚡ [perf] context: cắt byte nạp đầu phiên cho 3 repo

## Problem
Đo ở GeelyEx2 và OfficeReader vượt trần.
MD
rc=$(run --from-file "$TMP/backlog.md" --ticket 1)
[ "$rc" = "0" ] && [ "$(created_in)" = "ToanMobile/agent-workbench" ] && ok "8 --from-file không bị chặn" || fail "8 exit $rc, created=$(created_in)"

# 9. Checkout của repo app, thẻ nhắc kit → tạo ở repo app, không gợi ý đẩy sang board kit.
git -C "$TMP/repo" remote set-url origin https://github.com/ToanMobile/GeelyEx2.git
rc=$(run --title "🔧 [chore] GeelyEx2: port #185 từ agent-workbench" --problem "chép fix" --ac "- [ ] đã port")
[ "$rc" = "0" ] && [ "$(created_in)" = "ToanMobile/GeelyEx2" ] && ok "9 thẻ app nhắc kit → ở repo app" || fail "9 exit $rc, created=$(created_in)"
git -C "$TMP/repo" remote set-url origin https://github.com/ToanMobile/agent-workbench.git

# 10. Tên NFH viết có dấu cách (tên trong registry) cũng bị bắt.
rc=$(run --title "🔧 [chore] đồng bộ card" --problem "Neighbours From Hell hết slot" --ac "- [ ] x")
[ "$rc" = "64" ] && ok "10 'Neighbours From Hell' → từ chối" || fail "10 exit $rc"

# 11. Ranh giới từ áp cho cả hai vế của "Neighbours-From-Hell|NFH": NFH dính vào chữ khác không tính.
rc=$(run --title "🐛 [bug] hooks: biến XNFH sai" --problem "x" --ac "- [ ] y")
[ "$rc" = "0" ] && [ "$(created_in)" = "ToanMobile/agent-workbench" ] && ok "11 'XNFH' không bị coi là NFH" || fail "11 exit $rc, created=$(created_in)"

# 12. --from-file chỉ miễn khi ticket thật sự đọc từ file (có --ticket); chỉ có --from-file mà thẻ lấy từ --title vẫn bị kiểm.
rc=$(run --from-file "$TMP/backlog.md" --title "🔧 [chore] GeelyEx2: rebase PR" --problem "x" --ac "- [ ] y")
[ "$rc" = "64" ] && ok "12 --from-file không --ticket vẫn bị kiểm" || fail "12 exit $rc"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
