#!/usr/bin/env bash
# Hồi quy cho --sweep của .claude/bin/super-board-post-merge-clean.sh với thẻ BỊ BỎ (issue CLOSED as not planned), chạy offline với `gh` giả.
# 24/10: repo agent-workbench có 20 worktree và 31 nhánh chưa merge khi chỉ còn 4 thẻ chạy. 14 nhánh là của thẻ đã bị gộp vào thẻ khác
# ("[orchestrator] Gộp vào #316…", issue đóng NOT_PLANNED ngày 23/10) — PR của chúng vẫn MỞ, nhánh và worktree còn nguyên. Sweep chỉ
# dọn thẻ có PR MERGED ("kept card N: no merged PR of it"), nên thẻ bị bỏ không bao giờ được dọn.
#   - thẻ CLOSED + NOT_PLANNED đã quá SB_SWEEP_GRACE_S, không lane sống: đóng PR còn mở (kèm lời nhắn), gỡ worktree sạch bằng kit,
#     xoá nhánh local không worktree nào giữ bằng `agent-kit worktree prune-branch --dropped`, chỉ khi tip đã push lên origin và không còn
#     PR mở (commit chưa push: giữ, luật dự án bắt hỏi trước)
#   - thẻ còn OPEN, đóng kiểu COMPLETED, mới đóng (chưa tới hạn), lane còn sống: không đụng gì
#   - worktree còn sửa thật: giữ (và nhánh nó checkout giữ theo)
# Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C DEVKIT_LANG=en
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEAN="$ROOT/.claude/bin/super-board-post-merge-clean.sh"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-dropped-cards.XXXXXX")"
SL=""
trap '[ -n "$SL" ] && kill "$SL" 2>/dev/null; rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
mkdir -p "$R/src"; echo code > "$R/src/x.c"
git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q -u origin main; git -C "$R" remote set-head origin main
mkdir -p "$W" "$R/.claude/super-board/inflight"

# card <N> <branch> [commits]: nhánh với <commits> (mặc định 1) commit riêng, đã push; worktree <N> tạo riêng bởi từng ca
card() {
  local i=0
  git -C "$R" branch "$2" main
  git -C "$R" worktree add -q "$TMP/edit" "$2"
  while [ "$i" -lt "${3:-1}" ]; do i=$((i + 1)); echo "c$1-$i" > "$TMP/edit/f$1-$i"; git -C "$TMP/edit" add -A; git -C "$TMP/edit" commit -qm "card $1 #$i"; done
  git -C "$R" worktree remove "$TMP/edit"
  git -C "$R" push -q origin "$2"
}
issue() {  # issue <N> <STATE> <reason|-> <closedAt>
  printf '{"state":"%s","stateReason":"%s","closedAt":"%s"}\n' "$2" "$([ "$3" = - ] && echo "" || echo "$3")" "$4" > "$TMP/issue$1.json"
}
pr_open() {  # pr_open <PR> <branch>
  printf '{"number":%s,"headRefName":"%s","headRefOid":"%s","baseRefName":"main","isCrossRepository":false}\n' \
    "$1" "$2" "$(git -C "$R" rev-parse "$2")" >> "$TMP/open.jsonl"
}

# gh giả. Ghi mọi lệnh; `pr close` gỡ PR khỏi danh sách mở.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/gh.calls"
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
case " $* " in
  *" pr list "*"--state merged"*) echo '[]' ;;
  *" pr list "*"--state open"*)
    head=""; search=""; prev=""
    for a in "$@"; do case "$prev" in --head) head="$a" ;; --search) search="$a" ;; esac; prev="$a"; done
    python3 -c 'import json,os,sys
p, head, search = sys.argv[1], sys.argv[2], sys.argv[3]
rows = [json.loads(l) for l in open(p) if l.strip()] if os.path.exists(p) else []
pre = search[5:].rstrip("-") if search.startswith("head:") else ""
print(json.dumps([r for r in rows if (not head or r["headRefName"] == head) and (not pre or r["headRefName"].startswith(pre))]))' \
      "$FAKE_DIR/open.jsonl" "$head" "$search" ;;
  *" pr close "*)
    python3 -c 'import json,sys
p, n = sys.argv[1], int(sys.argv[2])
rows = [l for l in open(p) if l.strip() and json.loads(l)["number"] != n]
open(p, "w").write("".join(rows))' "$FAKE_DIR/open.jsonl" "$n"
    echo "closed #$n" ;;
  *" issue view "*)
    f="$FAKE_DIR/issue$n.json"; [ -f "$f" ] || { echo '{"state":"OPEN","stateReason":"","closedAt":""}' > "$f"; }
    case " $* " in
      *" -q .state "*) python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$f" ;;
      *) cat "$f" ;;
    esac ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"
unset SB_SWEEP_GRACE_S   # card 9 ("young") relies on the 900 s default
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0
OLD="2020-01-01T00:00:00Z"; NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
has_branch() { git -C "$R" show-ref --verify --quiet "refs/heads/$1"; }
open_prs() { python3 -c 'import json,sys; print(" ".join(sorted(str(json.loads(l)["number"]) for l in open(sys.argv[1]) if l.strip())))' "$TMP/open.jsonl"; }

# 5: bị bỏ, worktree sạch + nhánh một commit riêng (đã push) + PR 50 mở  → PR đóng, worktree gỡ, nhánh xoá
card 5 issue-5-gom; git -C "$R" worktree add -q "$W/issue-5-build" issue-5-gom; pr_open 50 issue-5-gom; issue 5 CLOSED NOT_PLANNED "$OLD"
# 6: còn OPEN → không đụng
card 6 issue-6-live; git -C "$R" worktree add -q "$W/issue-6-build" issue-6-live; pr_open 60 issue-6-live; issue 6 OPEN - ""
# 7: bị bỏ nhưng worktree còn sửa thật → PR đóng, worktree + nhánh giữ
card 7 issue-7-dirty; git -C "$R" worktree add -q "$W/issue-7-build" issue-7-dirty; pr_open 70 issue-7-dirty; issue 7 CLOSED NOT_PLANNED "$OLD"
echo "real fix" >> "$W/issue-7-build/src/x.c"
# 9: bị bỏ nhưng mới đóng (chưa tới hạn) → không đụng
card 9 issue-9-young; git -C "$R" worktree add -q "$W/issue-9-build" issue-9-young; pr_open 90 issue-9-young; issue 9 CLOSED NOT_PLANNED "$NOW"
# 10: bị bỏ nhưng lane còn sống giữ thẻ → không đụng
card 10 issue-10-lane; git -C "$R" worktree add -q "$W/issue-10-build" issue-10-lane; pr_open 100 issue-10-lane; issue 10 CLOSED NOT_PLANNED "$OLD"
sleep 300 & SL=$!; printf 'PID=%s\nLANE=build\n' "$SL" > "$R/.claude/super-board/inflight/10"
# 11: bị bỏ, chỉ có nhánh local 2 commit riêng KHÔNG push, không worktree, không PR → nhánh GIỮ (commit chưa push: luật dự án bắt hỏi trước)
git -C "$R" branch issue-11-solo main; git -C "$R" worktree add -q "$TMP/edit" issue-11-solo
echo s1 > "$TMP/edit/s1"; git -C "$TMP/edit" add -A; git -C "$TMP/edit" commit -qm s1
echo s2 > "$TMP/edit/s2"; git -C "$TMP/edit" add -A; git -C "$TMP/edit" commit -qm s2
git -C "$R" worktree remove "$TMP/edit"; TIP11=$(git -C "$R" rev-parse issue-11-solo); issue 11 CLOSED NOT_PLANNED "$OLD"
# 13: bị bỏ, nhưng dòng PR thiếu trường isCrossRepository (gh đổi API): không rõ có phải PR fork → không đóng
card 13 issue-13-nofield; issue 13 CLOSED NOT_PLANNED "$OLD"
printf '{"number":130,"headRefName":"issue-13-nofield","headRefOid":"x","baseRefName":"main"}\n' >> "$TMP/open.jsonl"
# 14: bị bỏ, PR từ FORK tên issue-14-… (của người ngoài) → không bao giờ đóng
card 14 issue-14-fork; issue 14 CLOSED NOT_PLANNED "$OLD"
printf '{"number":140,"headRefName":"issue-14-fork","headRefOid":"x","baseRefName":"main","isCrossRepository":true}\n' >> "$TMP/open.jsonl"
# 12: đóng kiểu COMPLETED mà PR vẫn mở (không phải thẻ bị bỏ) → không đụng
card 12 issue-12-done; pr_open 120 issue-12-done; issue 12 CLOSED COMPLETED "$OLD"

bash "$CLEAN" --sweep "$R" --dry-run --min-interval 0 >"$TMP/dry.log" 2>&1
[ -d "$W/issue-5-build" ] && has_branch issue-5-gom && [ "$(open_prs)" = "100 120 130 140 50 60 70 90" ] \
  && ok "d0 --dry-run changes nothing" || { fail "d0 --dry-run changed something"; cat "$TMP/dry.log"; }
grep -q "would close PR #50" "$TMP/dry.log" && ok "d0b --dry-run names the PR it would close" || { fail "d0b dry-run does not name PR #50"; cat "$TMP/dry.log"; }

bash "$CLEAN" --sweep "$R" --min-interval 0 >"$TMP/sweep.log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "d1 sweep exit 0" || fail "d1 sweep exit $rc"
case " $(open_prs) " in *" 50 "*) fail "d2 PR #50 of a dropped card is still open" ;; *) ok "d2 the open PR of a dropped card is closed" ;; esac
grep -q "pr close 50 .*--comment" "$TMP/gh.calls" && ok "d2b the PR is closed with a comment saying why" || fail "d2b no comment on the closed PR"
[ ! -d "$W/issue-5-build" ] && ok "d3 the clean worktree of a dropped card is removed" || { fail "d3 worktree of dropped card #5 kept"; grep -a "issue-5" "$TMP/sweep.log"; }
! has_branch issue-5-gom && ok "d4 its local branch is deleted" || { fail "d4 branch issue-5-gom kept"; grep -a "issue-5" "$TMP/sweep.log"; }
has_branch issue-11-solo && [ "$(git -C "$R" rev-parse issue-11-solo)" = "$TIP11" ] && grep -Eq "issue-11-solo.*(never pushed|chưa push)" "$TMP/sweep.log" \
  && ok "d5 a branch with commits never pushed is KEPT (asking first is the project rule), with the reason" \
  || { fail "d5 branch issue-11-solo with unpushed commits was deleted or no reason logged"; grep -a "issue-11" "$TMP/sweep.log"; }
case " $(open_prs) " in *" 130 "*) case " $(open_prs) " in *" 140 "*) ok "d5b a PR row without isCrossRepository, and a fork PR, are not closed (fail-closed)" ;; *) fail "d5b fork PR #140 was closed" ;; esac ;; *) fail "d5b PR #130 (no isCrossRepository) was closed" ;; esac
case " $(open_prs) " in *" 70 "*) fail "d6 PR #70 still open" ;; *) ok "d6 a dropped card with a dirty worktree still gets its PR closed" ;; esac
[ -d "$W/issue-7-build" ] && has_branch issue-7-dirty && [ "$(tail -1 "$W/issue-7-build/src/x.c")" = "real fix" ] \
  && ok "d7 real edits keep the worktree and its branch" || fail "d7 dirty worktree or its branch lost"
for b in issue-6-live issue-9-young issue-10-lane issue-12-done; do
  has_branch "$b" || fail "d8 branch $b deleted"
done
for k in 6 9 10; do [ -d "$W/issue-$k-build" ] || fail "d8 worktree of card $k removed"; done
for p in 60 90 100 120; do case " $(open_prs) " in *" $p "*) ;; *) fail "d8 PR #$p closed but its card is not a dropped one" ;; esac; done
( cd "$R" && python3 "$ROOT/universal-agent-devkit/scripts/git/worktree.py" prune-branch --dropped issue-12-done ) >"$TMP/k1.log" 2>&1; rc=$?
[ "$rc" -ne 0 ] && has_branch issue-12-done && grep -Eq "not a dropped card|không phải nhánh của thẻ bị bỏ" "$TMP/k1.log" && ok "d9 kit prune-branch --dropped refuses a card closed as COMPLETED (rc=$rc)" \
  || { fail "d9 kit deleted the branch of a card that was not dropped (rc=$rc)"; cat "$TMP/k1.log"; }
[ "$FAILS" -eq 0 ] && ok "d8 OPEN / COMPLETED / young / live-lane cards are untouched"

[ "$FAILS" -eq 0 ] && echo "✅ test_post_merge_dropped_cards: all passed" || { echo "❌ test_post_merge_dropped_cards: $FAILS failed"; exit 1; }
