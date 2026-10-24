#!/usr/bin/env bash
# T0054 (24/10): merge gate đối chiếu AC của thẻ với khối sb:ac của PR.
# - A (collapsed): thẻ 3 AC, sb:ac 1 dòng → exit 11, không merge (PR #343 nén 7 AC của #318 thành 3 dòng).
# - B (foreign): PR body Closes thẻ khác → exit 11, không merge.
# - C (unticked): còn dòng chưa tick → vẫn merge; Closes → Refs ở body PR và message; nhãn ac-open; comment; thẻ về Ready;
#   stdout có "ac-open: #N".
# - D (proved): đủ AC tick, thẻ đang mang ac-open → gỡ nhãn.
# - E (no block): PR không có sb:ac → hành vi cũ, không đọc issue.
# SB_GATE=<file> chạy bản cũ để thấy ĐỎ. Offline, bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${SB_GATE:-$ROOT/.claude/bin/super-board-merge-gate.sh}"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mergegate-ac.XXXXXX")"
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
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-x $(cat "$FAKE_DIR/pr$n.head")" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$(cat "$FAKE_DIR/pr$n.head")" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"title"*) [ -e "$FAKE_DIR/pr$n.title.fail" ] && exit 1; cat "$FAKE_DIR/pr$n.title" 2>/dev/null || echo "t" ;;
  *" pr view "*"--json body"*) if [ -e "$FAKE_DIR/pr$n.body2" ]; then cat "$FAKE_DIR/pr$n.body2"; else jq -r '.body' "$FAKE_DIR/pr$n.meta"; fi ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr edit "*) f=$(printf '%s\n' "$@" | sed -n '/^--body-file$/{n;p;}'); cp "$f" "$FAKE_DIR/pr$n.edited" ;;
  *" pr merge "*) f=$(printf '%s\n' "$@" | sed -n '/^--body-file$/{n;p;}'); [ -n "$f" ] && cp "$f" "$FAKE_DIR/merge$n.msg"; echo merged ;;
  *" issue view "*"-q .body"*) jq -r '.body' "$FAKE_DIR/issue$n.json" ;;
  *" issue view "*) cat "$FAKE_DIR/issue$n.json" ;;
  *" issue "*|*" label "*) : ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" SB_CARD_CACHE_DIR="$TMP/cache" SB_NOTIFY_SKIP=1
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_MERGE_RECHECK_DELAY_S=0 SB_MERGE_LOAD_MAX=100000
printf '{"projectId":"P","fieldId":"F","options":{"Ready":"o-r","Done":"o-d"},"items":{"21":"I21","23":"I23","24":"I24","41":"I41"}}' > "$TMP/cache/board-o-1.json"
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"project":{"owner":"o","number":1},"verify_commands":["true"]}' > "$CFG"
gate() {  # $1 = PR; stdout → gate$1.out, stderr → gate$1.err; echo rc
  rm -f "$TMP/calls"
  ( cd "$W/issue-$1-review" && bash "$GATE" --config "$CFG" --pr "$1" --expect-head "$(cat "$TMP/pr$1.head")" ) \
    >"$TMP/gate$1.out" 2>"$TMP/gate$1.err"; echo $?
}

cat > "$TMP/issue3.md" <<'EOF'
## Acceptance Criteria
- [ ] Test: khoá B → HIT
- Test: lượt 2 dùng lại REG-DK-ALL-01
- [ ] Đo tỷ lệ dùng lại ≥ 50%
EOF

# A — collapsed.
printf 'Closes #21\n<!-- sb:ac -->\n- [x] AC đạt hết\n<!-- /sb:ac -->\n' > "$TMP/b21.md"
card 21 "$TMP/b21.md" "$TMP/issue3.md" '[]'
rc=$(gate 21)
[ "$rc" = 11 ] && grep -q 'ac-check: card #21 has 3' "$TMP/gate21.out" && ! grep -q 'pr merge' "$TMP/calls" \
  && ok "A: 3 AC nén thành 1 dòng → exit 11, không merge" || fail "A: rc=$rc out=$(tail -2 "$TMP/gate21.out") err=$(tail -2 "$TMP/gate21.err")"

# B — foreign closes (không cần sb:ac, không đọc issue).
printf 'Closes #315\n' > "$TMP/b22.md"
card 22 "$TMP/b22.md" "$TMP/issue3.md" '[]'
rc=$(gate 22)
[ "$rc" = 11 ] && grep -q 'closes #315' "$TMP/gate22.out" && ! grep -q 'issue view' "$TMP/calls" && ! grep -q 'pr merge' "$TMP/calls" \
  && ok "B: Closes thẻ khác → exit 11, không đọc issue, không merge" || fail "B: rc=$rc out=$(tail -2 "$TMP/gate22.out")"

# C — unticked: merge, Refs, nhãn, comment, Ready, ac-open.
cat > "$TMP/b23.md" <<'EOF'
> ⏳ Closes #23
<!-- sb:ac -->
- [x] Test: khoá B → HIT\
  ↳ ca 1
- [x] Test: lượt 2 dùng lại REG-DK-ALL-01
- [ ] Đo tỷ lệ dùng lại ≥ 50%\
  ↳ đo sau merge
<!-- /sb:ac -->
EOF
card 23 "$TMP/b23.md" "$TMP/issue3.md" '[]'
rc=$(gate 23)
[ "$rc" = 0 ] && grep -q 'pr merge' "$TMP/calls" && ok "C: còn AC chưa tick → vẫn merge (exit 0)" || fail "C: rc=$rc err=$(tail -3 "$TMP/gate23.err")"
grep -q 'Refs #23' "$TMP/pr23.edited" 2>/dev/null && ! grep -qi 'closes #23' "$TMP/pr23.edited" \
  && grep -q '^Refs #23$' "$TMP/merge23.msg" 2>/dev/null && grep -q '^\* card 23' "$TMP/merge23.msg" \
  && ok "C: Closes #23 → Refs ở body PR và message squash" || fail "C: body/msg: $(cat "$TMP/pr23.edited" "$TMP/merge23.msg" 2>&1 | head -5)"
grep -q 'issue edit 23 --add-label ac-open' "$TMP/calls" && grep -q 'issue comment 23' "$TMP/calls" \
  && grep -q 'singleSelectOptionId' "$TMP/calls" && grep -q 'o=o-r' "$TMP/calls" && grep -q '^ac-open: #23$' "$TMP/gate23.out" \
  && ok "C: nhãn ac-open, comment, thẻ về Ready, stdout ac-open: #23" || fail "C: post-merge: $(tr '\n' '|' < "$TMP/calls")"
# thứ tự: body PR được sửa TRƯỚC lệnh merge
awk '/pr edit 23/{e=NR} /pr merge 23/{m=NR} END{exit !(e && m && e < m)}' "$TMP/calls" && ok "C: sửa body PR trước khi merge" || fail "C: order"

# D — đủ AC, nhãn ac-open đang có → gỡ.
sed 's/- \[ \] Đo/- [x] Đo/' "$TMP/b23.md" | sed 's/#23/#24/' > "$TMP/b24.md"
card 24 "$TMP/b24.md" "$TMP/issue3.md" '[{"name":"ac-open"}]'
rc=$(gate 24)
[ "$rc" = 0 ] && grep -q 'issue edit 24 --remove-label ac-open' "$TMP/calls" && ! grep -q '^ac-open:' "$TMP/gate24.out" \
  && ! grep -q 'pr edit 24' "$TMP/calls" && ok "D: đủ AC → merge, gỡ nhãn ac-open, không sửa body" || fail "D: rc=$rc $(tr '\n' '|' < "$TMP/calls")"
awk '/remove-label ac-open/{e=NR} /pr merge 24/{m=NR} END{exit !(e && m && e < m)}' "$TMP/calls" \
  && ok "D: gỡ nhãn TRƯỚC merge (runner không mở lại issue vừa được Closes đóng)" || fail "D: order"

# E — không có sb:ac, không tự Closes thẻ: như cũ, không đọc issue.
printf 'PR tay, Refs #25\n' > "$TMP/b25.md"
card 25 "$TMP/b25.md" "$TMP/issue3.md" '[]'
rc=$(gate 25)
[ "$rc" = 0 ] && ! grep -q 'issue ' "$TMP/calls" && ! grep -q 'pr edit' "$TMP/calls" \
  && ok "E: PR không có sb:ac, không Closes → merge như cũ, không đụng issue" || fail "E: rc=$rc $(tr '\n' '|' < "$TMP/calls")"

# G — không có sb:ac mà vẫn Closes #27 (nén về 0 dòng) trong khi thẻ có 3 AC → exit 11, không merge.
printf 'Closes #27\n' > "$TMP/b27.md"
card 27 "$TMP/b27.md" "$TMP/issue3.md" '[]'
rc=$(gate 27)
[ "$rc" = 11 ] && grep -q 'ac-check: card #27 has 3' "$TMP/gate27.out" && ! grep -q 'pr merge' "$TMP/calls" \
  && ok "G: không có sb:ac mà Closes thẻ có AC → exit 11" || fail "G: rc=$rc out=$(tail -2 "$TMP/gate27.out")"

# H — đúng ca #318/PR #343: thẻ chỉ ghi "AC của thẻ #315" + 1 dòng gate; #315 có 3 AC; sb:ac 2 dòng đã tick → exit 11.
printf '## Acceptance Criteria\n- [ ] AC của thẻ #315 đạt (xem Acceptance Criteria trong thẻ đó)\n- [ ] Gate --full exit 0\n' > "$TMP/i28.md"
jq -n --rawfile b "$TMP/issue3.md" '{number:315,title:"t",body:$b,labels:[]}' > "$TMP/issue315.json"
printf 'Closes #28\n<!-- sb:ac -->\n- [x] AC #315 mục 3 đạt\n- [x] Gate --full exit 0\n<!-- /sb:ac -->\n' > "$TMP/b28.md"
card 28 "$TMP/b28.md" "$TMP/i28.md" '[]'
rc=$(gate 28)
[ "$rc" = 11 ] && grep -q 'ac-check: card #28 has 4' "$TMP/gate28.out" && grep -q 'issue view 315' "$TMP/calls" && ! grep -q 'pr merge' "$TMP/calls" \
  && ok "H: AC gián tiếp 'AC của thẻ #315' được mở rộng ở gate (3 + 1 = 4 > 2) → exit 11 (ca #318/#343)" \
  || fail "H: rc=$rc out=$(tail -2 "$TMP/gate28.out") err=$(tail -2 "$TMP/gate28.err")"

# I — tiêu đề PR "Fix #29: …" (thành subject squash) + còn AC chưa tick → subject merge đổi thành "Refs #29"; tiêu đề
#     "Fix #315: …" (thẻ lạ) → exit 11.
sed 's/#23/#29/' "$TMP/b23.md" > "$TMP/b29.md"; printf 'Fix #29: cache gate\n' > "$TMP/pr29.title"
card 29 "$TMP/b29.md" "$TMP/issue3.md" '[]'
rc=$(gate 29)
[ "$rc" = 0 ] && grep -q 'pr merge 29.*--subject Refs #29: cache gate (#29)' "$TMP/calls" \
  && ok "I: tiêu đề 'Fix #29' thành subject squash đã đổi sang Refs" || fail "I: rc=$rc $(grep 'pr merge 29' "$TMP/calls")"
printf '<!-- sb:ac -->\n- [x] a\n- [x] b\n- [x] c\n<!-- /sb:ac -->\n' > "$TMP/b30.md"; printf 'Fix #315: cache gate\n' > "$TMP/pr30.title"
card 30 "$TMP/b30.md" "$TMP/issue3.md" '[]'
rc=$(gate 30)
[ "$rc" = 11 ] && grep -q 'closes #315' "$TMP/gate30.out" && ok "I: tiêu đề PR đóng thẻ lạ → exit 11" || fail "I': rc=$rc $(tail -2 "$TMP/gate30.out")"

# J — body không có sb:ac, không Closes; chỉ commit "Closes #31" (message squash từ commit) → thẻ có 3 AC → exit 11.
printf 'mô tả tay\n' > "$TMP/b31.md"
card 31 "$TMP/b31.md" "$TMP/issue3.md" '[]' "fix: x

Closes #31"
rc=$(gate 31)
[ "$rc" = 11 ] && grep -q 'closes card #31 (3 acceptance criteria)' "$TMP/gate31.out" && ! grep -q 'pr merge' "$TMP/calls" \
  && ok "J: chỉ commit Closes thẻ mình, không có sb:ac → exit 11" || fail "J: rc=$rc out=$(tail -2 "$TMP/gate31.out") err=$(tail -2 "$TMP/gate31.err")"
# K — không có sb:ac, Closes #32, body thẻ rỗng → không crash (jq), merge như cũ.
printf 'Closes #32\n' > "$TMP/b32.md"; : > "$TMP/empty.md"
card 32 "$TMP/b32.md" "$TMP/empty.md" '[]'
rc=$(gate 32)
[ "$rc" = 0 ] && grep -q 'pr merge 32' "$TMP/calls" && ok "K: thẻ không có AC, không sb:ac → merge, không crash" || fail "K: rc=$rc err=$(tail -3 "$TMP/gate32.err")"

# F — không --body-file: message squash lấy từ commit của nhánh; commit có "Closes #315" (thẻ lạ) → exit 11, không merge.
printf 'không có khối ac\n' > "$TMP/b26.md"
card 26 "$TMP/b26.md" "$TMP/empty.md" '[]' "fix: thứ gì đó

Closes #315
Closes #26"
rc=$(gate 26)
# Commit đã push không sửa được nếu không viết lại lịch sử: gate không trả về Build (sẽ lặp) mà tự đổi sang Refs.
[ "$rc" = 0 ] && grep -q 'pr merge 26.*--body-file' "$TMP/calls" && grep -q '^Refs #315$' "$TMP/merge26.msg" \
  && ! grep -qi 'closes #315' "$TMP/merge26.msg" && grep -q '^Closes #26$' "$TMP/merge26.msg" \
  && ok "F: commit Closes thẻ lạ → message squash 'Refs #315', giữ 'Closes #26' của chính thẻ, không exit 11 lặp" \
  || fail "F: rc=$rc msg=$(cat "$TMP/merge26.msg" 2>/dev/null) err=$(tail -2 "$TMP/gate26.err")"

# L (#319, T0054 edge 3) — the PR title cannot be read (network) while the branch is a card: exit 4 for a later wave, never a merge whose
#     subject nobody checked for Closes.
printf '<!-- sb:ac -->\n- [x] a\n- [x] b\n- [x] c\n<!-- /sb:ac -->\nCloses #40\n' > "$TMP/b40.md"
card 40 "$TMP/b40.md" "$TMP/issue3.md" '[]'; : > "$TMP/pr40.title.fail"
rc=$(gate 40)
[ "$rc" = 4 ] && ! grep -q 'pr merge' "$TMP/calls" && ok "L: tiêu đề PR không đọc được → exit 4, không merge" || fail "L: rc=$rc $(tr '\n' '|' < "$TMP/calls")"

# M (#319, T0054 edge 2) — the PR body changes while verify runs (a reviewer unticks a line): the AC verdict is taken again right before
#     the merge. Ticked at the start, one line unticked by merge time → Refs, ac-open, no label removal (the card must stay open).
printf 'Closes #41\n<!-- sb:ac -->\n- [x] Test: khoá B → HIT\n- [x] Test: lượt 2 dùng lại REG-DK-ALL-01\n- [x] Đo tỷ lệ dùng lại ≥ 50%%\n<!-- /sb:ac -->\n' > "$TMP/b41.md"
sed 's/- \[x\] Đo/- [ ] Đo/' "$TMP/b41.md" > "$TMP/b41.now"
card 41 "$TMP/b41.md" "$TMP/issue3.md" '[{"name":"ac-open"}]'; cp "$TMP/b41.now" "$TMP/pr41.body2"
rc=$(gate 41)
[ "$rc" = 0 ] && grep -q '^ac-open: #41$' "$TMP/gate41.out" && grep -q '^Refs #41$' "$TMP/merge41.msg" 2>/dev/null && ! grep -qi 'closes #41' "$TMP/merge41.msg" \
  && ! grep -q 'remove-label ac-open' "$TMP/calls" && ok "M: AC bỏ tick trong lúc verify → Refs + ac-open, không gỡ nhãn" \
  || fail "M: rc=$rc msg=$(cat "$TMP/merge41.msg" 2>/dev/null) calls=$(tr '\n' '|' < "$TMP/calls")"
# N — the body collapsed to fewer lines during verify: exit 11, no merge.
printf 'Closes #42\n<!-- sb:ac -->\n- [x] gộp tất cả\n<!-- /sb:ac -->\n' > "$TMP/b42.now"
sed 's/#41/#42/' "$TMP/b41.md" > "$TMP/b42.md"
card 42 "$TMP/b42.md" "$TMP/issue3.md" '[]'; cp "$TMP/b42.now" "$TMP/pr42.body2"
rc=$(gate 42)
[ "$rc" = 11 ] && ! grep -q 'pr merge' "$TMP/calls" && ok "N: body nén lại trong lúc verify → exit 11, không merge" || fail "N: rc=$rc $(tr '\n' '|' < "$TMP/calls")"

# N2 (OCR 24/10) — the recheck message names only the problem that exists: a collapsed block says so and does not claim a foreign close.
! grep -qi 'closes' "$TMP/gate42.out" && grep -q 'lists 1 AC lines but card #42 has 3' "$TMP/gate42.out" \
  && ok "N2: nén lại trong lúc verify → thông báo chỉ nói số dòng AC, không nói đóng thẻ lạ" || fail "N2: out=$(cat "$TMP/gate42.out")"
# O — only a foreign Closes appeared during verify (the block still lists every AC): exit 11 and the message must NOT say the block lists fewer lines.
sed 's/#41/#43/' "$TMP/b41.md" > "$TMP/b43.md"
{ cat "$TMP/b43.md"; printf 'Closes #315\n'; } > "$TMP/b43.now"
card 43 "$TMP/b43.md" "$TMP/issue3.md" '[]'; cp "$TMP/b43.now" "$TMP/pr43.body2"
rc=$(gate 43)
[ "$rc" = 11 ] && ! grep -q 'pr merge' "$TMP/calls" && grep -q 'closes #315' "$TMP/gate43.out" && ! grep -q 'fewer AC lines\|lists .* AC lines' "$TMP/gate43.out" \
  && ok "O: chỉ có Closes thẻ lạ trong lúc verify → exit 11, thông báo không nói thiếu dòng AC" || fail "O: rc=$rc out=$(cat "$TMP/gate43.out")"

[ "$FAILS" -eq 0 ] && { echo "merge gate ac-check: all checks passed"; exit 0; }
echo "merge gate ac-check: $FAILS FAILED"; exit 1
