#!/usr/bin/env bash
# Merge train: vòng solve đầu bị cắt giờ (verify exit 124 hai lần) khi GOOD đã có PR; sau đó preflight dry-run loại một PR bị
# policy chặn và ghi đè CANDS bằng NEWGOOD. Các PR chưa được chứng minh (còn nằm trong CANDS nhưng chưa vào GOOD/RED/CONFLICT)
# mất khỏi báo cáo: không có dòng `train-result: <N> timeout`, không trả exit 12, caller tưởng chúng không tồn tại (OCR 22/10, thẻ #287).
# Luật: mọi PR được truyền vào đều có đúng một kết cục trong output của train.
# Chạy offline với `gh` giả và origin bare, dựng như test_merge_train.sh. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TRAIN="$ROOT/.claude/bin/super-board-merge-train.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-train-unproven.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main

card_branch() {
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$1-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$1-build" "issue-$1-x"
  echo "$1" > "$W/issue-$1-build/$2"
  git -C "$W/issue-$1-build" add "$2"; git -C "$W/issue-$1-build" commit -qm "card $1"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  git -C "$R" diff "origin/main" "issue-$1-x" > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"%s"}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$2" > "$TMP/pr$1.meta"
}

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
  *" pr merge "*)
    git -C "$FAKE_REPO" fetch -q origin main "issue-$n-x"
    tree=$(git -C "$FAKE_REPO" merge-tree --write-tree origin/main "$head") || exit 1
    c=$(git -C "$FAKE_REPO" commit-tree "$tree" -p origin/main -m "squash #$n")
    git -C "$FAKE_REPO" push -q origin "$c:refs/heads/main" && echo "$n" >> "$FAKE_DIR/merged" && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_NOTIFY_SKIP=1

# #21 sạch, #22 mang nhãn money (gate dry-run trả exit 7), #23 và #24 sạch.
card_branch 21 f21; card_branch 22 f22; card_branch 23 f23; card_branch 24 f24
printf '{"files":[{"path":"f22"}],"labels":[{"name":"money"}],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr22.meta"
git -C "$R" worktree add -q --detach "$W/review" origin/main

# Verify theo bộ đếm: lần 1 đỏ (cả 4 PR), lần 2 xanh ([21,22]), lần 3 và 4 hết giờ ([21,22,23,24] hai lần), từ lần 5 xanh.
CFG="$TMP/cfg.json"
printf '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo x >> %s/verify.count; n=$(wc -l < %s/verify.count | tr -d \\" \\"); case $n in 1) exit 1;; 2) exit 0;; 3|4) exit 124;; *) exit 0;; esac"]}\n' "$TMP" "$TMP" > "$CFG"
rm -f "$TMP/verify.count" "$TMP/merged"
( cd "$W/review" && bash "$TRAIN" --config "$CFG" --prs 21,22,23,24 ) >"$TMP/t.log" 2>&1; rc=$?

for n in 21 22 23 24; do
  c=$(grep -c "^train-result: $n " "$TMP/t.log")
  [ "$c" -eq 1 ] && ok "#$n has exactly one train-result line" || fail "#$n has $c train-result lines: $(grep '^train-result' "$TMP/t.log" | tr '\n' '|')"
done
grep -q "train-result: 23 timeout" "$TMP/t.log" && grep -q "train-result: 24 timeout" "$TMP/t.log" \
  && ok "unproven #23 and #24 are reported as timeout" || fail "unproven PRs not reported as timeout: $(grep train "$TMP/t.log" | tr '\n' '|')"
[ "$rc" -eq 7 ] && ok "train exit 7: the policy block keeps precedence over the timeout" || fail "train exit $rc (want 7): $(tail -4 "$TMP/t.log")"
grep -q "train-result: 21 merged" "$TMP/t.log" && ok "#21 (proved green) still merges" || fail "#21 not merged: $(grep train "$TMP/t.log" | tr '\n' '|')"

[ "$FAILS" -eq 0 ] && echo "✅ test_merge_train_unproven_kept: all passed" || { echo "❌ test_merge_train_unproven_kept: $FAILS failed"; exit 1; }
