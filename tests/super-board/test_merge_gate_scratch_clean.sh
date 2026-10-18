#!/usr/bin/env bash
# 18/10 (GeelyEx2): merge gate chuyển output của lệnh verify vào "$SCRATCH/.verify.log", tức là TRONG cây scratch. Ở repo không ignore
# *.log (GeelyEx2), file chưa track đó vào dấu vân tay cây (bin/tree_fp.py: git add -A). Cây scratch vì vậy khác cây của worktree đã PASS,
# và post-fix-gate không mượn được biên nhận --full của worktree anh em (PR #55): mọi suite chạy lại (REG-CAR-01 mất 125-250 s).
# Luật: khi lệnh verify chạy, cây scratch chỉ chứa nội dung PR; log nằm ngoài cây và được dọn khi xong. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-scratchclean-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/deploy-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"   # như GeelyEx2: KHÔNG ignore *.log
mkdir -p "$R/.claude/super-board/configs" && echo '{}' > "$R/.claude/super-board/configs/x.json"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
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
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
# lệnh 1: cây scratch phải sạch (không file chưa track); lệnh 2 đánh dấu đã tới được, rồi đỏ để gate dừng trước bước merge
cat > "$CFG" <<'JSON'
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[
 "s=$(git status --porcelain --untracked-files=all); [ -z \"$s\" ] || { echo SCRATCH-DIR\"\"TY $s; exit 1; }",
 "echo second-verify-r\"\"an; false"]}
JSON
mkdir -p "$TMP/tt"
( cd "$WT" && TMPDIR="$TMP/tt" bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/gate.log" 2>&1; rc=$?
! grep -q "SCRATCH-DIRTY" "$TMP/gate.log" && grep -q "second-verify-ran" "$TMP/gate.log" \
  && ok "lệnh verify thấy cây scratch sạch (log không nằm trong cây)" || fail "cây scratch bẩn khi verify chạy: $(grep -m1 SCRATCH-DIRTY "$TMP/gate.log")"
[ "$rc" -eq 11 ] && ok "verify đỏ ở lệnh 2 (nhánh không chậm hơn base): exit 11" || fail "gate exit $rc (want 11): $(tail -5 "$TMP/gate.log")"
left=$(ls -A "$TMP/tt")
[ -z "$left" ] && ok "không để lại file tạm nào (scratch, meta, diff, log)" || fail "còn file tạm: $left"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_scratch_clean: PASS"; exit 0; } || { echo "test_merge_gate_scratch_clean: FAIL ($FAILS)"; exit 1; }
