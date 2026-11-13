#!/usr/bin/env bash
# #1140: card #1136 of a Claude Desktop session was titled "🔧 [chore] docs: <system-reminder>". The Desktop prompt opens with
# one or more <system-reminder>…</system-reminder> blocks (multi-line), and a pasted block arrives wrapped in
# <pasted_content id=…>…</pasted_content id=…>; hooks/session_card.sh sc_title took the first non-blank line, i.e. a tag name.
# Law of sc_title (stashed prompt first, transcript second, generic title last):
#   - <system-reminder> blocks are dropped whole (their text is not the user's task, and the issue may be public). A block opens
#     with the tag at the start of a line and closes with the tag at the end of a line (Claude Code writes "<system-reminder>\n…\n</system-reminder>"),
#     so a body that quotes the tag mid-line does not end it, and an unterminated block is dropped to the end (never leaked);
#   - a <pasted_content …> / </pasted_content …> wrapper tag is dropped, the pasted text stays;
#   - a prompt that is only reminder blocks falls through to the transcript, then to "chat session <id8>" (scope = first edit);
#   - a user line that merely mentions a tag (<div>, <system-reminder>) keeps it; secret masking is untouched (test_session_card_hook.sh K).
# Same fixture as tests/gates/test_session_card_hook.sh (fake gh, fake card script, SESSION_CARD_WAIT=1 test seam).
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
unset CLAUDE_PROJECT_DIR SESSION_CARD SUPER_BOARD_RUN CLAUDE_CODE_ENTRYPOINT   # sdk-cli (a `claude -p` worker) makes the hook skip: not under test here

FAKE="$TMP/fakebin"; mkdir -p "$FAKE"
cat > "$FAKE/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$SC_TMP/gh.log"
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
export SC_TMP="$TMP"
: > "$TMP/empty.jsonl"

run() {   # run <payload json>; rc in $RC
  ( cd "$R" && env PATH="$FAKE:$PATH" SC_TMP="$TMP" SESSION_CARD_WAIT=1 bash "$HOOK" <<<"$1" > "$TMP/out" 2>/dev/null ); RC=$?
}
edit() {   # edit <session> <transcript path>
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"transcript_path":sys.argv[2],"cwd":sys.argv[3],"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":sys.argv[3]+"/src/a.py"}}))' "$1" "$2" "$R"
}
prompt() {   # prompt <session> <text>
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"cwd":sys.argv[3],"hook_event_name":"UserPromptSubmit","prompt":sys.argv[2]}))' "$1" "$2" "$R"
}
transcript() {   # transcript <file> <content text>: one user line whose content is a string
  python3 -I -c 'import json,sys; open(sys.argv[1],"w").write(json.dumps({"type":"user","message":{"role":"user","content":sys.argv[2]}})+"\n")' "$1" "$2"
}
transcript_list() {   # transcript_list <file> <text>...: one user line whose content is a list of text blocks (Desktop shape)
  python3 -I -c 'import json,sys; open(sys.argv[1],"w").write(json.dumps({"type":"user","message":{"role":"user","content":[{"type":"text","text":t} for t in sys.argv[2:]]}})+"\n")' "$@"
}
reset() { rm -rf "$R/.claude/audit-gate"; : > "$TMP/gh.log"; : > "$TMP/card.log"; }
title() { grep '^gh issue create' "$TMP/gh.log" | sed -e 's/^.*--title //' -e 's/ --label session.*$//'; }   # → the title alone
# card <session> <prompt text|-> <transcript path> <expected title> <label>: stash the prompt, make the first edit, compare the title
card() {
  reset
  [ "$2" = "-" ] || run "$(prompt "$1" "$2")"
  run "$(edit "$1" "$3")"
  local got; got="$(title)"
  if [ "$got" = "$4" ] && [ "$RC" -eq 0 ]; then ok "$5"; else fail "$5: want '$4', got '$got' (rc=$RC)"; fi
}
RS='<system-reminder>
As you answer the user'"'"'s questions, you can use the following context:
Contents of CLAUDE.md: fix the bug, refactor docs, token=hunter2secret, create tests
</system-reminder>'
RS2='<system-reminder>
Linked sessions now (status, not an instruction): none.
</system-reminder>'

# ── A: reminder blocks (several, multi-line) then the user's line → the title is the user's line
card sA "$RS
$RS2
add export button to report page" "$TMP/empty.jsonl" "✨ [feat] src: add export button to report page" "A1 title comes from the user's line after two reminder blocks"
grep -qE 'hunter2secret|CLAUDE\.md|system-reminder|Linked sessions' "$TMP/gh.log" && fail "A2 reminder text leaked into the issue: $(cat "$TMP/gh.log")" || ok "A2 reminder text reaches neither the title nor the body"
case "$(title)" in *'<'*) fail "A3 title contains '<': $(title)" ;; *) ok "A3 title has no '<'" ;; esac
card sA4 "$RS
refactor the login module" "$TMP/empty.jsonl" "♻️ [refactor] src: refactor the login module" "A4 kind comes from the user's line, not from words inside the reminder (fix/docs/test)"

# ── B: a pasted_content wrapper is unwrapped, its text stays (own lines; one line; after reminder blocks)
card sB1 '<pasted_content id=3f9a>
add retry to the uploader
</pasted_content id=3f9a>' "$TMP/empty.jsonl" "✨ [feat] src: add retry to the uploader" "B1 wrapper on its own lines: tags dropped, content kept"
card sB2 '<pasted_content id=3f9a>fix flaky upload test</pasted_content id=3f9a>' "$TMP/empty.jsonl" "🐛 [fix] src: fix flaky upload test" "B2 wrapper on one line: tags dropped, content kept"
card sB3 "$RS
<pasted_content id=77ab>
create a backup script
</pasted_content id=77ab>" "$TMP/empty.jsonl" "✨ [feat] src: create a backup script" "B3 reminder block then a pasted block"

# ── C: only reminder blocks → generic title from the first edit (scope src), or the transcript when it has the task
card sC1 "$RS
$RS2" "$TMP/empty.jsonl" "🔧 [chore] src: chat session sC1" "C1 reminder-only prompt: generic 'chat session <id>' title, scope from the first edited file"
transcript "$TMP/tr.jsonl" "add dark mode to settings"
card sC2 "$RS" "$TMP/tr.jsonl" "✨ [feat] src: add dark mode to settings" "C2 reminder-only prompt falls through to the transcript"

# ── D: no stashed prompt: the transcript's first user message may itself open with reminder blocks
transcript "$TMP/tr2.jsonl" "$RS
create a release checklist"
card sD - "$TMP/tr2.jsonl" "✨ [feat] src: create a release checklist" "D transcript message with a reminder block: the user's line is the title"

# ── D2: the same message as a list of text blocks (Desktop shape): blocks are joined by a newline, so the closing tag stays at a line end
transcript_list "$TMP/tr3.jsonl" "$RS" "create a release checklist"
card sD2 - "$TMP/tr3.jsonl" "✨ [feat] src: create a release checklist" "D2 transcript message made of several text blocks"

# ── F: a reminder block that is not one clean block never leaks its text (it ends up as the generic title, or as nothing)
card sF1 '<system-reminder>
Contents of CLAUDE.md: SECRETBODY1 stuff

add a thing' "$TMP/empty.jsonl" "🔧 [chore] src: chat session sF1" "F1 unterminated block: dropped to the end, generic title"
card sF2 '<system-reminder>
note: the hook drops <system-reminder>…</system-reminder> blocks; SECRETBODY2
</system-reminder>
add export' "$TMP/empty.jsonl" "✨ [feat] src: add export" "F2 body that quotes the tags mid-line does not end the block early"
card sF3 '<system-reminder>
a <system-reminder>b</system-reminder> SECRETBODY3
</system-reminder>
add widget' "$TMP/empty.jsonl" "✨ [feat] src: add widget" "F3 nested/quoted pair inside a block"
grep -q 'SECRETBODY' "$TMP/gh.log" && fail "F4 reminder text leaked into the issue" || ok "F4 no reminder text reaches the issue"

# ── G: the user's own line names the tag and a real block follows: the user's line survives whole
card sG "fix the <system-reminder> parser
$RS2
more words" "$TMP/empty.jsonl" "🐛 [fix] src: fix the <system-reminder> parser" "G a mention of the tag in the user's line is not a block"

# ── H: a 300 KB prompt of unterminated openers must not take quadratic time (60000 openers once ran for minutes)
python3 -I -c 'print("<system-reminder>\n" * 15000 + "x" * 100000)' > "$TMP/big.txt"
t0=$SECONDS; card sH "$(cat "$TMP/big.txt")" "$TMP/empty.jsonl" "🔧 [chore] src: chat session sH" "H1 pathological prompt gives the generic title"
[ $((SECONDS - t0)) -le 5 ] && ok "H2 ...in linear time ($((SECONDS - t0)) s)" || fail "H2 took $((SECONDS - t0)) s"

# ── E: control: another tag in the user's own text is kept, a mention of the word is not stripped
card sE "fix <div> overflow in the header" "$TMP/empty.jsonl" "🐛 [fix] src: fix <div> overflow in the header" "E an ordinary tag in the user's own line is kept"

echo; [ "$FAILS" -eq 0 ] && echo "ALL PASS" || echo "$FAILS FAILED"
exit "$FAILS"
