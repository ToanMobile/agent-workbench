#!/usr/bin/env bash
# #262 (R1/R2): duyệt của người gắn với head X; gate tự đẩy merge commit Y rồi thoát (verify đỏ). Lượt gate thứ hai thấy head=Y, không đẩy
# nữa: nó vẫn phải truyền --approved-head X cho approval. Biên nhận do gate ghi theo Y; xoá dòng ghi/đọc nó thì lượt hai đòi duyệt lại (exit 7).
# Approval giả: duyệt khi head == X hoặc --approved-head == X. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-approved-head-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
# Gate chạy từ bản sao thư mục bin để thay super-board-approval.py bằng bản giả mà không đụng bản thật.
cp -R "$ROOT/.claude/bin" "$TMP/gatebin"
GATE="$TMP/gatebin/super-board-merge-gate.sh"
cat > "$TMP/gatebin/super-board-approval.py" <<PY
#!/usr/bin/env python3
import json, sys
a = sys.argv[1:]
def opt(k):
    return a[a.index(k) + 1] if k in a else ""
open("$TMP/approval-calls", "a").write(" ".join(a) + "\n")
x = open("$TMP/x.head").read().strip()
print(json.dumps({"approved": opt("--head") == x or opt("--approved-head") == x}))
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
# main đi tiếp sau khi PR mở: nhánh PR chậm hơn base, gate tự đẩy merge commit Y.
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
  *" pr merge "*) echo "merged #61" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
mkdir -p "$TMP/g"
cat > "$TMP/g/post-fix-gate.py" <<PY
import sys
sys.exit(int(open("$TMP/verify-rc").read()))
PY
python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":"https://github.com/o/r"},"project":{"owner":"o","number":1},"merge_policy":{"default":"human"},"verify_commands":[sys.argv[1]]}))' "python3 $TMP/g/post-fix-gate.py" > "$TMP/cfg.json"
gate() { ( cd "$WT" && bash "$GATE" --config "$TMP/cfg.json" --pr 61 --expect-head "$(cat "$TMP/pr61.head")" ) >"$TMP/gate.log" 2>&1; GATE_RC=$?; }

echo 1 > "$TMP/verify-rc"; gate
Y=$(git -C "$R" rev-parse origin/issue-61-x)
[ "$Y" != "$X" ] && [ "$GATE_RC" -eq 11 ] && ok "run 1: approved head X, gate pushed merge commit Y, verify red (exit 11)" \
  || fail "run 1 (rc=$GATE_RC Y=$Y X=$X, want 11 and Y!=X): $(tail -4 "$TMP/gate.log")"

echo "$Y" > "$TMP/pr61.head"; echo 0 > "$TMP/verify-rc"; gate
[ "$GATE_RC" -eq 0 ] && grep -q -- "--approved-head $X" "$TMP/approval-calls" \
  && ok "run 2 on head Y: approval still covers Y through the recorded X, no new 'done' needed" \
  || fail "run 2 (rc=$GATE_RC, want 0 with --approved-head $X): $(tail -4 "$TMP/gate.log")"

# Commit người đẩy thêm sau merge commit của gate: không có biên nhận cho head đó, duyệt lapse (exit 7).
git -C "$WT" fetch -q origin issue-61-x; git -C "$WT" switch -q -C issue-61-x "$Y"
echo extra > "$WT/extra"; git -C "$WT" add extra; git -C "$WT" commit -qm human-push
git -C "$WT" push -q origin issue-61-x; Z=$(git -C "$WT" rev-parse HEAD)
echo "$Z" > "$TMP/pr61.head"; git -C "$R" diff "$Y" "$Z" > "$TMP/pr61.diff"; gate
[ "$GATE_RC" -eq 7 ] && ok "run 3: a commit pushed after the gate's merge has no receipt, approval lapses (exit 7)" \
  || fail "run 3 (rc=$GATE_RC, want 7): $(tail -4 "$TMP/gate.log")"

[ "$FAILS" -eq 0 ] && { echo "OK: all checks passed"; exit 0; } || { echo "FAILED: $FAILS check(s)"; exit 1; }
