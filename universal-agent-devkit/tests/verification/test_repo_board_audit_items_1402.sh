#!/usr/bin/env bash
# #1402 (audit Antigravity của PR #1394 @a060008a, 3 mục nhỏ): hai mục đầu nằm ở đây, mục 3 (gh giả thoát mã 4) là ca 3g
# của test_repo_board_and_context.sh.
# (1) repo_board.py: slug đọc từ `.claude/super-board/active` có `/`, `\` hoặc bằng `.`/`..` phải bị từ chối, không được
#     đọc một file JSON nằm NGOÀI thư mục configs (vd `../x` -> `.claude/super-board/x.json`).
# (2) block_dangerous_git_main.py: kit cài kiểu copy (hook nằm ở `<repo>/.claude/hooks/`, không phải symlink về kit) thì
#     `scripts/governance` cạnh hook không tồn tại; cảnh báo `gh project item-list` sai board phải lấy repo_board.py từ
#     `<repo>/.agents/devkit/scripts/governance` thay vì im lặng.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
unset CLAUDE_PROJECT_DIR
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)" || exit 1
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
RB="$DK/scripts/governance/repo_board.py"

cfg() {  # cfg <file> <number> <title> [remote repo]
  printf '{"version": 1, "project": {"owner": "ToanMobile", "title": "%s", "number": %s}, "repo": {"remote": "https://github.com/ToanMobile/%s"}, "base_branch": "main"}\n' \
    "$3" "$2" "${4:-Elsewhere}" > "$1"
}
board_num() {  # board_num <repo dir> -> số board repo_board.py chọn
  python3 -I -c 'import sys
sys.dont_write_bytecode = True
import importlib.util
s = importlib.util.spec_from_file_location("_rb", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
b = m.resolve_board(sys.argv[2]); print(b["number"] if b else "none")' "$RB" "$1" 2>&1
}

# ── (1) slug trong file active ──────────────────────────────────────────────────────────────────────────────────────
# Chỉ office.json khớp origin: mọi slug bị từ chối phải rơi về #2. Các file còn lại là đích mà slug xấu trỏ tới.
R="$T/OfficeReader"
mkdir -p "$R/.claude/super-board/configs/sub"
(cd "$R" && git init -q -b main && git remote add origin https://github.com/ToanMobile/OfficeReader.git)
cfg "$R/.claude/super-board/configs/office.json" 2 "OfficeReader" OfficeReader
cfg "$R/.claude/super-board/x.json" 99 "Outside"                 # NGOÀI configs/ (slug `../x`, `..\x` trên Windows)
cfg "$R/.claude/super-board/configs/sub/y.json" 98 "Nested"      # slug `sub/y`
cfg "$R/.claude/super-board/configs/...json" 97 "DotDot"         # slug `..` -> `...json`
cfg "$R/.claude/super-board/configs/..json" 96 "Dot"             # slug `.`  -> `..json`
cfg "$R/.claude/super-board/configs/sub\\y.json" 95 "Backslash"  # slug `sub\y`
cfg "$R/.claude/super-board/configs/..\\x.json" 94 "Backslash2"  # slug `..\x`

for slug in '../x' 'sub/y' '..' '.' 'sub\y' '..\x'; do
  printf '%s\n' "$slug" > "$R/.claude/super-board/active"
  n="$(board_num "$R")"
  [ "$n" = 2 ] && ok "(1) slug active '$slug' bị từ chối, rơi về config khớp origin #2" \
    || fail "(1) slug active '$slug' không bị từ chối: board=$n (muốn 2)"
done
# slug hợp lệ vẫn được chọn (không siết quá tay)
cfg "$R/.claude/super-board/configs/other-1.x.json" 7 "Other"
printf 'other-1.x\n' > "$R/.claude/super-board/active"
n="$(board_num "$R")"
[ "$n" = 7 ] && ok "(1) slug active hợp lệ 'other-1.x' vẫn được chọn (#7)" || fail "(1) slug active hợp lệ bị từ chối: board=$n (muốn 7)"
rm -f "$R/.claude/super-board/active"

# ── (2) bố cục copy: hook nằm ở <repo>/.claude/hooks, kit ở <repo>/.agents/devkit ─────────────────────────────────────
mkdir -p "$R/.claude/hooks" "$R/.agents/devkit/scripts/governance"
cp "$DK"/hooks/*.sh "$DK"/hooks/*.py "$R/.claude/hooks/"
cp "$RB" "$R/.agents/devkit/scripts/governance/repo_board.py"
[ ! -e "$R/.claude/scripts/governance" ] || fail "(2) fixture sai: scripts/governance cạnh hook lại tồn tại"
payload() { printf '{"tool_name":"Bash","tool_input":{"command":"gh project item-list %s --owner ToanMobile"},"cwd":"%s"}' "$1" "$R"; }

out="$(payload 1 | CLAUDE_PROJECT_DIR="$R" bash "$R/.claude/hooks/block-dangerous-git.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'board của repo này là #2' \
  && ok "(2) hook cài kiểu copy vẫn cảnh báo sai board (#2) qua .agents/devkit/scripts/governance" \
  || fail "(2) hook cài kiểu copy im lặng khi sai board: rc=$rc out=$out"
out="$(payload 2 | CLAUDE_PROJECT_DIR="$R" bash "$R/.claude/hooks/block-dangerous-git.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "(2) hook cài kiểu copy im lặng khi đúng board #2" \
  || fail "(2) hook cài kiểu copy cảnh báo nhầm khi đúng board: rc=$rc out=$out"
# CLAUDE_PROJECT_DIR không đặt: vẫn tìm được kit qua vị trí của chính hook (<repo>/.claude/hooks)
out="$(payload 1 | (cd "$R" && bash "$R/.claude/hooks/block-dangerous-git.sh" 2>&1))"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'board của repo này là #2' \
  && ok "(2) hook cài kiểu copy cảnh báo cả khi không có CLAUDE_PROJECT_DIR" \
  || fail "(2) hook cài kiểu copy im lặng khi không có CLAUDE_PROJECT_DIR: rc=$rc out=$out"
[ -z "$(find "$R/.agents/devkit" -name __pycache__ -print 2>/dev/null)" ] \
  && ok "(2) không ghi __pycache__ vào .agents/devkit" || fail "(2) hook ghi __pycache__ vào .agents/devkit"

[ "$FAILS" -eq 0 ] && { echo "✅ test_repo_board_audit_items_1402"; exit 0; }
echo "❌ test_repo_board_audit_items_1402: $FAILS failure(s)"; exit 1
