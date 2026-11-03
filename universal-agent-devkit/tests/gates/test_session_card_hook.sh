#!/usr/bin/env bash
# 03/11, owner: "mọi task đều phải hiển thị lên board để theo dõi, hiện không thấy, fix dev kit". A task that starts in chat has
# no issue, so Agent Office listed its session as a worker with no card on the board (PR #928 of agent-office).
# Law of hooks/session_card.sh (UserPromptSubmit + PreToolUse Edit|Write):
#   - the first repo edit of a session creates exactly ONE issue (label `session`), adds it to the project and moves it to
#     Building; two Edit hooks of one session racing still make one card;
#   - the title is `<emoji> [type] scope: subject` from the first prompt (stashed at UserPromptSubmit: the transcript of the
#     running turn is not flushed yet), else the transcript, else a generic one; secrets in the prompt are masked;
#   - skipped: a subagent (agent_id), a headless `claude -p` run (CLAUDE_CODE_ENTRYPOINT=sdk-cli), a board lane (cwd on an issue-N-* branch/worktree), a repo with no board config, an edit
#     outside the repo, SESSION_CARD=0;
#   - never blocks (exit 0 always, also on a bad payload or a gh failure); a failed attempt is retried at the next edit, 3 tries.
# SESSION_CARD_WAIT=1 runs the background part in the foreground (test seam).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${SC_HOOK:-$DEVKIT_DIR/hooks/session_card.sh}"
TMP="$(mktemp -d)"; TMP="$(cd -P "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset CLAUDE_PROJECT_DIR SESSION_CARD SUPER_BOARD_RUN

FAKE="$TMP/fakebin"; mkdir -p "$FAKE"
cat > "$FAKE/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$SC_TMP/gh.log"
[ -f "$SC_TMP/gh.fail" ] && exit 1
case "$1 $2" in
  "issue create") echo "https://github.com/o/r/issues/77" ;;
esac
exit 0
SH
chmod +x "$FAKE/gh"

R="$TMP/repo"
mkdir -p "$R/src" "$R/.claude/bin" "$R/.claude/super-board/configs"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
printf '{"project":{"owner":"o","number":1},"repo":{"remote":"https://github.com/o/r"}}\n' > "$R/.claude/super-board/configs/p.json"
printf '#!/usr/bin/env bash\necho "card $*" >> "$SC_TMP/card.log"\n' > "$R/.claude/bin/super-board-card.sh"
printf 'x=1\n' > "$R/src/a.py"
git -C "$R" add -A && git -C "$R" commit -qm init
git -C "$R" worktree add -q -b issue-12-lane "$R/.claude/worktrees/issue-12-build"
printf '{"type":"user","message":{"role":"user","content":"add dark mode to settings"}}\n' > "$TMP/tr.jsonl"
export SC_TMP="$TMP"

# run <cwd> <payload json> [VAR=val…]; stdout in $TMP/out, rc in $RC
run() {
  local cwd="$1" json="$2"; shift 2
  ( cd "$cwd" && env PATH="$FAKE:$PATH" SC_TMP="$TMP" SESSION_CARD_WAIT=1 "$@" bash "$HOOK" <<<"$json" > "$TMP/out" 2>/dev/null ); RC=$?
}
edit() {   # edit <cwd> <session> <file> [extra json]
  python3 -I -c 'import json,sys; d={"session_id":sys.argv[2],"transcript_path":sys.argv[5],"cwd":sys.argv[1],"hook_event_name":"PreToolUse",
"tool_name":"Edit","tool_input":{"file_path":sys.argv[3]}}; d.update(json.loads(sys.argv[4] or "{}")); print(json.dumps(d))' "$1" "$2" "$3" "${4:-}" "$TMP/tr.jsonl"
}
prompt() {   # prompt <cwd> <session> <text>
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":sys.argv[2],"cwd":sys.argv[1],"hook_event_name":"UserPromptSubmit","prompt":sys.argv[3]}))' "$1" "$2" "$3"
}
reset() { rm -f "$TMP/gh.log" "$TMP/card.log" "$TMP/gh.fail"; rm -rf "$R/.claude/audit-gate"; : > "$TMP/gh.log"; : > "$TMP/card.log"; }
creates() { grep -c '^gh issue create' "$TMP/gh.log"; }

# ── A: prompt stashed, first edit → one card: title from the prompt, label session, on the project, moved to Building
reset
run "$R" "$(prompt "$R" sA 'fix lỗi login crash khi mở app')"; rcp=$RC
run "$R" "$(edit "$R" sA "$R/src/a.py")"
t=$(grep '^gh issue create' "$TMP/gh.log")
[ "$RC" -eq 0 ] && [ "$rcp" -eq 0 ] && [ "$(creates)" = 1 ] && ok "A1 first edit creates exactly one issue (exit 0)" || fail "A1 creates=$(creates) rc=$RC/$rcp: $(cat "$TMP/gh.log")"
case "$t" in *"--title 🐛 [fix] src: fix lỗi login crash khi mở app"*) ok "A2 title is '<emoji> [type] scope: subject' from the first prompt" ;; *) fail "A2 title: $t" ;; esac
case "$t" in *"--label session"*) ok "A3 label session" ;; *) fail "A3 label: $t" ;; esac
grep -q '^gh project item-add 1 --owner o --url https://github.com/o/r/issues/77' "$TMP/gh.log" && ok "A4 card added to project #1" || fail "A4 item-add: $(cat "$TMP/gh.log")"
grep -q 'move 77 Building' "$TMP/card.log" && ok "A5 card moved to Building (never Ready: the runner would build it)" || fail "A5 card.log: $(cat "$TMP/card.log")"
grep -q 'Closes #' "$TMP/gh.log" && fail "A6 body must not pre-close anything" || ok "A6 body does not pre-close anything"

# ── B: second edit of the same session → no second card; the card number is told once
run "$R" "$(edit "$R" sA "$R/src/a.py")"; o1="$(cat "$TMP/out")"
run "$R" "$(edit "$R" sA "$R/src/a.py")"; o2="$(cat "$TMP/out")"
[ "$(creates)" = 1 ] && ok "B1 later edits create no card" || fail "B1 creates=$(creates)"
case "$o1" in *'#77'*'Closes #77'*) ok "B2 the next edit tells the session its card (Closes #77)" ;; *) fail "B2 hint: '$o1'" ;; esac
[ -z "$o2" ] && ok "B3 ...once" || fail "B3 repeated hint: '$o2'"

# ── C: parallel Edit hooks of one new session → one card
reset
j="$(edit "$R" sC "$R/src/a.py")"
for i in 1 2 3 4; do ( run "$R" "$j" ) & done; wait
[ "$(creates)" = 1 ] && ok "C parallel first edits make one card" || fail "C creates=$(creates)"

# ── D..H: skipped cases
reset; run "$R" "$(edit "$R" sD "$R/src/a.py" '{"agent_id":"sub1"}')"
[ "$(creates)" = 0 ] && [ "$RC" -eq 0 ] && ok "D subagent (agent_id) gets no card" || fail "D creates=$(creates)"
reset; WT="$R/.claude/worktrees/issue-12-build"; run "$WT" "$(edit "$WT" sE "$WT/src/a.py")"
[ "$(creates)" = 0 ] && [ "$RC" -eq 0 ] && ok "E board lane (issue-12-* worktree) gets no card" || fail "E creates=$(creates)"
reset; mkdir -p "$TMP/nocfg" && git -C "$TMP/nocfg" init -q . ; run "$TMP/nocfg" "$(edit "$TMP/nocfg" sF "$TMP/nocfg/a.py")"
[ "$(creates)" = 0 ] && [ "$RC" -eq 0 ] && ok "F repo with no board config gets no card" || fail "F creates=$(creates)"
reset; run "$R" "$(edit "$R" sG "$TMP/scratch.txt")"
[ "$(creates)" = 0 ] && [ "$RC" -eq 0 ] && ok "G an edit outside the repo gets no card" || fail "G creates=$(creates)"
reset; run "$R" "$(edit "$R" sH "$R/src/a.py")" SESSION_CARD=0
[ "$(creates)" = 0 ] && [ "$RC" -eq 0 ] && ok "H SESSION_CARD=0 gets no card" || fail "H creates=$(creates)"

reset; run "$R" "$(edit "$R" sH2 "$R/src/a.py")" CLAUDE_CODE_ENTRYPOINT=sdk-cli
[ "$(creates)" = 0 ] && [ "$RC" -eq 0 ] && ok "H2 headless claude -p (sdk-cli) gets no card" || fail "H2 creates=$(creates)"

# ── I: gh fails → exit 0, retried at the next edit, gives up after 3 tries
reset; touch "$TMP/gh.fail"
run "$R" "$(edit "$R" sI "$R/src/a.py")"
[ "$RC" -eq 0 ] && [ "$(creates)" = 1 ] && ok "I1 gh failure never blocks the edit" || fail "I1 rc=$RC creates=$(creates)"
run "$R" "$(edit "$R" sI "$R/src/a.py")"; run "$R" "$(edit "$R" sI "$R/src/a.py")"; run "$R" "$(edit "$R" sI "$R/src/a.py")"
[ "$(creates)" = 3 ] && ok "I2 3 tries, then no more" || fail "I2 creates=$(creates)"
reset; touch "$TMP/gh.fail"; run "$R" "$(edit "$R" sI2 "$R/src/a.py")"; rm -f "$TMP/gh.fail"
run "$R" "$(edit "$R" sI2 "$R/src/a.py")"
grep -q 'move 77 Building' "$TMP/card.log" && ok "I3 retry after a failure succeeds" || fail "I3 card.log: $(cat "$TMP/card.log")"

# ── J: no stashed prompt → first user message of the transcript; K: secrets masked
reset; run "$R" "$(edit "$R" sJ "$R/src/a.py")"
case "$(grep '^gh issue create' "$TMP/gh.log")" in *"--title ✨ [feat] src: add dark mode to settings"*) ok "J title falls back to the transcript" ;; *) fail "J: $(cat "$TMP/gh.log")" ;; esac
TOK="ghp""_$(printf 'abcdefghijklmnopqrstuvwxyz0123456789ABCD')"   # built at run time: no token-shaped literal in the file
reset; run "$R" "$(prompt "$R" sK "use $TOK to push")"; run "$R" "$(edit "$R" sK "$R/src/a.py")"
grep -q "$TOK" "$TMP/gh.log" && fail "K token leaked into the issue" || ok "K tokens in the prompt are masked"

# ── L: a bad payload never blocks
reset; run "$R" "not json at all"; [ "$RC" -eq 0 ] && [ "$(creates)" = 0 ] && ok "L bad payload: exit 0" || fail "L rc=$RC"

echo; [ "$FAILS" -eq 0 ] && echo "ALL PASS" || echo "$FAILS FAILED"
exit "$FAILS"
