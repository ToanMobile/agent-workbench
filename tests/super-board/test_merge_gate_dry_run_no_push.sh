#!/usr/bin/env bash
# Merge train chạy gate --dry-run từng PR để kiểm policy/approval trước khi dựng chuỗi. Khi nhánh PR đang sau base, đường
# "cập nhật nhánh tại chỗ" của gate đẩy commit gộp lên nhánh PR kể cả ở chế độ dry-run: đầu PR đổi, và lần gọi gate thật sau đó
# mang --expect-head của đầu cũ nên thoát exit 6 (head moved), PR không bao giờ merge (OCR 22/10, thẻ #287).
# Luật: --dry-run không ghi gì lên remote; nhánh PR giữ nguyên SHA.
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
export SB_NOTIFY_SKIP=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-dryrun-nopush.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"

O="$TMP/origin.git"; R="$TMP/repo"; WT="$R/.claude/worktrees/deploy-x"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '/.claude/worktrees/\n' > "$R/.gitignore"
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

# main tiến thêm một commit không xung đột: nhánh PR chậm hơn base, merge scratch sạch.
git -C "$R" checkout -q main; echo c > "$R/c"; git -C "$R" add c; git -C "$R" commit -qm main-moves; git -C "$R" push -q origin main

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
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["echo ran; exit 0"]}' > "$CFG"

BEHIND=$(git -C "$R" rev-list --count "${H}..origin/main")
[ "$BEHIND" -gt 0 ] && ok "setup: PR branch is $BEHIND commit(s) behind main" || fail "setup: branch not behind main"

( cd "$WT" && bash "$GATE" --config "$CFG" --pr 5 --expect-head "$H" --dry-run ) >"$TMP/dry.log" 2>&1; rc=$?
git -C "$R" fetch -q origin
AFTER=$(git -C "$R" rev-parse origin/issue-5-x)
[ "$AFTER" = "$H" ] && ok "dry run leaves the PR branch at the reviewed head" \
  || fail "dry run moved the PR branch ($H -> $AFTER, gate rc $rc): $(grep -i 'in place' "$TMP/dry.log")"
grep -q "updated .* in place" "$TMP/dry.log" && fail "dry run log claims the branch was updated in place" || ok "dry run does not log an in-place update"
# Chứng minh gate thật sự đi qua nhánh dry-run mới (thoát sớm vì lý do khác cũng giữ nguyên nhánh nên chưa đủ).
[ "$rc" -eq 0 ] && ok "dry run exits 0" || fail "dry run exit $rc: $(tail -3 "$TMP/dry.log")"
grep -q "dry run: .* (nothing pushed)" "$TMP/dry.log" && ok "dry run says it would update the branch and pushed nothing" \
  || fail "no 'nothing pushed' line: $(grep 'merge-gate' "$TMP/dry.log" | tail -3)"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
