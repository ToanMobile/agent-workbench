#!/usr/bin/env bash
# Hồi quy (17/10, người dùng: "commit hết toàn bộ", merge gate của super-board): một commit chỉ đổi sổ trạng thái do chính gate ghi
# (.agents/regression_status.json, CHECKLIST.md…) bị `post-fix-gate --run-tests --full --diff <ref>` trả exit 3 "KHÔNG có thay đổi nào
# để kiểm toán" vì is_devkit_artifact bỏ chúng ra. Merge gate coi exit khác 0 là hỏng, nên PR đó không bao giờ gộp được, kể cả khi người
# dùng đã duyệt. Có --diff tường minh thì nội dung đó vẫn được kiểm như file thường (quét tĩnh, không cần test) và PASS được.
#   Giữ nguyên: cây sạch không --diff vẫn exit 3; một token lộ trong sổ đó vẫn bị chặn (exit 1).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mk() {   # <name>: repo có matrix + sổ trạng thái đã commit
  R="$TMP/$1"; mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt; echo '{"rows":[]}' > .agents/regression_status.json; echo "# checklist" > .agents/CHECKLIST.md
  printf '{"project":"t","rules":[{"component":"C","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"c","command":"true"}]}]}\n' \
    > .agents/regression_matrix.active.json
  git add -A && git commit -qm init
}
gate() {   # <name> <args…>: exit code của gate
  local n="$1"; shift
  ( cd "$TMP/$n" && CLAUDE_PROJECT_DIR="$TMP/$n" python3 "$DEVKIT_DIR/bin/post-fix-gate.py" "$@" > "$TMP/$n.out" 2>&1; echo $? )
}

mk a; echo '{"rows":[1]}' > .agents/regression_status.json; printf '# checklist\n- [x] a\n' > .agents/CHECKLIST.md
git add -A && git commit -qm "state only"
rc=$(gate a --run-tests --full --brief --diff HEAD~1)
[ "$rc" = 0 ] && ok "a commit of gate state only, audited with --diff → exit 0" \
  || { fail "state-only commit with --diff: exit $rc, expected 0"; tail -6 "$TMP/a.out"; }

mk b
rc=$(gate b --run-tests --full --brief)
[ "$rc" = 3 ] && ok "clean tree without --diff still exits 3 (never PASS for nothing)" || fail "clean tree: exit $rc, expected 3"

mk c; printf '{"rows":[1],"note":"ghp_%s"}\n' "abcdefghijklmnopqrstuvwxyz0123456789" > .agents/regression_status.json
git add -A && git commit -qm "state with a token"
rc=$(gate c --run-tests --full --brief --diff HEAD~1)
[ "$rc" = 1 ] && ok "a token in the state file is still rejected (exit 1)" || { fail "token in state: exit $rc, expected 1"; tail -6 "$TMP/c.out"; }

# 18/10 (người dùng bỏ luật 400 dòng): PR chỉ đổi config board super-board không có test nào khớp; config đó chỉ script super-board đọc.
mk d; mkdir -p .claude/super-board/configs; echo '{"merge_policy":{"auto_max_lines":400}}' > .claude/super-board/configs/t.json
git add -A && git commit -qm cfg; echo '{"merge_policy":{"auto_max_lines":0}}' > .claude/super-board/configs/t.json; git add -A && git commit -qm "cap 0"
rc=$(gate d --run-tests --full --brief --diff HEAD~1)
[ "$rc" = 0 ] && ok "a super-board config-only commit → exit 0" || { fail "super-board config only: exit $rc, expected 0"; tail -6 "$TMP/d.out"; }
mk e; mkdir -p .claude/other; echo '{"a":1}' > .claude/other/x.json; git add -A && git commit -qm x; echo '{"a":2}' > .claude/other/x.json; git add -A && git commit -qm x2
rc=$(gate e --run-tests --full --brief --diff HEAD~1)
[ "$rc" = 2 ] && ok "another .claude json still needs a test (exit 2)" || fail "other .claude json: exit $rc, expected 2"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_diff_state_only: all passed" || { echo "❌ test_gate_diff_state_only: $FAILS failed"; exit 1; }
