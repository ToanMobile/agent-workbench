#!/usr/bin/env bash
# #724: một đợt thẻ = một nhánh, một PR, một lần gate. PR trên nhánh issue-<trưởng> Closes thẻ trưởng VÀ các thành viên đợt
# (thẻ mà body issue mang `<!-- sb:batch-of #<trưởng> -->`, do create_task.py ghi lúc tạo). Trước đây ac-check coi mọi Closes
# khác thẻ của nhánh là thẻ lạ ⇒ merge gate exit 11, nên N thẻ khác scope luôn là N nhánh/PR/gate.
# - A (ac-check): thành viên có marker đúng ⇒ không foreign, vào `batch`, AC của nó cộng vào issue_ac; marker trỏ thẻ khác,
#   marker trong code fence, body rỗng (không đọc được) ⇒ vẫn foreign (fail-closed, T0054).
# - B: PR Closes #31 #32 #33, sb:ac đủ 6 dòng ⇒ merge (bản cũ: exit 11).
# - C: thiếu dòng AC của thành viên ⇒ exit 11 "has 6".
# - D: còn dòng chưa tick ⇒ merge nhưng Closes → Refs cho thẻ trưởng VÀ mọi thành viên (body PR + message squash).
# - E: thêm Closes thẻ không marker ⇒ exit 11 nêu đúng thẻ đó.
# - F: PR đợt không có khối sb:ac ⇒ exit 11 như cũ, không đọc issue thành viên.
# SB_GATE=<file> / SB_AC=<file> chạy bản cũ để thấy ĐỎ. Offline, bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${SB_GATE:-$ROOT/.claude/bin/super-board-merge-gate.sh}"
AC="${SB_AC:-$ROOT/.claude/bin/super-board-ac-check.py}"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
field() { python3 -c 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print(json.dumps(v) if isinstance(v,(list,bool)) or v is None else v)' "$1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mergegate-batch.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# member <N> <trưởng> <số AC>: body thẻ thành viên như create_task.py ghi.
member() {
  { printf '## Problem\nviệc %s\n\n## Acceptance Criteria\n' "$1"
    i=1; while [ "$i" -le "$3" ]; do printf -- '- [ ] M%s-%s\n' "$1" "$i"; i=$((i + 1)); done
    printf '\n## Blocked by\n- #%s — đợt: build chung nhánh issue-%s-…, một PR, một gate\n<!-- sb:batch-of #%s -->\n' "$2" "$2" "$2"
  } > "$TMP/m$1.md"
}
cat > "$TMP/lead.md" <<'EOF'
## Acceptance Criteria
- [ ] L1
- [ ] L2
- [ ] L3

## Blocked by
- None.
EOF

# ---- A. ac-check.py ---------------------------------------------------------------------------------------------------------
member 32 31 2; member 33 31 1
printf 'Closes #31\nCloses #32\nCloses #33\n' > "$TMP/a-pr.md"
out=$(python3 "$AC" --pr-body "$TMP/a-pr.md" --branch issue-31-dot --batch-member-body "32=$TMP/m32.md" --batch-member-body "33=$TMP/m33.md" 2>&1)
[ "$(printf '%s' "$out" | field foreign_closes 2>/dev/null)" = "[]" ] && [ "$(printf '%s' "$out" | field batch 2>/dev/null)" = "[32, 33]" ] \
  && ok "A1 thành viên mang marker #31 → không foreign, batch [32, 33]" || fail "A1 $out"
{ cat "$TMP/a-pr.md"; printf '<!-- sb:ac -->\n- [x] L1\n- [x] L2\n- [x] L3\n- [x] [#32] M32-1\n- [x] [#32] M32-2\n<!-- /sb:ac -->\n'; } > "$TMP/a-pr5.md"
out=$(python3 "$AC" --issue-body "$TMP/lead.md" --pr-body "$TMP/a-pr5.md" --branch issue-31-dot \
  --batch-member-body "32=$TMP/m32.md" --batch-member-body "33=$TMP/m33.md" 2>&1)
[ "$(printf '%s' "$out" | field issue_ac 2>/dev/null)" = 6 ] && [ "$(printf '%s' "$out" | field collapsed 2>/dev/null)" = true ] \
  && ok "A2 AC thành viên cộng vào thẻ trưởng (3 + 2 + 1 = 6), sb:ac 5 dòng → collapsed" || fail "A2 $out"
member 34 99 1
sed 's/^\(<!-- sb:batch-of #31 -->\)$/```\n\1\n```/' "$TMP/m33.md" > "$TMP/m33fence.md"
: > "$TMP/empty.md"
for spec in "34=$TMP/m34.md:marker trỏ thẻ khác (#99)" "33=$TMP/m33fence.md:marker trong code fence" "33=$TMP/empty.md:body rỗng (không đọc được)"; do
  arg=${spec%%:*}; name=${spec#*:}; n=${arg%%=*}
  printf 'Closes #31\nCloses #%s\n' "$n" > "$TMP/a-one.md"
  out=$(python3 "$AC" --pr-body "$TMP/a-one.md" --branch issue-31-dot --batch-member-body "$arg" 2>&1)
  [ "$(printf '%s' "$out" | field foreign_closes 2>/dev/null)" = "[$n]" ] && [ "$(printf '%s' "$out" | field batch 2>/dev/null)" = "[]" ] \
    && ok "A3 $name → vẫn là thẻ lạ" || fail "A3 $name: $out"
done
out=$(python3 "$AC" --pr-body "$TMP/a-pr.md" --branch issue-31-dot --batch-member-body "32=$TMP/m32.md" 2>&1)
[ "$(printf '%s' "$out" | field collapsed 2>/dev/null)" = true ] && [ "$(printf '%s' "$out" | field issue_ac 2>/dev/null)" = 2 ] \
  && ok "A5 Closes thành viên mà PR không có khối sb:ac → collapsed (AC của thành viên chưa ai chứng minh)" || fail "A5 $out"
out=$(python3 "$AC" --pr-body "$TMP/a-pr.md" --branch issue-31-dot 2>&1)
[ "$(printf '%s' "$out" | field foreign_closes 2>/dev/null)" = "[32, 33]" ] && ok "A4 không truyền body thành viên → như cũ, cả hai là thẻ lạ" || fail "A4 $out"

# ---- B–E. merge gate ---------------------------------------------------------------------------------------------------------
O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"
git -C "$R" push -q origin main

# lead <N> <pr body file>: nhánh issue-<N>-dot, mỗi thẻ của đợt một commit `(#m)` (quy ước builder), metadata + issue cho gh giả.
lead() {
  local n="$1" m
  git -C "$R" fetch -q origin
  git -C "$R" branch -q --no-track "issue-$n-dot" origin/main
  git -C "$R" worktree add -q "$W/issue-$n-build" "issue-$n-dot"
  for m in $n $((n + 1)) $((n + 2)); do
    echo "$m" > "$W/issue-$n-build/f$m"; git -C "$W/issue-$n-build" add "f$m"; git -C "$W/issue-$n-build" commit -qm "việc $m (#$m)"
  done
  git -C "$R" push -q origin "issue-$n-dot"
  git -C "$R" rev-parse "issue-$n-dot" > "$TMP/pr$n.head"
  git -C "$R" diff origin/main "issue-$n-dot" > "$TMP/pr$n.diff"
  jq -n --rawfile b "$2" --arg a "f$n" --arg b2 "f$((n + 1))" --arg c "f$((n + 2))" \
    '{files:[{path:$a},{path:$b2},{path:$c}],labels:[],body:$b,additions:3,deletions:0,changedFiles:3}' > "$TMP/pr$n.meta"
  jq -n --rawfile b "$TMP/lead.md" --argjson n "$n" '{number:$n,title:"t",body:$b,labels:[]}' > "$TMP/issue$n.json"
  member $((n + 1)) "$n" 2; member $((n + 2)) "$n" 1
  for m in $((n + 1)) $((n + 2)); do jq -n --rawfile b "$TMP/m$m.md" --argjson n "$m" '{number:$n,title:"t",body:$b,labels:[]}' > "$TMP/issue$m.json"; done
  git -C "$R" worktree add -q --detach "$W/issue-$n-review" "$(cat "$TMP/pr$n.head")"
}
# pr_body <N> <dòng sb:ac…>: Closes thẻ trưởng + 2 thành viên, rồi khối sb:ac.
pr_body() {
  local n="$1"; shift
  { printf 'Đợt #%s\n\nCloses #%s\nCloses #%s\nCloses #%s\n\n<!-- sb:ac -->\n' "$n" "$n" $((n + 1)) $((n + 2))
    printf '%s\n' "$@"; printf '<!-- /sb:ac -->\n'; } > "$TMP/b$n.md"
}

mkdir -p "$TMP/bin" "$TMP/cache"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls"
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
case " $* " in
  *" api graphql "*) echo '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"I"}}}}' ;;
  *" pr view "*"headRefName,headRefOid"*) echo "issue-$n-dot $(cat "$FAKE_DIR/pr$n.head")" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*) printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$(cat "$FAKE_DIR/pr$n.head")" ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"title"*) echo "t" ;;
  *" pr view "*"--json body"*) jq -r '.body' "$FAKE_DIR/pr$n.meta" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr edit "*) f=$(printf '%s\n' "$@" | sed -n '/^--body-file$/{n;p;}'); cp "$f" "$FAKE_DIR/pr$n.edited" ;;
  *" pr merge "*) f=$(printf '%s\n' "$@" | sed -n '/^--body-file$/{n;p;}'); [ -n "$f" ] && cp "$f" "$FAKE_DIR/merge$n.msg"; echo merged ;;
  *" issue view "*"-q .body"*) [ -e "$FAKE_DIR/issue$n.json" ] || exit 1; jq -r '.body' "$FAKE_DIR/issue$n.json" ;;
  *" issue view "*) cat "$FAKE_DIR/issue$n.json" ;;
  *" issue "*|*" label "*) : ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" SB_CARD_CACHE_DIR="$TMP/cache" SB_NOTIFY_SKIP=1
export SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_MERGE_RECHECK_DELAY_S=0 SB_MERGE_LOAD_MAX=100000
printf '{"projectId":"P","fieldId":"F","options":{"Ready":"o-r","Done":"o-d"},"items":{"31":"I31","41":"I41","51":"I51","61":"I61","71":"I71"}}' > "$TMP/cache/board-o-1.json"
CFG="$TMP/cfg.json"
echo '{"base_branch":"main","repo":{"path":".","remote":""},"project":{"owner":"o","number":1},"verify_commands":["touch '"$TMP"'/verified"]}' > "$CFG"
gate() {  # $1 = PR; stdout → gate$1.out, stderr → gate$1.err; echo rc
  rm -f "$TMP/calls" "$TMP/verified"
  ( cd "$W/issue-$1-review" && bash "$GATE" --config "$CFG" --pr "$1" --expect-head "$(cat "$TMP/pr$1.head")" ) \
    >"$TMP/gate$1.out" 2>"$TMP/gate$1.err"; echo $?
}

# B — 3 thẻ khác scope, một nhánh, một PR, sb:ac đủ 6 dòng → merge exit 0.
pr_body 31 '- [x] L1' '- [x] L2' '- [x] L3' '- [x] [#32] M32-1' '- [x] [#32] M32-2' '- [x] [#33] M33-1'
lead 31 "$TMP/b31.md"
rc=$(gate 31)
[ "$rc" = 0 ] && grep -q 'pr merge 31' "$TMP/calls" && [ -e "$TMP/verified" ] && ! grep -q 'pr edit 31' "$TMP/calls" \
  && grep -q 'issue view 32' "$TMP/calls" && grep -q 'issue view 33' "$TMP/calls" \
  && ok "B: một PR Closes #31 #32 #33 (thành viên đợt), sb:ac đủ → verify MỘT lần, merge" \
  || fail "B: rc=$rc out=$(tail -2 "$TMP/gate31.out") err=$(tail -3 "$TMP/gate31.err")"

# C — thiếu dòng AC của #33 → 5 < 6 → exit 11, không merge.
pr_body 41 '- [x] L1' '- [x] L2' '- [x] L3' '- [x] [#42] M42-1' '- [x] [#42] M42-2'
lead 41 "$TMP/b41.md"
rc=$(gate 41)
[ "$rc" = 11 ] && grep -q 'ac-check: card #41 has 6' "$TMP/gate41.out" && ! grep -q 'pr merge' "$TMP/calls" \
  && ok "C: thiếu AC của thành viên #43 → exit 11 'has 6', không merge" || fail "C: rc=$rc out=$(tail -2 "$TMP/gate41.out")"

# D — còn dòng chưa tick (của thành viên) → merge, nhưng KHÔNG thẻ nào của đợt tự đóng: Closes → Refs cho #51 #52 #53.
pr_body 51 '- [x] L1' '- [x] L2' '- [x] L3' '- [x] [#52] M52-1' '- [ ] [#52] M52-2' '- [x] [#53] M53-1'
lead 51 "$TMP/b51.md"
rc=$(gate 51)
[ "$rc" = 0 ] && grep -q 'pr merge 51' "$TMP/calls" && ok "D: còn AC chưa tick → vẫn merge" || fail "D: rc=$rc err=$(tail -3 "$TMP/gate51.err")"
python3 - "$TMP/pr51.edited" "$TMP/merge51.msg" <<'PY' && ok "D: body PR + message squash: Refs #51 #52 #53, không còn Closes" || fail "D: $(cat "$TMP/pr51.edited" "$TMP/merge51.msg" 2>&1 | head -12)"
import re, sys
try:
    body, msg = (open(p).read() for p in sys.argv[1:3])
except OSError:
    sys.exit(1)
closes = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\s+#(\d+)", re.I)
sys.exit(0 if not closes.search(body) and not closes.search(msg) and all(f"Refs #{n}" in body for n in (51, 52, 53)) else 1)
PY
grep -q '^ac-open: #51$' "$TMP/gate51.out" && grep -q 'issue edit 51 --add-label ac-open' "$TMP/calls" \
  && ok "D: thẻ trưởng #51 mang ac-open (thành viên ở lại cùng đợt)" || fail "D: ac-open: $(tr '\n' '|' < "$TMP/calls" | tail -c 400)"

# E — thêm Closes #64 (không marker) → exit 11 nêu #64, không nêu thành viên.
pr_body 61 '- [x] L1' '- [x] L2' '- [x] L3' '- [x] [#62] M62-1' '- [x] [#62] M62-2' '- [x] [#63] M63-1'
printf 'Closes #64\n' >> "$TMP/b61.md"
lead 61 "$TMP/b61.md"
jq -n '{number:64,title:"t",body:"## Acceptance Criteria\n- [ ] x\n\n## Blocked by\n- None.\n",labels:[]}' > "$TMP/issue64.json"
rc=$(gate 61)
[ "$rc" = 11 ] && grep -q 'closes #64' "$TMP/gate61.out" && ! grep -q 'closes #6[23]' "$TMP/gate61.out" && ! grep -q 'pr merge' "$TMP/calls" \
  && ok "E: Closes thẻ không thuộc đợt → exit 11 chỉ nêu #64" || fail "E: rc=$rc out=$(tail -2 "$TMP/gate61.out")"

# F — PR đợt không có khối sb:ac (AC thành viên không được liệt kê) → exit 11 như Closes thẻ lạ, không đọc issue thành viên.
printf 'Closes #71\nCloses #72\nCloses #73\n' > "$TMP/b71.md"
lead 71 "$TMP/b71.md"
rc=$(gate 71)
[ "$rc" = 11 ] && grep -q 'closes #72, #73' "$TMP/gate71.out" && ! grep -q 'issue view 7[23]' "$TMP/calls" && ! grep -q 'pr merge' "$TMP/calls" \
  && ok "F: PR đợt không có sb:ac → exit 11, không đọc issue thành viên" || fail "F: rc=$rc out=$(tail -2 "$TMP/gate71.out") calls=$(grep 'issue view' "$TMP/calls" | head -3)"

[ "$FAILS" -eq 0 ] && { echo "merge gate batch: all checks passed"; exit 0; }
echo "merge gate batch: $FAILS FAILED"; exit 1
