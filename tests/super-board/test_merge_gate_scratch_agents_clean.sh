#!/usr/bin/env bash
# #234 (#323): bước cài DevKit của merge gate (install.sh -t <scratch>) viết lại khối devkit-essentials của AGENTS.md đã TRACK; cây scratch
# bẩn đó làm worktree remove/discard từ chối gỡ (.merge-scratch 21/10) và đổi dấu vân tay cây. Luật: khi lệnh verify chạy, `git status` của
# scratch sạch, kể cả khi install.sh sửa AGENTS.md. install.sh giả ở đây chỉ làm đúng việc đó (sửa file đã track).
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-scratchagents-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/deploy-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
mkdir -p "$R/.claude/super-board/configs" && echo '{}' > "$R/.claude/super-board/configs/x.json"
echo a > "$R/a"
printf 'intro\n<!-- devkit-essentials:start v1 -->\nban kit cu\n<!-- devkit-essentials:end -->\n' > "$R/AGENTS.md"
mkdir -p "$R/universal-agent-devkit/bin"
printf '#!/usr/bin/env bash\nprintf "ban kit main\\n" > "$2/AGENTS.md"\n' > "$R/universal-agent-devkit/bin/install.sh"
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
. "$ROOT/tests/super-board/lib/fake_review_fanout.sh"; sb_review_fixture "$TMP/bin"   # signed review PASS + CI checks (new gate preconditions)
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
# lệnh 1: scratch (sau khi install.sh giả sửa AGENTS.md) phải sạch; lệnh 2 đánh dấu đã tới được, rồi đỏ để gate dừng trước bước merge
cat > "$CFG" <<'JSON'
{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":[
 "s=$(git status --porcelain --untracked-files=all); [ -z \"$s\" ] || { echo SCRATCH-DIR\"\"TY $s; exit 1; }",
 "echo second-verify-r\"\"an; false"]}
JSON
mkdir -p "$TMP/tt"
( cd "$WT" && TMPDIR="$TMP/tt" bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" ) >"$TMP/gate.log" 2>&1; rc=$?
! grep -q "SCRATCH-DIRTY" "$TMP/gate.log" && grep -q "second-verify-ran" "$TMP/gate.log" \
  && ok "AGENTS.md đã track không bẩn trong scratch sau khi cài DevKit" || fail "scratch bẩn khi verify chạy: $(grep -m1 SCRATCH-DIRTY "$TMP/gate.log")"
[ "$rc" -eq 11 ] && ok "verify đỏ ở lệnh 2: exit 11" || fail "gate exit $rc (want 11): $(tail -5 "$TMP/gate.log")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_gate_scratch_agents_clean: PASS"; exit 0; } || { echo "test_merge_gate_scratch_agents_clean: FAIL ($FAILS)"; exit 1; }
