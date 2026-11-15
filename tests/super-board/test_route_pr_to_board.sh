#!/usr/bin/env bash
# #1192: PR mở bằng `gh pr create` ngoài board (nhánh chore/…, fix/…, không thẻ) không vào lane nào, phiên tác giả bị cấm tự duyệt (#605)
# nên agent đẩy việc duyệt cho chủ repo. Luật ở đây:
#  (a) route-pr: nhánh issue-12-x, thẻ Building → move QA, body thêm `Closes #12`
#  (b) body `Closes #N`, thẻ Review → giữ, không move
#  (c) PR draft → không ghi gì
#  (d) không config super-board → exit 0, test đòi file ghi lời gọi gh ($ST/writes) rỗng
#  (e) status rc 3 → gh project item-add URL ISSUE rồi QA; status rc 69 → exit 69, không move
#  (f) chạy 2 lần: lần 2 không ghi gì
#  (g) hook PreToolUse: gh pr create từ fix/x ở repo có board → exit 2 kèm cách sửa; issue-3-x / --draft / repo không board / chữ trong tham số → 0
#  (h) hook PostToolUse: URL …/pull/<n> trong output → gọi route-pr; lệnh khác → không; route-pr lỗi → exit 0 + additionalContext
#  (i) wave-plan: PR nhãn merge-queue trên nhánh không issue-* có closingIssuesReferences #N → N vào QUEUED_ISSUES (thẻ bị ẩn khỏi wave)
# Chạy offline: gh, super-board-card.sh và route-pr (ở (h)) là stub. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROUTE="$ROOT/.claude/bin/super-board-route-pr.sh"
HOOK="$ROOT/universal-agent-devkit/hooks/route_pr_to_board.py"
PLAN="$ROOT/.claude/bin/super-board-wave-plan.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-route-pr.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CEILING_DIRECTORIES="$TMP"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE SB_CONFIG
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/st"
[ -f "$ROUTE" ] && cp "$ROUTE" "$TMP/bin/super-board-route-pr.sh"
printf '{"project":{"owner":"acme","number":7},"repo":{"path":".","remote":"https://github.com/acme/widgets"},"base_branch":"main"}\n' > "$TMP/cfg.json"

# super-board-card.sh giả: status đọc $ST/status (rỗng được), rc từ $ST/status_rc; move ghi lời gọi + đổi status
cat > "$TMP/bin/super-board-card.sh" <<'SH'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --config|--owner|--number|--repo) shift 2 ;; *) break ;; esac; done
case "$1" in
  status) rc=$(cat "$ST/status_rc" 2>/dev/null || echo 0)
          [ "$rc" = 0 ] || { echo "stub status rc $rc" >&2; exit "$rc"; }
          cat "$ST/status" ;;
  move)   echo "move $2 $3" >> "$ST/writes"; printf '%s\n' "$3" > "$ST/status" ;;
  *)      echo "stub card: $*" >&2; exit 64 ;;
esac
SH
# gh giả: pr view in JSON từ $ST/pr + body từ $ST/body; pr edit / project item-add ghi lời gọi
cat > "$TMP/path/gh" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view")  jq -c --rawfile b "$ST/body" '. + {body: $b}' "$ST/pr" ;;
  "pr edit")  f=""; while [ $# -gt 0 ]; do [ "$1" = --body-file ] && f="$2"; shift; done
              echo "pr-edit" >> "$ST/writes"; cp "$f" "$ST/body" ;;
  "project item-add") echo "item-add $*" >> "$ST/writes"; echo 0 > "$ST/status_rc"; : > "$ST/status" ;;
  *) echo "gh $*" >> "$ST/writes" ;;
esac
SH
chmod +x "$TMP/bin/"* "$TMP/path/gh"
export ST="$TMP/st" PATH="$TMP/path:$PATH"

setpr() {   # setpr <branch> <draft> <body> <status> [status_rc]
  printf '{"number":42,"isDraft":%s,"headRefName":"%s","title":"t","state":"OPEN","url":"https://github.com/acme/widgets/pull/42"}' "$2" "$1" > "$ST/pr"
  printf '%s' "$3" > "$ST/body"; printf '%s\n' "$4" > "$ST/status"; echo "${5:-0}" > "$ST/status_rc"; : > "$ST/writes"
}
route() { ( cd "$TMP" && bash "$TMP/bin/super-board-route-pr.sh" 42 "$@" >"$TMP/out" 2>"$TMP/err" ); echo $?; }

# (a)
setpr issue-12-x false "Fix stuff" Building
rc=$(route --config "$TMP/cfg.json")
[ "$rc" = 0 ] && grep -qx "move 12 QA" "$ST/writes" && grep -q "Closes #12" "$ST/body" \
  && ok "(a) issue-12-x Building: card moved to QA, Closes #12 added" || fail "(a) rc=$rc writes=$(tr '\n' ' ' <"$ST/writes") body=$(cat "$ST/body") err=$(head -c 300 "$TMP/err")"
# (f) lần 2 không ghi
: > "$ST/writes"; rc=$(route --config "$TMP/cfg.json")
[ "$rc" = 0 ] && [ ! -s "$ST/writes" ] && ok "(f) second run writes nothing" || fail "(f) rc=$rc writes=$(tr '\n' ' ' <"$ST/writes")"
# (b)
setpr chore/x false "Body. Closes #5" Review
rc=$(route --config "$TMP/cfg.json")
[ "$rc" = 0 ] && [ ! -s "$ST/writes" ] && ok "(b) Closes #5 + Review: kept, nothing written" || fail "(b) rc=$rc writes=$(tr '\n' ' ' <"$ST/writes") err=$(head -c 300 "$TMP/err")"
# (c)
setpr issue-12-x true "x" Building
rc=$(route --config "$TMP/cfg.json")
[ "$rc" = 0 ] && [ ! -s "$ST/writes" ] && ok "(c) draft PR: nothing written" || fail "(c) rc=$rc writes=$(tr '\n' ' ' <"$ST/writes")"
# (d) không --config, thư mục không có .claude/super-board/configs
setpr issue-12-x false "x" Building
rc=$(route)
[ "$rc" = 0 ] && [ ! -s "$ST/writes" ] && ok "(d) no super-board config: exit 0, no gh write" || fail "(d) rc=$rc writes=$(tr '\n' ' ' <"$ST/writes")"
# (e) không trên board → item-add bằng URL issue rồi QA
setpr issue-9-y false "Closes #9" "" 3
rc=$(route --config "$TMP/cfg.json")
[ "$rc" = 0 ] && grep -q "item-add.*project item-add 7 --owner acme --url https://github.com/acme/widgets/issues/9" "$ST/writes" && grep -qx "move 9 QA" "$ST/writes" \
  && ok "(e) card not on board: item-add with the issue URL, then QA" || fail "(e) rc=$rc writes=$(tr '\n' ' ' <"$ST/writes") err=$(head -c 300 "$TMP/err")"
setpr issue-9-y false "Closes #9" "" 69
rc=$(route --config "$TMP/cfg.json")
[ "$rc" = 69 ] && ! grep -q "^move" "$ST/writes" && [ -s "$TMP/err" ] && ok "(e) status rc 69: exit 69, no move" || fail "(e69) rc=$rc writes=$(tr '\n' ' ' <"$ST/writes")"
# không tìm ra số thẻ → exit 4 kèm hướng dẫn
setpr chore/x false "no ref" Building
rc=$(route --config "$TMP/cfg.json")
[ "$rc" = 4 ] && [ ! -s "$ST/writes" ] && grep -q "Closes #" "$TMP/err" && ok "no card number: exit 4 with guidance" || fail "no-N rc=$rc"

# (g) hook PreToolUse
mkdir -p "$TMP/board/.claude/super-board/configs" "$TMP/plain"
cp "$TMP/cfg.json" "$TMP/board/.claude/super-board/configs/w.json"
for d in board plain; do git -C "$TMP/$d" init -q -b fix/x; done
pre() {   # pre <dir> <command> → rc; stderr ở $TMP/pre.err
  jq -nc --arg c "$2" --arg d "$TMP/$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
    | ( cd "$TMP/$1" && CLAUDE_PROJECT_DIR="$TMP/$1" python3 "$HOOK" >"$TMP/pre.out" 2>"$TMP/pre.err" ); echo $?
}
rc=$(pre board 'gh pr create --base main --title t --body b')
[ "$rc" = 2 ] && grep -q "issue-<N>" "$TMP/pre.err" && grep -q "gh issue create" "$TMP/pre.err" && grep -q "DEVKIT_ALLOW_BRANCH=1" "$TMP/pre.err" \
  && ok "(g) gh pr create from fix/x in a board repo: exit 2 with the fix steps" || fail "(g) fix/x rc=$rc $(head -c 300 "$TMP/pre.err")"
rc=$(pre board 'cd . && GH_PAGER= gh -R acme/widgets pr new -t t -b b')
[ "$rc" = 2 ] && ok "(g) gh -R … pr new after cd/VAR=: blocked too" || fail "(g) pr new rc=$rc"
rc=$(pre board 'gh pr create --draft --title t'); [ "$rc" = 0 ] && ok "(g) --draft: allowed" || fail "(g) --draft rc=$rc"
rc=$(pre board 'gh pr create -d -t t'); [ "$rc" = 0 ] && ok "(g) -d: allowed" || fail "(g) -d rc=$rc"
rc=$(pre board 'gh pr create --title -d -b x'); [ "$rc" = 2 ] && ok "(g) -d as the --title value is not draft" || fail "(g) title -d rc=$rc"
rc=$(pre board 'gh pr create --head issue-3-x --title t'); [ "$rc" = 0 ] && ok "(g) --head issue-3-x: allowed" || fail "(g) --head rc=$rc"
rc=$(pre board 'gh pr create -H acme:issue-3-x --title t'); [ "$rc" = 0 ] && ok "(g) -H owner:issue-3-x: allowed" || fail "(g) -H rc=$rc"
rc=$(pre board 'git commit -m "gh pr create from fix/x" && echo "gh pr create"'); [ "$rc" = 0 ] && ok "(g) the words inside arguments do not trigger" || fail "(g) args rc=$rc"
rc=$(pre board 'gh pr view 3'); [ "$rc" = 0 ] && ok "(g) other gh pr verbs: allowed" || fail "(g) view rc=$rc"
rc=$(pre plain 'gh pr create --title t'); [ "$rc" = 0 ] && ok "(g) repo without a board: allowed" || fail "(g) plain rc=$rc"
git -C "$TMP/board" checkout -q -b issue-3-x
rc=$(pre board 'gh pr create --title t'); [ "$rc" = 0 ] && ok "(g) on branch issue-3-x: allowed" || fail "(g) issue-3-x rc=$rc $(head -c 200 "$TMP/pre.err")"

# (h) hook PostToolUse: route-pr của repo là stub ghi lời gọi
mkdir -p "$TMP/board/.claude/bin"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/route-calls"\necho "PR #$1 → QA (card #3)"\nexit "${STUB_ROUTE_RC:-0}"\n' "$TMP" > "$TMP/board/.claude/bin/super-board-route-pr.sh"
chmod +x "$TMP/board/.claude/bin/super-board-route-pr.sh"
post() {   # post <command> <stdout>
  jq -nc --arg c "$1" --arg o "$2" --arg d "$TMP/board" '{hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:$c},tool_response:{stdout:$o,stderr:"",interrupted:false},cwd:$d}' \
    | ( cd "$TMP/board" && CLAUDE_PROJECT_DIR="$TMP/board" python3 "$HOOK" >"$TMP/post.out" 2>"$TMP/post.err" ); echo $?
}
rm -f "$TMP/route-calls"
rc=$(post 'gh pr create --title t --body b' 'https://github.com/acme/widgets/pull/57')
[ "$rc" = 0 ] && [ "$(cat "$TMP/route-calls" 2>/dev/null)" = 57 ] && jq -e '.hookSpecificOutput.additionalContext | test("#57")' "$TMP/post.out" >/dev/null \
  && ok "(h) PR URL in the output: route-pr called with 57, additionalContext set" || fail "(h) rc=$rc calls=$(cat "$TMP/route-calls" 2>/dev/null) out=$(head -c 300 "$TMP/post.out")"
rm -f "$TMP/route-calls"
rc=$(post 'gh pr view 57' 'https://github.com/acme/widgets/pull/57')
[ "$rc" = 0 ] && [ ! -e "$TMP/route-calls" ] && ok "(h) other commands: route-pr not called" || fail "(h) other rc=$rc"
rc=$(STUB_ROUTE_RC=69 post 'gh pr create --title t' 'https://github.com/acme/widgets/pull/58')
[ "$rc" = 0 ] && jq -e '.hookSpecificOutput.additionalContext | test("69")' "$TMP/post.out" >/dev/null \
  && ok "(h) route-pr fails: exit 0, the error in additionalContext" || fail "(h) fail rc=$rc out=$(head -c 300 "$TMP/post.out")"

# (i) wave-plan: closingIssuesReferences của PR đã vào hàng
cat > "$TMP/items.json" <<'J'
{"items":[
 {"id":"I5","status":"Review","labels":["feature"],"content":{"type":"Issue","number":5,"title":"queued by ref","assignees":[]}},
 {"id":"I6","status":"Review","labels":["feature"],"content":{"type":"Issue","number":6,"title":"not queued","assignees":[]}}]}
J
echo '{}' > "$TMP/deps.json"
echo '[{"headRefName":"chore/x","closingIssuesReferences":[{"number":5}]}]' > "$TMP/queued.json"
printf '{"project":{"owner":"x","number":1},"repo":{"path":".","remote":"https://github.com/x/y"},"worker_backend":"workflow","verify_commands":["true"],"merge_queue":{"enabled":true}}' > "$TMP/wcfg.json"
got=$( cd "$ROOT" && SB_QUEUE_SCHEDULE_AUTOINSTALL=0 SB_GITHUB_HALT_FILE="$TMP/halt.json" bash "$PLAN" --config "$TMP/wcfg.json" \
  --items "$TMP/items.json" --deps "$TMP/deps.json" --queued "$TMP/queued.json" 2>"$TMP/werr" | jq -c '[.cards[].number] | sort' )
[ "$got" = "[6]" ] && ok "(i) queued PR on chore/x closing #5: card #5 is not planned" || fail "(i) got=$got $(head -c 200 "$TMP/werr")"

[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }
