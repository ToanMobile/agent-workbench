#!/usr/bin/env bash
# #775 (gộp thêm, review #772 r18/r18b): merge gate gộp base vào scratch bằng `MERGE_ERR=$(git merge … 2>&1)`.
#   1. Hook commit-msg để một tiến trình nền giữ stderr ⇒ `$(…)` chờ tới khi tiến trình đó thoát: gate treo. Luật: stderr của git merge
#      ghi ra file, gate thoát 5 ngay khi git merge thoát, vẫn in lời hook.
#   2. Xung đột thật: dòng `CONFLICT (…)` của git bị bắt vào biến rồi bỏ. Luật: in tên file xung đột VÀ các dòng CONFLICT của git.
#   3. Bước dọn file chưa track sau khi cài DevKit vào scratch giữ `.agents/devkit` kể cả khi repo KHÔNG ignore nó (nhánh bảo vệ riêng):
#      verify vẫn thấy link.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mergestderr-test.XXXXXX")"
SLEEPER_PIDS="$TMP/sleepers"
cleanup_tmp() {
  # Tiến trình nền của hook giả (ca 1): giết đúng pid nó tự ghi, không giết theo tên.
  if [ -f "$SLEEPER_PIDS" ]; then while read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$SLEEPER_PIDS"; fi
  rm -rf "$TMP"
}
trap cleanup_tmp EXIT
# Không đọc config git của máy (core.hooksPath, core.excludesFile, commit.gpgsign…): kết quả chỉ do fixture
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg"
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
# Token giả ghép lúc chạy (không có nguyên văn trong file: bộ quét secret đọc diff); hook ca 1 in nó ra stderr.
FAKE_TOK="gh""p_$(printf 'Q%.0s' $(seq 1 30))"; export FAKE_TOK

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

# repo_init <dir> <gitignore>: origin bare + repo có config board giả
repo_init() {
  git init -q --bare -b main "$1.git"
  git init -q -b main "$1"
  git -C "$1" config user.email t@example.invalid; git -C "$1" config user.name t
  printf "$2" > "$1/.gitignore"
  mkdir -p "$1/.claude/super-board/configs" && echo '{}' > "$1/.claude/super-board/configs/x.json"
  echo a > "$1/a"; echo s > "$1/shared"; git -C "$1" add -A; git -C "$1" commit -qm init
  git -C "$1" remote add origin "$1.git"; git -C "$1" push -q origin main
}
# pr_branch <repo> <N> <file> <nội dung>: nhánh issue-<N>-x đổi <file>, đã đẩy; metadata cho gh giả
pr_branch() {
  local wt="$1/.claude/worktrees/pr-$2"
  git -C "$1" branch -q --no-track "issue-$2-x" main
  git -C "$1" worktree add -q "$wt" "issue-$2-x"
  echo "$4" > "$wt/$3"; git -C "$wt" add "$3"; git -C "$wt" commit -qm "card $2"
  git -C "$1" push -q origin "issue-$2-x"
  git -C "$1" rev-parse "issue-$2-x" > "$TMP/pr$2.head"
  git -C "$1" diff origin/main "issue-$2-x" > "$TMP/pr$2.diff"
  # số dòng thêm/xoá đúng như diff: github-read so với diff và dừng (halt) khi lệch
  local ad
  ad=$(git -C "$1" diff --numstat origin/main "issue-$2-x" | awk '{a += $1; d += $2} END {printf "\"additions\":%d,\"deletions\":%d", a, d}')
  printf '{"files":[{"path":"%s"}],"labels":[],"body":"",%s,"changedFiles":1}' "$3" "$ad" > "$TMP/pr$2.meta"
}
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo ran; exit 0"]}' > "$CFG"

# ── 1 + 2: hook để tiến trình nền giữ stderr; xung đột thật
R="$TMP/repo"
repo_init "$R" '/.claude/worktrees/\n'
pr_branch "$R" 5 b b5
pr_branch "$R" 6 shared pr6
git -C "$R" checkout -q main; echo c > "$R/c"; echo main > "$R/shared"; git -C "$R" add c shared; git -C "$R" commit -qm main-moves
git -C "$R" push -q origin main
mkdir -p "$TMP/hooks"
cat > "$TMP/hooks/commit-msg" <<SH
#!/bin/sh
echo "guard-check: commit gop bi tu choi (HOOK-REF""USED)" >&2
echo "auth token=\$FAKE_TOK" >&2
# tiến trình nền thừa hưởng stderr của hook (ống của \$(…) cũ) và sống 15 s
sleep 15 >&2 &
echo \$! >> "$SLEEPER_PIDS"
exit 1
SH
chmod +x "$TMP/hooks/commit-msg"
git -C "$R" config core.hooksPath "$TMP/hooks"
start=$(date +%s)
( cd "$R/.claude/worktrees/pr-5" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$(cat "$TMP/pr5.head")" --dry-run ) >"$TMP/hook.log" 2>&1; rc=$?
took=$(( $(date +%s) - start ))
[ "$rc" -eq 5 ] && ok "hook refusal: exit 5 as before" || fail "hook refusal: exit $rc (want 5): $(tail -3 "$TMP/hook.log")"
[ "$took" -lt 10 ] && ok "a hook's background process holding stderr does not hang the gate (${took}s)" \
  || fail "gate waited ${took}s for the hook's background process (stderr captured through a pipe)"
grep -q "HOOK-REFUSED" "$TMP/hook.log" && ok "  … the hook's reason is still printed" || fail "  … hook reason lost: $(grep merge-gate "$TMP/hook.log" | tail -3)"
# Lời hook là chữ tuỳ ý: token trong đó bị che trước khi vào log gate (log runner / train, review Claude P3).
grep -q "$FAKE_TOK" "$TMP/hook.log" && fail "  … a token printed by the hook reached the gate log" || ok "  … a token printed by the hook is redacted in the gate log"
# Hook im lặng (exit 1, không in gì): pipefail không được biến "không có dòng nào" thành "bộ che không nạp được" (OCR r2).
mkdir -p "$TMP/hooks-silent"; printf '#!/bin/sh\nexit 1\n' > "$TMP/hooks-silent/commit-msg"; chmod +x "$TMP/hooks-silent/commit-msg"
git -C "$R" config core.hooksPath "$TMP/hooks-silent"
( cd "$R/.claude/worktrees/pr-5" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$(cat "$TMP/pr5.head")" --dry-run ) >"$TMP/silent.log" 2>&1; rc=$?
[ "$rc" -eq 5 ] && grep -q "refused the local merge commit" "$TMP/silent.log" && ! grep -q "redactor could not be loaded" "$TMP/silent.log" \
  && ok "silent hook: exit 5, no false 'redactor could not be loaded'" || fail "silent hook: exit $rc: $(grep merge-gate "$TMP/silent.log" | tail -2)"
grep -q "rebase pass for the Builder lane" "$TMP/hook.log" && fail "  … hook refusal mislabelled as a rebase pass" || ok "  … hook refusal is not reported as a rebase pass"

git -C "$R" config --unset core.hooksPath
( cd "$R/.claude/worktrees/pr-5" && bash "$GATE" --config "$CFG" --pr 6 --expect-head "$(cat "$TMP/pr6.head")" --dry-run ) >"$TMP/conf.log" 2>&1; rc=$?
[ "$rc" -eq 5 ] && grep -q "conflicts: shared" "$TMP/conf.log" && ok "real conflict: exit 5, conflicting file named" \
  || fail "real conflict: exit $rc: $(grep merge-gate "$TMP/conf.log" | tail -3)"
grep -q "CONFLICT (add/add\|CONFLICT (content" "$TMP/conf.log" && ok "  … git's CONFLICT line is printed" \
  || fail "  … git's CONFLICT line dropped: $(grep merge-gate "$TMP/conf.log" | tail -3)"

# ── 3: repo KHÔNG ignore .agents/devkit; install.sh giả tạo link đó + một file chưa track. Bước dọn xoá file kia, giữ link.
R2="$TMP/repo2"; KIT="$TMP/kit"
mkdir -p "$KIT/bin"
cat > "$KIT/bin/install.sh" <<'SH'
#!/usr/bin/env bash
kit="$(cd "$(dirname "$0")/.." && pwd)"
t=""; while [ $# -gt 0 ]; do case "$1" in -t) t="$2"; shift 2 ;; *) shift ;; esac; done
mkdir -p "$t/.agents" && ln -sfn "$kit" "$t/.agents/devkit"
echo '{}' > "$t/.mcp.json"
SH
repo_init "$R2" '/.claude/worktrees/\n'
mkdir -p "$R2/.agents" && ln -s "$KIT" "$R2/.agents/devkit"
pr_branch "$R2" 7 README.md doc
CFG2="$TMP/cfg2.json"
cat > "$CFG2" <<'JSON'
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[
 "[ -L .agents/devkit ] || { echo DEVKIT-G\"\"ONE; exit 1; }",
 "[ ! -e .mcp.json ] || { echo INSTALL-FILE-L\"\"EFT; exit 1; }"]}
JSON
( cd "$R2/.claude/worktrees/pr-7" && bash "$GATE" --config "$CFG2" --pr 7 --expect-head "$(cat "$TMP/pr7.head")" --dry-run ) >"$TMP/dk.log" 2>&1; rc=$?
! grep -q "DEVKIT-GONE" "$TMP/dk.log" && ok ".agents/devkit not ignored by the repo: the link is kept for verify" || fail "the cleanup deleted the .agents/devkit link"
! grep -q "INSTALL-FILE-LEFT" "$TMP/dk.log" && ok "  … other untracked install files are still removed" || fail "  … .mcp.json left in the scratch"
[ "$rc" -eq 0 ] && grep -q "verified green against main (2 command(s))" "$TMP/dk.log" && ok "  … dry run exit 0, both verify commands green" \
  || fail "  … gate exit $rc: $(tail -4 "$TMP/dk.log")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_merge_stderr: PASS"; exit 0; } || { echo "test_merge_gate_merge_stderr: FAIL ($FAILS)"; exit 1; }
