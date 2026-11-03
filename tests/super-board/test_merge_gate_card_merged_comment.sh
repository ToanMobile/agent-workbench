#!/usr/bin/env bash
# P2 (optimizer đợt 2, 03/11): merge gate gọi trực tiếp (lane, phiên, drain_merge --standalone) tự comment "[reviewer] [report]
# ✅ merged" lên mọi thẻ PR đóng (closingIssuesReferences của GitHub). 130/177 thẻ WB vào Done từ 28/10 không có dòng merged nào
# (PR nhánh split/…, merge ngoài queue; WB#325, #392 trước queue).
# - M1: Closes #41, đủ AC → comment ✅ merged <sha squash> · PR #41 trên issue 41, sau lệnh merge.
# - M2: SB_MERGE_CALLER=queue → không comment (queue tự comment lúc route train-result).
# - M3: còn AC chưa tick → chỉ comment ac-open, không ✅ merged.
# - M4: PR tay không Closes thẻ (Refs) → không đụng issue.
# - M5: nhánh không mang số thẻ (split/…) đóng #45 → comment trên #45.
# - M6: lệnh merge lỗi (mất phản hồi) mà GitHub báo MERGED → vẫn comment, kèm sha squash GitHub báo.
# SB_GATE=<file> chạy bản cũ để thấy ĐỎ. Offline, bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${SB_GATE:-$ROOT/.claude/bin/super-board-merge-gate.sh}"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
GATE="${SB_GATE:-$ROOT/.claude/bin/super-board-merge-gate.sh}"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mergegate-merged.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main

# card <N> <pr body file> <issue body file> <issue labels json>: nhánh issue-<N>-x, metadata + issue cho gh giả.
card() {  # $5 (tuỳ chọn) = message commit
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$1-x" origin/main
  git -C "$R" worktree add -q "$W/issue-$1-build" "issue-$1-x"
  echo "$1" > "$W/issue-$1-build/f$1"
  git -C "$W/issue-$1-build" add "f$1"; git -C "$W/issue-$1-build" commit -qm "${5:-card $1}"
  git -C "$R" push -q origin "issue-$1-x"
  git -C "$R" rev-parse "issue-$1-x" > "$TMP/pr$1.head"
  git -C "$R" diff origin/main "issue-$1-x" > "$TMP/pr$1.diff"
  jq -n --rawfile b "$2" --arg p "f$1" '{files:[{path:$p}],labels:[],body:$b,additions:1,deletions:0,changedFiles:1}' > "$TMP/pr$1.meta"
  jq -n --rawfile b "$3" --argjson l "$4" --argjson n "$1" '{number:$n,title:"t",body:$b,labels:$l}' > "$TMP/issue$1.json"
  git -C "$R" worktree add -q --detach "$W/issue-$1-review" "$(cat "$TMP/pr$1.head")"
}

mkdir -p "$TMP/bin" "$TMP/cache"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
case " $* " in
  *" api graphql "*) echo '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"I"}}}}' ;;
  *" pr view "*"headRefName,headRefOid"*) echo "$(cat "$FAKE_DIR/pr$n.ref" 2>/dev/null || echo "issue-$n-x") $(cat "$FAKE_DIR/pr$n.head")" ;;
  *" pr view "*"closingIssuesReferences"*) cat "$FAKE_DIR/pr$n.closes" 2>/dev/null ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) if [ -e "$FAKE_DIR/pr$n.lost" ] && [ -e "$FAKE_DIR/pr$n.merged" ]; then
      printf '{"state":"MERGED","mergeCommit":{"oid":"6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b%s"},"headRefOid":"%s"}\n' "$n" "$(cat "$FAKE_DIR/pr$n.head")"
    else printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$(cat "$FAKE_DIR/pr$n.head")"; fi ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"--json mergeCommit "*) echo "5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5$n" ;;
  *" pr view "*"title"*) [ -e "$FAKE_DIR/pr$n.title.fail" ] && exit 1
    if [ -e "$FAKE_DIR/verified" ] && [ -e "$FAKE_DIR/pr$n.title2" ]; then cat "$FAKE_DIR/pr$n.title2"; else cat "$FAKE_DIR/pr$n.title" 2>/dev/null || echo "t"; fi ;;
  *" pr view "*"--json body"*) if [ -e "$FAKE_DIR/pr$n.body2" ]; then cat "$FAKE_DIR/pr$n.body2"; else jq -r '.body' "$FAKE_DIR/pr$n.meta"; fi ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr edit "*) f=$(printf '%s\n' "$@" | sed -n '/^--body-file$/{n;p;}'); cp "$f" "$FAKE_DIR/pr$n.edited" ;;
  *" pr merge "*) [ -e "$FAKE_DIR/pr$n.lost" ] && { : > "$FAKE_DIR/pr$n.merged"; echo "GraphQL: 502" >&2; exit 1; }
    f=$(printf '%s\n' "$@" | sed -n '/^--body-file$/{n;p;}'); [ -n "$f" ] && cp "$f" "$FAKE_DIR/merge$n.msg"; echo merged ;;
  *" issue view "*"-q .body"*) jq -r '.body' "$FAKE_DIR/issue$n.json" ;;
  *" issue view "*) cat "$FAKE_DIR/issue$n.json" ;;
  *" issue "*|*" label "*) : ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
. "$ROOT/tests/super-board/lib/fake_ci_checks.sh"; sb_ci_checks_fixture "$TMP/bin"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" SB_CARD_CACHE_DIR="$TMP/cache" SB_NOTIFY_SKIP=1
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_MERGE_RECHECK_DELAY_S=0 SB_MERGE_LOAD_MAX=100000
printf '{"projectId":"P","fieldId":"F","options":{"Ready":"o-r","Done":"o-d"},"items":{"41":"I41","42":"I42","43":"I43","44":"I44","45":"I45","46":"I46"}}' > "$TMP/cache/board-o-1.json"
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"project":{"owner":"o","number":1},"verify_commands":["touch '"$TMP"'/verified"]}' > "$CFG"
gate() {  # $1 = PR; stdout → gate$1.out, stderr → gate$1.err; echo rc
  rm -f "$TMP/calls" "$TMP/verified"
  ( cd "$W/issue-$1-review" && bash "$GATE" --config "$CFG" --pr "$1" --expect-head "$(cat "$TMP/pr$1.head")" ) \
    >"$TMP/gate$1.out" 2>"$TMP/gate$1.err"; echo $?
}


printf '## Acceptance Criteria\n- [ ] Test: lane gọi gate trực tiếp có comment merged\n' > "$TMP/issue1.md"
merged_comment() { grep -c "issue comment $1 .*\[reviewer\] \[report\] ✅ merged" "$TMP/calls"; }

# M1 — gọi trực tiếp, Closes #41, đủ AC.
printf 'Closes #41\n<!-- sb:ac -->\n- [x] Test: lane gọi gate trực tiếp có comment merged\n<!-- /sb:ac -->\n' > "$TMP/b41.md"
card 41 "$TMP/b41.md" "$TMP/issue1.md" '[]'
echo 41 > "$TMP/pr41.closes"
rc=$(gate 41)
[ "$rc" = 0 ] && [ "$(merged_comment 41)" = 1 ] && grep -q '✅ merged 5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a541 · PR #41' "$TMP/calls" \
  && ok "M1: gọi trực tiếp, đủ AC → một comment ✅ merged <sha squash> · PR #41 trên thẻ" \
  || fail "M1: rc=$rc calls=$(tr '\n' '|' < "$TMP/calls" | tail -c 600)"
awk '/pr merge 41/{m=NR} /issue comment 41/{c=NR} END{exit !(m && c && m < c)}' "$TMP/calls" \
  && ok "M1: comment sau lệnh merge" || fail "M1: order"

# M2 — queue/train gọi gate: queue tự comment khi route train-result, gate không comment trùng.
printf 'Closes #42\n<!-- sb:ac -->\n- [x] Test: lane gọi gate trực tiếp có comment merged\n<!-- /sb:ac -->\n' > "$TMP/b42.md"
card 42 "$TMP/b42.md" "$TMP/issue1.md" '[]'
echo 42 > "$TMP/pr42.closes"
rc=$(SB_MERGE_CALLER=queue gate 42)
[ "$rc" = 0 ] && grep -q 'pr merge 42' "$TMP/calls" && [ "$(merged_comment 42)" = 0 ] \
  && ok "M2: SB_MERGE_CALLER=queue → merge, không comment ✅ merged" || fail "M2: rc=$rc $(tr '\n' '|' < "$TMP/calls" | tail -c 400)"

# M3 — còn AC chưa tick: ac-open lo phần thẻ, không ✅ merged.
printf '> ⏳ Closes #43\n<!-- sb:ac -->\n- [ ] Test: lane gọi gate trực tiếp có comment merged\\\n  ↳ đo sau merge\n<!-- /sb:ac -->\n' > "$TMP/b43.md"
card 43 "$TMP/b43.md" "$TMP/issue1.md" '[]'
rc=$(gate 43)
[ "$rc" = 0 ] && grep -q '^ac-open: #43$' "$TMP/gate43.out" && [ "$(merged_comment 43)" = 0 ] \
  && ok "M3: AC chưa đủ → ac-open, không ✅ merged" || fail "M3: rc=$rc $(tr '\n' '|' < "$TMP/calls" | tail -c 400)"

# M4 — PR tay không đóng thẻ: như cũ, không đụng issue.
printf 'PR tay, Refs #44\n' > "$TMP/b44.md"
card 44 "$TMP/b44.md" "$TMP/issue1.md" '[]'
rc=$(gate 44)
[ "$rc" = 0 ] && ! grep -q 'issue ' "$TMP/calls" && ok "M4: PR không Closes thẻ → không comment" || fail "M4: rc=$rc $(tr '\n' '|' < "$TMP/calls")"

# M5 — nhánh không mang số thẻ (ac-check bỏ qua, AC_CARD rỗng) nhưng PR đóng #45: vẫn comment trên #45.
printf 'Closes #45\n' > "$TMP/b45.md"
card 45 "$TMP/b45.md" "$TMP/issue1.md" '[]'
git -C "$R" push -q origin "issue-45-x:refs/heads/split/c45"
echo split/c45 > "$TMP/pr45.ref"; echo 45 > "$TMP/pr45.closes"
rc=$(gate 45)
[ "$rc" = 0 ] && [ "$(merged_comment 45)" = 1 ] && ok "M5: nhánh split/… đóng #45 → comment ✅ merged trên #45" \
  || fail "M5: rc=$rc err=$(tail -2 "$TMP/gate45.err") calls=$(tr '\n' '|' < "$TMP/calls" | tail -c 400)"

# M6 — phản hồi merge mất: GitHub đọc lại thấy MERGED → nhánh "merge response was lost" vẫn comment trên thẻ.
printf 'Closes #46\n<!-- sb:ac -->\n- [x] Test: lane gọi gate trực tiếp có comment merged\n<!-- /sb:ac -->\n' > "$TMP/b46.md"
card 46 "$TMP/b46.md" "$TMP/issue1.md" '[]'
: > "$TMP/pr46.lost"; echo 46 > "$TMP/pr46.closes"
rc=$(gate 46)
[ "$rc" = 0 ] && grep -q 'merge response was lost' "$TMP/gate46.err" && [ "$(merged_comment 46)" = 1 ] \
  && grep -q '✅ merged 6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b46 · PR #46' "$TMP/calls" \
  && ok "M6: mất phản hồi merge, GitHub báo MERGED → comment ✅ merged <sha GitHub báo>" \
  || fail "M6: rc=$rc err=$(tail -3 "$TMP/gate46.err") calls=$(tr '\n' '|' < "$TMP/calls" | tail -c 400)"

[ "$FAILS" = 0 ] && echo "ALL PASS" || { echo "$FAILS FAIL"; exit 1; }
