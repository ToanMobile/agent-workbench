#!/usr/bin/env bash
# 01/11 (Idle-Plaza-3D PR #18): bước cài DevKit vào scratch (install.sh -t <scratch>) ghi .mcp.json / mcp_config.json. `git checkout -- .`
# chỉ trả lại file đã track, nên ở repo không track cũng không ignore .mcp.json, file đó ở lại scratch như một file chưa track.
# post-fix-gate --diff origin/main đếm nó vào `files`, không luật ma trận nào khớp ⇒ verify exit 2 ⇒ gate exit 11 với mọi PR của repo.
# Luật: sau bước cài, file chưa track (không bị ignore) do install.sh tạo ra bị xoá; file bị ignore mà verify cần (.agents/devkit) giữ
# nguyên; file của PR (đã track, kể cả khi install.sh ghi đè cùng tên) giữ đúng nội dung PR. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-installuntracked-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Không đọc config git của máy (core.hooksPath, core.excludesFile, commit.gpgsign, ~/.config/git/ignore): kết quả chỉ do fixture
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg"
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/deploy-x"; KIT="$TMP/kit"
# DevKit giả như install.sh thật: link .agents/devkit (repo ignore), .mcp.json + mcp_config.json + .gemini/settings.json (repo KHÔNG
# ignore), và ghi đè mcp_config.json mà PR đã track.
mkdir -p "$KIT/bin"
cat > "$KIT/bin/install.sh" <<'SH'
#!/usr/bin/env bash
kit="$(cd "$(dirname "$0")/.." && pwd)"
t=""; while [ $# -gt 0 ]; do case "$1" in -t) t="$2"; shift 2 ;; *) shift ;; esac; done
mkdir -p "$t/.agents/context" "$t/.gemini" && ln -sfn "$kit" "$t/.agents/devkit"
# như repo không track .gitignore: install tạo file ignore chưa track che file thật của nó; xoá file ignore thì file kia lộ ra
echo 'context/' > "$t/.agents/.gitignore"; echo ctx > "$t/.agents/context/essentials.md"
echo '{"mcpServers":{"install":{}}}' > "$t/.mcp.json"
echo INSTALL > "$t/mcp_config.json"
echo '{}' > "$t/.gemini/settings.json"
SH
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n.agents/devkit\n' > "$R/.gitignore"   # như Idle: .mcp.json, mcp_config.json KHÔNG bị ignore
mkdir -p "$R/.claude/super-board/configs" && echo '{}' > "$R/.claude/super-board/configs/x.json"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
mkdir -p "$R/.agents" && ln -s "$KIT" "$R/.agents/devkit"
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
# Hook post-checkout của repo (như relink của GeelyEx2) tạo file chưa track lúc gate dựng scratch, TRƯỚC bước cài DevKit:
# file đó không do install.sh tạo nên phải còn nguyên (ảnh chụp "trước" mới có tác dụng).
mkdir -p "$R/.git/hooks"
printf '#!/bin/sh\n[ "$3" = 1 ] && echo hook > pre-existing.txt\nexit 0\n' > "$R/.git/hooks/post-checkout"
chmod +x "$R/.git/hooks/post-checkout"
git -C "$R" config core.hooksPath "$R/.git/hooks"
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
# PR: một file Markdown + mcp_config.json của chính PR (đã track, cùng tên với file install.sh ghi đè)
echo doc > "$WT/README.md"; echo PR > "$WT/mcp_config.json"
git -C "$WT" add README.md mcp_config.json; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"
printf '{"files":[{"path":"README.md"},{"path":"mcp_config.json"}],"labels":[],"body":"","additions":2,"deletions":0,"changedFiles":2}' > "$TMP/pr5.meta"
echo "$H" > "$TMP/pr5.head"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr merge "*) echo "fake gh: dry run must not merge" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_review_fanout.sh"; sb_review_fixture "$TMP/bin"   # signed review PASS + CI checks (new gate preconditions)
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
# Lệnh verify đọc scratch như post-fix-gate --diff: file chưa track + file đổi so với base. Mỗi lệnh in dấu riêng rồi đỏ nếu sai.
cat > "$CFG" <<'JSON'
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[
 "u=$(git ls-files --others --exclude-standard); [ \"$u\" = pre-existing.txt ] || { echo UNTRACKED-L\"\"EFT $u; exit 1; }",
 "[ ! -e .mcp.json ] && [ ! -e .agents/context/essentials.md ] || { echo INSTALL-FILE-L\"\"EFT; exit 1; }",
 "[ -L .agents/devkit ] || { echo DEVKIT-G\"\"ONE; exit 1; }",
 "[ \"$(cat mcp_config.json)\" = PR ] || { echo PR-FILE-CH\"\"ANGED $(cat mcp_config.json); exit 1; }",
 "git diff --name-only origin/main HEAD | grep -qx mcp_config.json || { echo PR-FILE-UNS\"\"EEN; exit 1; }",
 "echo all-verify-ran"]}
JSON
( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" --dry-run ) >"$TMP/gate.log" 2>&1; rc=$?
! grep -q "UNTRACKED-LEFT" "$TMP/gate.log" \
  && ok "scratch chỉ còn file chưa track có từ trước khi cài (pre-existing.txt); file install.sh tạo (.mcp.json, .gemini/settings.json) đã xoá" \
  || fail "install.sh để lại file chưa track trong scratch: $(grep -m1 UNTRACKED-LEFT "$TMP/gate.log")"
! grep -q "DEVKIT-GONE" "$TMP/gate.log" && ok "link .agents/devkit (bị ignore) vẫn còn cho verify" || fail "xoá mất .agents/devkit"
! grep -q "PR-FILE-CHANGED" "$TMP/gate.log" && ok "mcp_config.json của PR giữ đúng nội dung PR" \
  || fail "file của PR bị đổi: $(grep -m1 PR-FILE-CHANGED "$TMP/gate.log")"
! grep -q "PR-FILE-UNSEEN" "$TMP/gate.log" && ok "file của PR vẫn nằm trong diff mà verify thấy" || fail "verify không thấy file của PR"
# Lệnh verify xanh không in output ra log gate: "6 command(s)" xanh là bằng chứng cả 6 lệnh kiểm ở trên đều qua.
grep -q "verified green against main (6 command(s))" "$TMP/gate.log" && [ "$rc" -eq 0 ] && ok "PR Markdown + config: 6/6 lệnh verify xanh, dry run exit 0" \
  || fail "gate exit $rc (want 0, mọi lệnh verify chạy): $(tail -5 "$TMP/gate.log")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_install_untracked: PASS"; exit 0; } || { echo "test_merge_gate_install_untracked: FAIL ($FAILS)"; exit 1; }
