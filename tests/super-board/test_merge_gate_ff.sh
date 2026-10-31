#!/usr/bin/env bash
# Test hồi quy cho bước sau merge của .claude/bin/super-board-merge-gate.sh, chạy offline với `gh` giả và origin bare.
# Reviewer chạy merge gate từ worktree issue-<N>-review của nó, với repo.path "." (config của mọi board). Bước
# fetch + `merge --ff-only` sau merge dùng thẳng "." nên nhắm vào worktree review (HEAD detached): nhánh base của
# main checkout không bao giờ được fast-forward, lần merge kế tiếp và mọi worktree mới đều dựng trên base cũ.
# Phải quy "." về main checkout (dòng đầu `git worktree list --porcelain`) như super-board-post-merge-clean.sh, và
# vẫn chỉ ff khi main checkout đang ở nhánh base.
# Tương thích bash 3.2.
set -u
# Test grep thông báo tiếng Anh của git: ghim locale C để git có bản dịch không làm đỏ oan.
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/.claude/bin/super-board-merge-gate.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mergegate-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main

# card_branch <N> <file>: nhánh issue-<N>-x thêm đúng một dòng vào <file>, đã push; ghi diff + metadata cho gh giả.
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
# gh giả: đọc trạng thái PR từ $FAKE_DIR/pr<N>.*; `pr merge` mô phỏng GitHub đưa head lên main của origin.
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $head" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  # FAKE_BREAK_ORIGIN: merge xong thì trỏ origin vào đường dẫn không tồn tại, để fetch sau merge hỏng.
  *" pr merge "*) git -C "$FAKE_REPO" push -q origin "$head:refs/heads/main" \
                    && { [ -z "${FAKE_BREAK_ORIGIN:-}" ] || git -C "$FAKE_REPO" remote set-url origin "$FAKE_BREAK_ORIGIN"; } \
                    && echo "merged #$n" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_review_fanout.sh"; sb_review_fixture "$TMP/bin"   # signed review PASS + CI checks (new gate preconditions)
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_REPO="$R"
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["true"]}' > "$CFG"

# ── 1. Reviewer của thẻ #7 chạy gate từ worktree của nó; main checkout đang ở main.
card_branch 7 b
H7=$(cat "$TMP/pr7.head")
git -C "$R" worktree add -q --detach "$W/issue-7-review" "$H7"
( cd "$W/issue-7-review" && bash "$GATE" --config "$CFG" --pr 7 --expect-head "$H7" ) >"$TMP/gate7.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "gate run from the review worktree: merged (exit 0)" || fail "gate exit $rc: $(tail -5 "$TMP/gate7.log")"
[ "$(git -C "$O" rev-parse main)" = "$H7" ] || fail "fixture: fake merge did not reach origin/main"
[ "$(git -C "$R" rev-parse main)" = "$H7" ] && ok "main checkout's base branch fast-forwarded to the merge (repo.path '.')" \
  || fail "main checkout's main still at $(git -C "$R" rev-parse --short main), origin/main is ${H7:0:7}: ff-only ran on the review worktree"
[ -z "$(git -C "$R" status --porcelain --untracked-files=no)" ] && ok "main checkout's tree matches the fast-forwarded main" \
  || fail "main checkout dirty after ff: $(git -C "$R" status --porcelain --untracked-files=no | head -3)"
[ -d "$W/issue-7-review" ] && ok "calling Reviewer's worktree kept" || fail "calling Reviewer's worktree removed"
! grep -q "not fast-forwarded" "$TMP/gate7.log" && ok "successful fast-forward prints no stale-base warning" \
  || fail "false stale-base message after a successful fast-forward: $(grep 'not fast-forwarded' "$TMP/gate7.log")"

# ── 2. Đối chứng: main checkout đang ở nhánh khác thì không fast-forward gì (ff-only đẩy nhánh đang checkout).
git -C "$R" checkout -q -b local-work
card_branch 8 c
H8=$(cat "$TMP/pr8.head")
before_main=$(git -C "$R" rev-parse main); before_work=$(git -C "$R" rev-parse local-work)
git -C "$R" worktree add -q --detach "$W/issue-8-review" "$H8"
( cd "$W/issue-8-review" && bash "$GATE" --config "$CFG" --pr 8 --expect-head "$H8" ) >"$TMP/gate8.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] || fail "gate exit $rc (control): $(tail -5 "$TMP/gate8.log")"
[ "$(git -C "$O" rev-parse main)" = "$H8" ] || fail "fixture: fake merge #8 did not reach origin/main (control proves nothing)"
[ "$(git -C "$R" rev-parse local-work)" = "$before_work" ] && [ "$(git -C "$R" rev-parse main)" = "$before_main" ] \
  && ok "main checkout on another branch: nothing fast-forwarded" \
  || fail "main checkout on another branch: local-work or main moved"
grep -q "note: main in .* not fast-forwarded (main checkout is not on main)" "$TMP/gate8.log" && ok "skipped fast-forward is reported (local base visibly stale)" \
  || fail "skipped fast-forward left no trace in the gate output"

# ── 3. main checkout ở main nhưng ff bị git từ chối (file chưa track chắn đường): không im lặng, base cũ phải lộ ra.
git -C "$R" checkout -q main
card_branch 9 d
H9=$(cat "$TMP/pr9.head")
echo local > "$R/d"                                   # file chưa track mà merge sẽ ghi đè: ff-only từ chối
before_main=$(git -C "$R" rev-parse main)
git -C "$R" worktree add -q --detach "$W/issue-9-review" "$H9"
( cd "$W/issue-9-review" && bash "$GATE" --config "$CFG" --pr 9 --expect-head "$H9" ) >"$TMP/gate9.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] || fail "gate exit $rc (ff refused): $(tail -5 "$TMP/gate9.log")"
[ "$(git -C "$R" rev-parse main)" = "$before_main" ] && [ "$(cat "$R/d")" = local ] || fail "fixture: ff was expected to be refused"
grep -q "warning: main in .* not fast-forwarded.*untracked working tree files would be overwritten" "$TMP/gate9.log" && ok "refused fast-forward reported with git's own reason, merge still exits 0" \
  || fail "refused fast-forward left no trace (stale base, same symptom as before)"

# ── 4. fetch sau merge hỏng (origin mất ngay sau khi GitHub merge): cảnh báo phải kèm lý do thật của git.
rm -f "$R/d"
card_branch 10 e
H10=$(cat "$TMP/pr10.head")
git -C "$R" worktree add -q --detach "$W/issue-10-review" "$H10"
( cd "$W/issue-10-review" && FAKE_BREAK_ORIGIN="$TMP/gone.git" bash "$GATE" --config "$CFG" --pr 10 --expect-head "$H10" ) >"$TMP/gate10.log" 2>&1; rc=$?
git -C "$R" remote set-url origin "$O"
[ "$rc" -eq 0 ] || fail "gate exit $rc (fetch failed): $(tail -5 "$TMP/gate10.log")"
[ "$(git -C "$O" rev-parse main)" = "$H10" ] || fail "fixture: fake merge #10 did not reach origin/main"
grep -q "warning: fetch origin main failed in .*local base may be stale: .*does not appear to be a git repository" "$TMP/gate10.log" \
  && ok "failed post-merge fetch reported with git's own reason, merge still exits 0" \
  || fail "failed post-merge fetch warning lacks git's reason: $(grep 'fetch origin' "$TMP/gate10.log")"

[ ! -e "$TMP/halt.json" ] && ok "no GitHub halt recorded" || fail "halt recorded: $(cat "$TMP/halt.json")"
[ "$FAILS" -eq 0 ] && echo "✅ test_merge_gate_ff: all passed" || { echo "❌ test_merge_gate_ff: $FAILS failed"; exit 1; }
