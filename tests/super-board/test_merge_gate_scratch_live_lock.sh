#!/usr/bin/env bash
# 03/11 (PR #940): scratch .merge-scratch-vHICXz bị xoá GIỮA lúc verify chạy. Thủ phạm: một phiên Grok ở main checkout, dọn đồ của train
# PR #930, thấy scratch trong `git worktree list` và chạy `git worktree remove <scratch>` trần (rmscratch:0, 13:07:17): cây sạch nên git
# gỡ luôn, suite đang chạy mất cwd (getcwd), shard sau exit 127, gate báo REJECT oan. Luật: trong lúc gate còn sống, scratch bị
# `git worktree lock` (lý do devkit-kept, pid của gate) nên `git worktree remove` không --force --force bị git từ chối;
# gate tự mở khoá khi dọn, nên không để lại .merge-scratch-* và không để lại khoá.
#   a. lệnh verify (đúng lệnh của phiên Grok, chạy từ main checkout) không gỡ được scratch: exit khác 0, thư mục còn;
#   b. lý do khoá đúng mẫu devkit-kept session=… pid=<pid gate> (worktree.py kept_lock đọc được; gc mở khoá khi pid đã chết);
#   c. gate vẫn tới lệnh verify thứ hai và exit 11 (verify đỏ cố ý);
#   d. sau gate: không còn .merge-scratch-* tạm nào, không còn đăng ký worktree của scratch.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mergegate-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/deploy-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
mkdir -p "$R/.claude/super-board/configs" && echo '{}' > "$R/.claude/super-board/configs/x.json"
echo a > "$R/a"
git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
echo b > "$WT/b"; git -C "$WT" add b; git -C "$WT" commit -qm card
git -C "$R" push -q origin issue-5-x
H=$(git -C "$R" rev-parse issue-5-x)
git -C "$R" diff origin/main issue-5-x > "$TMP/pr5.diff"
printf '{"files":[{"path":"b"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr5.meta"
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
  *" pr merge "*) echo "fake gh: must not merge on a red verify" >&2; exit 1 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" SBT_MAIN="$R" SBT_OUT="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
# lệnh 1: đúng lệnh phiên Grok đã chạy (git -C <main> worktree remove <scratch>, không --force), ghi exit, thư mục còn không, lý do khoá;
# lệnh 2: đánh dấu đã tới được rồi đỏ để gate dừng trước bước merge
cat > "$CFG" <<'JSON'
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[
 "S=$(pwd -P); echo \"$S\" > \"$SBT_OUT/scratch.path\"; git -C \"$SBT_MAIN\" worktree list --porcelain > \"$SBT_OUT/list.txt\"; git -C \"$SBT_MAIN\" worktree remove \"$S\" > \"$SBT_OUT/rm.out\" 2>&1; echo $? > \"$SBT_OUT/rm.rc\"; [ -f \"$S/a\" ] && echo yes > \"$SBT_OUT/still.txt\"; true",
 "echo second-verify-r\"\"an; false"]}
JSON
mkdir -p "$TMP/tt"
( cd "$WT" && TMPDIR="$TMP/tt" exec bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/gate.log" 2>&1 &
GPID=$!
wait "$GPID"; rc=$?

S=$(cat "$TMP/scratch.path" 2>/dev/null)
case "$S" in "$R/.claude/worktrees/.merge-scratch-"*) ok "verify ran in a .merge-scratch-* tree ($S)" ;; *) fail "verify cwd not a merge scratch: '${S}'" ;; esac
rmrc=$(cat "$TMP/rm.rc" 2>/dev/null)
[ -n "$rmrc" ] && [ "$rmrc" != 0 ] && [ "$(cat "$TMP/still.txt" 2>/dev/null)" = yes ] \
  && ok "a. bare 'git worktree remove <scratch>' while the gate lives: refused (exit $rmrc), tree kept" \
  || fail "a. bare remove of the live scratch: exit '${rmrc}', tree kept='$(cat "$TMP/still.txt" 2>/dev/null)' ($(head -c 200 "$TMP/rm.out" 2>/dev/null))"
reason=$(awk -v w="worktree $S" '$0==w{f=1; next} /^worktree /{f=0} f && /^locked/{sub(/^locked ?/,""); print; exit}' "$TMP/list.txt" 2>/dev/null)
[[ "$reason" =~ ^devkit-kept\ session=merge-gate-pr5\ pid=${GPID}$ ]] \
  && ok "b. lock reason names the gate: $reason" || fail "b. lock reason '${reason}' (want devkit-kept session=merge-gate-pr5 pid=${GPID})"
grep -q "second-verify-ran" "$TMP/gate.log" && [ "$rc" -eq 11 ] \
  && ok "c. the gate went on to verify command 2 and exited 11" || fail "c. gate exit $rc (want 11), second verify ran: $(grep -c second-verify-ran "$TMP/gate.log"): $(tail -5 "$TMP/gate.log")"
left=$(find "$R/.claude/worktrees" -mindepth 1 -maxdepth 1 -name '.merge-scratch-*' 2>/dev/null | grep -c . || true)
reg=$(git -C "$R" worktree list --porcelain | grep -c '^worktree .*/\.merge-scratch-' || true)
[ "$left" -eq 0 ] && [ "$reg" -eq 0 ] && ok "d. gate cleanup removed its own (locked) scratch: no folder, no registration" \
  || fail "d. left behind: $left folder(s), $reg registration(s): $(git -C "$R" worktree list)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_scratch_live_lock: PASS"; exit 0; } || { echo "test_merge_gate_scratch_live_lock: FAIL ($FAILS)"; exit 1; }
