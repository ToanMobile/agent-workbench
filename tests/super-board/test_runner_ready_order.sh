#!/usr/bin/env bash
# Test hồi quy #202 (22/10 11:36, agent-workbench): top_card_in_column lấy thẻ Ready đầu tiên theo thứ tự item của Project nên
# runner nhận #201 (feature, thêm sau cùng, trùng #151/#152/#180) và #200 trước các bản sửa runner #188-#190 đã Ready từ trước.
# Luật ở đây (chạy qua top_card_in_column thật, gh/issue_is_open là stub):
#  1. Ready: label priority:* trước, rồi bug trước thẻ khác, rồi số issue tăng dần. Cột khác giữ thứ tự board.
#  2. Thẻ Ready mà body nhắc repo khác (owner/repo khác config, hoặc đường dẫn checkout ngoài repo này) không được giao:
#     chuyển Blocked kèm block-template (dòng cuối `blocked-by:  -`), thẻ kế tiếp được giao.
#  3. Thẻ Ready mà mục Fix làm một thẻ đang mở khác (#N ở Ready/Building) không được giao: comment trùng đúng một lần, thẻ vẫn ở Ready.
# Chạy offline, tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-ready-order.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bodies" "$TMP/repo"
# stub đọc GitHub: `issue view N --json body ...` in body của $TMP/bodies/N (thiếu file = body rỗng)
# Giống github-read thật: kind issue từ chối --jq/-q/--template (exit 64) và in JSON {"number","title","body"} cho dạng đúng
# `--json number,title,body`. Stub cũ nhận cả `-q .body` và in chữ thô nên mã gọi sai dạng vẫn xanh (22 và 23/10).
cat > "$TMP/gh-read.py" <<'PY'
import json, os, sys
a = sys.argv[1:]
if any(x in ("-q", "--jq", "--template", "-t") for x in a):
    sys.stderr.write("stub github-read: --jq/-q/--template cannot pass with --kind issue\n")
    sys.exit(64)
n = a[a.index("view") + 1] if "view" in a else ""
p = os.path.join(os.environ["STUB_DIR"], "bodies", n)
if "body" in " ".join(a) and os.path.exists(p):
    sys.stdout.write(json.dumps({"number": int(n), "title": "t", "body": open(p).read()}))
PY
export STUB_DIR="$TMP"

unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/gh-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{"repo":{"remote":"https://github.com/ToanMobile/agent-workbench"}}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"; NO_DEVICE=false
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "status $1 $2" >> "$TMP/writes"; return 0; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
cd "$TMP/repo" || exit 1

item() { # id number status labels-json
  printf '{"id":"PVTI_%s","status":"%s","labels":%s,"content":{"type":"Issue","number":%s,"assignees":[]}}' "$1" "$3" "$4" "$2"
}
pick() { : > "$TMP/writes"; : > "$TMP/log"; if top_card_in_column "${1:-Ready}"; then echo "$TOP_ISSUE"; else echo NONE; fi; }

# ── 1. thứ tự: bug cũ đứng trước feature mới dù feature đứng trước trên board
PROJECT_ITEMS_JSON="{\"items\":[$(item 201 201 Ready '["feature"]'),$(item 188 188 Ready '["bug"]')]}"
p=$(pick)
[ "$p" = 188 ] && ok "bug #188 (cũ) được giao trước feature #201 (mới)" || fail "thứ tự bug-trước: giao #$p, cần #188"

# 1b. cùng loại: số issue nhỏ trước
PROJECT_ITEMS_JSON="{\"items\":[$(item 190 190 Ready '["bug"]'),$(item 188 188 Ready '["bug"]')]}"
p=$(pick)
[ "$p" = 188 ] && ok "cùng nhãn bug: số nhỏ #188 trước #190" || fail "số tăng dần: giao #$p, cần #188"

# 1c. priority đứng trước bug
PROJECT_ITEMS_JSON="{\"items\":[$(item 188 188 Ready '["bug"]'),$(item 210 210 Ready '["feature","priority:high"]')]}"
p=$(pick)
[ "$p" = 210 ] && ok "thẻ priority:high (feature) đứng trước bug không có priority" || fail "priority: giao #$p, cần #210"

# 1d. cột khác giữ thứ tự board
PROJECT_ITEMS_JSON="{\"items\":[$(item 201 201 QA '["feature"]'),$(item 188 188 QA '["bug"]')]}"
p=$(pick QA)
[ "$p" = 201 ] && ok "cột QA giữ thứ tự board (#201 trước)" || fail "QA bị sắp lại: giao #$p, cần #201"

# ── 2. body nhắc repo khác
printf '## Problem\nBug nằm ở https://github.com/ToanMobile/OfficeReader/blob/main/x.kt\n' > "$TMP/bodies/194"
printf '## Problem\nbug nội bộ, xem https://github.com/ToanMobile/agent-workbench/issues/5 và .claude/bin/x.sh\n' > "$TMP/bodies/195"
PROJECT_ITEMS_JSON="{\"items\":[$(item 194 194 Ready '["bug"]'),$(item 195 195 Ready '["bug"]')]}"
p=$(pick)
[ "$p" = 195 ] && ok "thẻ #194 nhắm repo khác bị bỏ qua, #195 (repo mình) được giao" || fail "repo khác: giao #$p, cần #195"
grep -q "status PVTI_194 Blocked" "$TMP/writes" && grep -q "issue comment 194" "$TMP/writes" && grep -q "blocked-by:  -" "$TMP/writes" \
  && ok "  … #194 chuyển Blocked kèm comment block-template" || fail "  #194 không được chuyển Blocked/comment: $(cat "$TMP/writes")"

printf '## Fix\nsửa ở /Volumes/Data/Toan/Other/app/run.sh\n' > "$TMP/bodies/196"
PROJECT_ITEMS_JSON="{\"items\":[$(item 196 196 Ready '["bug"]')]}"
p=$(pick)
[ "$p" = NONE ] && grep -q "status PVTI_196 Blocked" "$TMP/writes" && ok "đường dẫn checkout ngoài repo này → Blocked, không giao" || fail "đường dẫn ngoài repo: giao #$p"

# ── 3. Fix làm thẻ đang mở khác
printf '## Fix\nLàm #151 #152 như đã mô tả.\n\n## Acceptance Criteria\n1) ok\n' > "$TMP/bodies/201"
PROJECT_ITEMS_JSON="{\"items\":[$(item 201 201 Ready '["feature","priority:high"]'),$(item 151 151 Ready '["feature"]')]}"
: > "$TMP/writes"; : > "$TMP/log"; top_card_in_column Ready; p=$TOP_ISSUE   # same shell: the note mark lives in the state dir
[ "$p" = 151 ] && ok "thẻ #201 (đứng đầu) có Fix làm #151 (đang Ready) không được giao, #151 được giao" || fail "thẻ trùng: giao #$p, cần #151"
n=$(grep -c "issue comment 201" "$TMP/writes"); [ "$n" = 1 ] && ! grep -q "status PVTI_201" "$TMP/writes" \
  && ok "  … comment trùng đúng một lần, thẻ vẫn ở Ready" || fail "  comment trùng $n lần / thẻ bị chuyển cột: $(cat "$TMP/writes")"
: > "$TMP/writes"; top_card_in_column Ready >/dev/null
[ "$(grep -c "issue comment 201" "$TMP/writes")" = 0 ] && ok "  … tick sau không comment lại" || fail "  tick sau comment lại thẻ #201"

# thẻ nhắc #N chỉ trong Blocked by (không phải phần Fix) vẫn được giao
printf '## Fix\nsửa x.\n\n## Blocked by\n- #151\n' > "$TMP/bodies/202"
PROJECT_ITEMS_JSON="{\"items\":[$(item 202 202 Ready '["bug"]'),$(item 151 151 Ready '["feature"]')]}"
p=$(pick)
[ "$p" = 202 ] && ok "#N ngoài mục Fix không chặn thẻ" || fail "#N ngoài mục Fix chặn nhầm: giao #$p"

# ── R1: dạng nhìn giống repo khác nhưng không phải → KHÔNG chặn thẻ
mkdir -p "$TMP/repo/docs"
printf '## Problem\n![img](https://github.com/user-attachments/assets/1f2e3d4c-aaaa) và https://github.com/orgs/acme/settings, xem docs/notes.md#12 và docs/foo#3\n' > "$TMP/bodies/310"
PROJECT_ITEMS_JSON="{\"items\":[$(item 310 310 Ready '["bug"]')]}"
p=$(pick)
[ "$p" = 310 ] && ! grep -q "status PVTI_310" "$TMP/writes" && ok "R1: user-attachments/orgs/docs/x.md#N không bị coi là repo khác" || fail "R1: thẻ #310 bị chặn nhầm (giao #$p): $(cat "$TMP/log")"
printf '## Fix\nlàm theo ToanMobile/OfficeReader#7\n' > "$TMP/bodies/311"
PROJECT_ITEMS_JSON="{\"items\":[$(item 311 311 Ready '["bug"]')]}"
p=$(pick)
[ "$p" = NONE ] && grep -q "status PVTI_311 Blocked" "$TMP/writes" && ok "R1: <owner>/<repo>#N đứng riêng vẫn là repo khác → Blocked" || fail "R1: owner/repo#N không bị chặn (giao #$p)"

# ── R2: đường dẫn trong văn xuôi/stack trace không chặn; đường dẫn checkout trong Fix vẫn chặn
printf '## Problem\nổ /Volumes/Data còn 13 GiB; at /Users/alex/proj/x.kt:12 (stack trace)\n\n## Fix\nsửa script runner.\n' > "$TMP/bodies/312"
PROJECT_ITEMS_JSON="{\"items\":[$(item 312 312 Ready '["bug"]')]}"
p=$(pick)
[ "$p" = 312 ] && ! grep -q "status PVTI_312" "$TMP/writes" && ok "R2: /Volumes/Data trong văn xuôi và stack trace ở Problem không chặn thẻ" || fail "R2: thẻ #312 bị chặn nhầm (giao #$p)"

# ── R3: vòng A<->B chỉ giữ thẻ số lớn; 'afterwards' không cắt dòng Fix; ## Fixture không phải mục Fix
printf '## Fix\nlàm cùng #301.\n' > "$TMP/bodies/300"; printf '## Fix\nlàm cùng #300.\n' > "$TMP/bodies/301"
PROJECT_ITEMS_JSON="{\"items\":[$(item 301 301 Ready '["bug"]'),$(item 300 300 Ready '["bug"]')]}"
p=$(pick)
[ "$p" = 300 ] && ok "R3: tham chiếu chéo #300<->#301 → giao #300 (thẻ số nhỏ), không kẹt cả hai" || fail "R3: vòng A<->B giao #$p, cần #300"
printf '## Fix\nlàm #151 afterwards cũng sửa x.\n' > "$TMP/bodies/313"
PROJECT_ITEMS_JSON="{\"items\":[$(item 313 313 Ready '["bug"]'),$(item 151 151 Ready '["feature"]')]}"
p=$(pick)
[ "$p" = 151 ] && ok "R3: 'afterwards' không phải 'after' — Fix #151 vẫn tính là trùng" || fail "R3: 'afterwards' cắt dòng Fix (giao #$p)"
printf '## Fixture\ndữ liệu mẫu nhắc #151\n' > "$TMP/bodies/314"
PROJECT_ITEMS_JSON="{\"items\":[$(item 314 314 Ready '["bug"]'),$(item 151 151 Ready '["feature"]')]}"
p=$(pick)
[ "$p" = 314 ] && ok "R3: '## Fixture' không bị coi là mục Fix" || fail "R3: ## Fixture bị coi là Fix (giao #$p)"

# ── R4: dấu đã comment sống qua restart (file trong state dir, không chỉ biến của process)
grep -qx "201:#151" "$(dirname "$INFLIGHT_DIR")/dup-noted" 2>/dev/null && ok "R4: dấu 'đã comment #201' nằm trong state dir (sống qua restart)" || fail "R4: không có dấu comment trong state dir"

echo
[ "$FAILS" -eq 0 ] && echo "ALL PASS" || { echo "$FAILS FAIL"; exit 1; }
