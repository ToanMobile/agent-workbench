#!/usr/bin/env bash
# #570: nhánh PR chậm hơn base, gate chạy xong thì head của PR trên origin phải GIỮ NGUYÊN (gate không tự ghi lên nhánh PR).
# Gate vẫn gộp base vào worktree scratch ở local và verify trên cây đã gộp; approved-head và --match-head-commit vẫn khớp head PR.
# Approval giả: duyệt khi --head == X. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-no-push-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
mkdir -p "$TMP/gk/.claude"; cp -R "$ROOT/.claude/bin" "$TMP/gk/.claude/bin"; ln -s "$ROOT/universal-agent-devkit" "$TMP/gk/universal-agent-devkit"   # DevKit beside the gate: review-fanout.sh
GATE="$TMP/gk/.claude/bin/super-board-merge-gate.sh"
cat > "$TMP/gk/.claude/bin/super-board-approval.py" <<PY
#!/usr/bin/env python3
import json, sys
a = sys.argv[1:]
def opt(k):
    return a[a.index(k) + 1] if k in a else ""
open("$TMP/approval-calls", "a").write(" ".join(a) + "\n")
print(json.dumps({"approved": opt("--head") == open("$TMP/x.head").read().strip()}))
PY
O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/review-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
mkdir -p "$R/.agents"; echo '[]' > "$R/.agents/regression_matrix.active.json"
echo a > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
git -C "$R" branch -q --no-track issue-5-x main
git -C "$R" worktree add -q "$WT" issue-5-x
git -C "$R" branch -q --no-track issue-61-x main
git -C "$WT" switch -q issue-61-x
echo 61 > "$WT/f61"; git -C "$WT" add f61; git -C "$WT" commit -qm card61
git -C "$R" push -q origin issue-61-x
X=$(git -C "$R" rev-parse issue-61-x); echo "$X" > "$TMP/x.head"; echo "$X" > "$TMP/pr61.head"
git -C "$R" diff "$X~1" "$X" > "$TMP/pr61.diff"
printf '{"files":[{"path":"f61"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr61.meta"
# main đi tiếp sau khi PR mở: nhánh PR chậm hơn base.
echo b > "$R/b"; git -C "$R" add b; git -C "$R" commit -qm main-moves; git -C "$R" push -q origin main

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
head=$(cat "$FAKE_DIR/pr61.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-61-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr61.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr61.diff" ;;
  *" pr merge "*) echo "$*" > "$FAKE_DIR/merge-args"; echo "merged #61" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_review_fanout.sh"; sb_review_fixture "$TMP/bin"   # signed review PASS + CI checks (new gate preconditions)
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
# Verify giả chạy trong scratch: ghi lại file nào có mặt (b của base, f61 của PR).
cat > "$TMP/verify.py" <<PY
import os
open("$TMP/verify-tree", "w").write(" ".join(sorted(f for f in ("a", "b", "f61") if os.path.exists(f))))
PY
python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"project":{"owner":"o","number":1},"merge_policy":{"default":"human"},"verify_commands":[sys.argv[1]]}))' "python3 $TMP/verify.py" > "$TMP/cfg.json"
( cd "$WT" && bash "$GATE" --config "$TMP/cfg.json" --pr 61 --expect-head "$X" ) >"$TMP/gate.log" 2>&1; RC=$?

[ "$(git -C "$O" rev-parse issue-61-x)" = "$X" ] && ok "PR head on origin unchanged after the gate" \
  || fail "PR head moved ${X:0:8} -> $(git -C "$O" rev-parse --short issue-61-x) (gate wrote to the PR branch)"
[ "$(cat "$TMP/verify-tree" 2>/dev/null)" = "a b f61" ] && ok "verify ran on the locally merged scratch tree (base + PR)" \
  || fail "verify tree was '$(cat "$TMP/verify-tree" 2>/dev/null)', want 'a b f61'"
[ "$RC" -eq 0 ] && ok "gate exits 0 (approved head still matches, no new approval)" \
  || fail "gate exit $RC, want 0: $(tail -4 "$TMP/gate.log")"
if [ -r "$TMP/approval-calls" ]; then
  ! grep -q -- "--approved-head" "$TMP/approval-calls" && grep -q -- "--head $X" "$TMP/approval-calls" \
    && ok "approval asked about the PR head X itself (no --approved-head indirection)" \
    || fail "approval calls: $(cat "$TMP/approval-calls")"
else fail "approval was never consulted"; fi
grep -q -- "--match-head-commit $X" "$TMP/merge-args" 2>/dev/null && ok "merge pinned to the unchanged head X (--match-head-commit)" \
  || fail "merge args: $(cat "$TMP/merge-args" 2>/dev/null)"

[ "$FAILS" -eq 0 ] && { echo "OK: all checks passed"; exit 0; } || { echo "FAILED: $FAILS check(s)"; exit 1; }
