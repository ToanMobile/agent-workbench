#!/usr/bin/env bash
# Commit closure at EDIT time: an edit that lands in an UNTRACKED file cannot be committed alone
# (HEAD does not hold the file), and nothing said so until a reviewer noticed (OfficeReader 07/10: the edit lived in an untracked file another
# session's refactor made). hooks/churn_guard.sh (PostToolUse Edit|Write|NotebookEdit, no new hook file: the hook count is documented and
# three registries must agree) now warns once per file per session, never blocks (the edit has happened), in bash + git only (no python).
#   1. a tracked file: silent;  2. an untracked file: rc 2 + the fix;  3. once per file per session;  4. an ignored file and a file outside
#   any repo: silent;  5. a file THIS session created with Write is its own: silent (Write overwriting an existing file: warns);
#   6. a path with glob characters is judged literally;  7. the churn warning still fires beside it;  8. python is not started;  9. off switch.
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${UE_HOOK:-$DEVKIT_DIR/hooks/churn_guard.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REAL_PY="$(command -v python3)" || { echo "skip: python3 missing"; exit 0; }

mkdir -p "$TMP/bin" "$TMP/repo" "$TMP/outside"
printf '#!/bin/sh\necho start >> "%s/py.log"\nexec "%s" "$@"\n' "$TMP" "$REAL_PY" > "$TMP/bin/python3"
chmod +x "$TMP/bin/python3"
REAL_GIT="$(command -v git)"   # a git shim in the hook's PATH counts the git processes it starts ($TMP/git.log, one line each) and records the
                               # LC_ALL each one was started with ($TMP/lcall.log): the hook must hand its children the locale it was given
printf '#!/bin/sh\necho "$*" >> "%s/git.log"\necho "${LC_ALL-<unset>}" >> "%s/lcall.log"\nexec "%s" "$@"\n' "$TMP" "$TMP" "$REAL_GIT" > "$TMP/bin/git"
chmod +x "$TMP/bin/git"
R="$TMP/repo"
git -C "$R" init -q . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
mkdir -p "$R/src" "$R/sub dir"
printf 'a\n' > "$R/src/tracked.kt"; printf 'a\n' > "$R/src/n[1].kt"; printf '*.log\n' > "$R/.gitignore"
printf 'a\n' > "$R/sub dir/new2.kt"   # TRACKED: the glob new[2].kt matches it, so a non-literal pathspec would call the untracked new[2].kt tracked
git -C "$R" add -A && git -C "$R" commit -q -m init
printf 'b\n' > "$R/src/untracked.kt"          # untracked, not ignored
printf 'b\n' > "$R/src/n1.kt"                 # untracked sibling the glob n[1].kt would match
printf 'b\n' > "$R/sub dir/new[2].kt"         # untracked, space and glob characters in the name
printf 'b\n' > "$R/build.log"                 # ignored
printf 'b\n' > "$TMP/outside/x.kt"            # no repo
: > "$TMP/t.jsonl"

# run <session> <tool> <file_path> <tool_response json> [VAR=val…]: rc in $RC, "1" in $PY when python started, stderr in $TMP/err
run() {
  local sid="$1" tool="$2" fp="$3" resp="$4" key=file_path; shift 4
  [ "$tool" = NotebookEdit ] && key=notebook_path
  : > "$TMP/py.log"; : > "$TMP/git.log"; : > "$TMP/lcall.log"
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"%s":"%s","old_string":"a","new_string":"b"},"tool_response":%s}' \
    "$sid" "${UE_TRANSCRIPT:-$TMP/t.jsonl}" "$R" "$tool" "$key" "$fp" "$resp" > "$TMP/in.json"
  ( cd "$R" && env PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$R" "$@" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  RC=$?
  PY=$([ -s "$TMP/py.log" ] && echo 1 || echo 0)
}
warned() { grep -q "COMMIT-CLOSURE" "$TMP/err"; }

# 1. tracked: silent
run s1 Edit "$R/src/tracked.kt" '{"filePath":"x"}'
[ "$RC" = 0 ] && ! warned && ok "editing a tracked file: rc 0, no warning" || fail "tracked file: rc=$RC err=$(cat "$TMP/err")"

# 2. untracked: warn, name the cause and the fix, never block (rc 2 is PostToolUse's 'tell the agent', the edit already happened)
run s1 Edit "$R/src/untracked.kt" '{"filePath":"x"}'
[ "$RC" = 2 ] && warned && ok "editing an untracked file: rc 2 + COMMIT-CLOSURE warning" || fail "untracked file: rc=$RC (want 2) err=$(cat "$TMP/err")"
grep -q "untracked.kt" "$TMP/err" && grep -q "HEAD" "$TMP/err" && grep -q "git add" "$TMP/err" \
  && ok "  … the warning names the file, says HEAD does not hold it, and says git add" || fail "warning text lacks the file / HEAD / git add: $(cat "$TMP/err")"
grep -qi "git archive HEAD" "$TMP/err" && ok "  … and names the full version (git archive HEAD + overlay compile)" || fail "warning does not name the git archive HEAD full version"

# 3. once per file per session; another session warns again; another file warns
run s1 Edit "$R/src/untracked.kt" '{"filePath":"x"}'
[ "$RC" = 0 ] && ! warned && ok "the same file again, same session: silent (warned once)" || fail "second edit warned again: rc=$RC"
run s2 Edit "$R/src/untracked.kt" '{"filePath":"x"}'
[ "$RC" = 2 ] && warned && ok "the same file in another session: warns" || fail "another session: rc=$RC (want 2)"
run s1 NotebookEdit "$R/src/n1.kt" '{"filePath":"x"}'
[ "$RC" = 2 ] && warned && ok "a NotebookEdit (notebook_path) of another untracked file: warns" || fail "notebook_path: rc=$RC (want 2)"

# 4. ignored and outside any repo: silent
run s1 Edit "$R/build.log" '{"filePath":"x"}'
[ "$RC" = 0 ] && ! warned && ok "an ignored file: silent" || fail "ignored file: rc=$RC err=$(cat "$TMP/err")"
run s1 Edit "$TMP/outside/x.kt" '{"filePath":"x"}'
[ "$RC" = 0 ] && ! warned && ok "a file outside any git repo: silent" || fail "outside file: rc=$RC err=$(cat "$TMP/err")"
run s1 Edit "$TMP/outside/missing/dir/x.kt" '{"filePath":"x"}'
[ "$RC" = 0 ] && ok "a path whose directory does not exist: silent, no crash" || fail "missing dir: rc=$RC"

# 5. a file this session created is its own; Write over an existing untracked file is not
printf 'new\n' > "$R/src/mine.kt"
run s3 Write "$R/src/mine.kt" '{"type":"create","filePath":"x"}'
[ "$RC" = 0 ] && ! warned && ok "Write that CREATED the untracked file: silent" || fail "Write create: rc=$RC err=$(cat "$TMP/err")"
run s3 Edit "$R/src/mine.kt" '{"filePath":"x"}'
[ "$RC" = 0 ] && ! warned && ok "  … and the later Edits of it in that session: silent" || fail "Edit of own file: rc=$RC err=$(cat "$TMP/err")"
run s4 Write "$R/src/untracked.kt" '{"type":"update","filePath":"x"}'
[ "$RC" = 2 ] && warned && ok "Write that OVERWROTE an existing untracked file: warns" || fail "Write update: rc=$RC (want 2)"
run s5 Write "$R/src/n1.kt" '{"filePath":"x"}'
[ "$RC" = 0 ] && ! warned && ok "Write with no type in the response: treated as own (silent, fails safe)" || fail "Write without type: rc=$RC"

# 6. glob characters are literal: the tracked n[1].kt is NOT judged by its untracked sibling n1.kt; the untracked "new[2].kt" is found
run s6 Edit "$R/src/n[1].kt" '{"filePath":"x"}'
[ "$RC" = 0 ] && ! warned && ok "tracked n[1].kt next to an untracked n1.kt: silent (literal pathspec)" || fail "glob name: rc=$RC err=$(cat "$TMP/err")"
run s6 Edit "$R/sub dir/new[2].kt" '{"filePath":"x"}'
[ "$RC" = 2 ] && warned && ok "untracked 'sub dir/new[2].kt' (space + glob characters): warns" || fail "space+glob name: rc=$RC (want 2)"

# 7. churn still fires beside it: a transcript with three landed edits naming the file and no evidence
{ for i in 1 2 3; do printf '{"type":"assistant","message":{"id":"m%s","content":[{"type":"tool_use","id":"t%s","name":"Edit","input":{"file_path":"%s/src/churn.kt","old_string":"a","new_string":"b"}}]}}\n' "$i" "$i" "$R"; done; } > "$TMP/t3.jsonl"
printf 'b\n' > "$R/src/churn.kt"
UE_TRANSCRIPT="$TMP/t3.jsonl" run s7 Edit "$R/src/churn.kt" '{"filePath":"x"}'
[ "$RC" = 2 ] && warned && grep -q "CHURN-GUARD" "$TMP/err" && ok "untracked + third blind edit: both warnings, rc 2" || fail "both warnings: rc=$RC err=$(cat "$TMP/err")"

# 8. bash + git only: python was not started for a warning
printf 'b\n' > "$R/src/nopy.kt"
run s8 Edit "$R/src/nopy.kt" '{"filePath":"x"}'
[ "$RC" = 2 ] && [ "$PY" = 0 ] && ok "the warning path did not start python (fast path kept)" || fail "python=$PY rc=$RC (want 0 starts, rc 2)"

# 9. off switches
printf 'b\n' > "$R/src/off.kt"
run s9 Edit "$R/src/off.kt" '{"filePath":"x"}' UNTRACKED_EDIT_WARN=0
[ "$RC" = 0 ] && ! warned && ok "UNTRACKED_EDIT_WARN=0: silent" || fail "off switch: rc=$RC"
run s9 Edit "$R/src/off.kt" '{"filePath":"x"}' CHURN_GUARD=0
[ "$RC" = 0 ] && ! warned && ok "CHURN_GUARD=0 (the hook's own switch): silent" || fail "CHURN_GUARD=0: rc=$RC"

# ── review of lane A11 (this hook runs on EVERY Edit/Write of every repo: fast, fail-open, never blocking) ───────────────────────────
# a. its git calls run no command taken from the repo they look at: `git ls-files` starts the repo's core.fsmonitor program (verified with
#    git 2.55), and the edited path may lie in ANY repo. The fixture's fsmonitor writes a marker; the untracked file is still found.
FS="$TMP/fsrepo"; mkdir -p "$FS"
git -C "$FS" init -q . && git -C "$FS" config user.email t@t && git -C "$FS" config user.name t && git -C "$FS" config commit.gpgsign false
printf 'a\n' > "$FS/t.kt"; git -C "$FS" add -A && git -C "$FS" commit -q -m init; printf 'b\n' > "$FS/new.kt"
printf '#!/bin/sh\necho "ran $*" >> "%s/fsm.marker"\nprintf "\\0"\n' "$TMP" > "$TMP/fsm.sh"; chmod +x "$TMP/fsm.sh"
git -C "$FS" config core.fsmonitor "$TMP/fsm.sh"
rm -f "$TMP/fsm.marker"
run s11 Edit "$FS/new.kt" '{"filePath":"x"}'
[ "$RC" = 2 ] && warned && [ ! -s "$TMP/fsm.marker" ] && ok "a repo's core.fsmonitor program is not started by the hook's git calls (and its untracked file is still found)" \
  || fail "fsmonitor: rc=$RC warned=$(warned && echo yes || echo no) marker=$(cat "$TMP/fsm.marker" 2>/dev/null | head -2)"
# e. a GIT_DIR leaked into the hook's environment must not turn every tracked edit into a warning: the repo of the edited path is judged
run s11 Edit "$R/src/tracked.kt" '{"filePath":"x"}' GIT_DIR="$FS/.git"
[ "$RC" = 0 ] && ! warned && ok "a leaked GIT_DIR does not make a tracked file look untracked" || fail "GIT_DIR leak: rc=$RC err=$(cat "$TMP/err")"

# b. a file already in this session's ledger costs no git process at all (the ledger is read BEFORE the git calls)
printf 'b\n' > "$R/src/ledger1.kt"
run s12 Edit "$R/src/ledger1.kt" '{"filePath":"x"}'
G1="$(grep -c . "$TMP/git.log")"
[ "$RC" = 2 ] && [ "$G1" -ge 1 ] || fail "ledger fixture: first edit rc=$RC git calls=$G1"
run s12 Edit "$R/src/ledger1.kt" '{"filePath":"x"}'
[ "$RC" = 0 ] && ! warned && [ ! -s "$TMP/git.log" ] && ok "re-editing a file the ledger already holds: silent and 0 git processes (first edit: $G1)" \
  || fail "ledger first: rc=$RC git calls=$(grep -c . "$TMP/git.log") ($(head -2 "$TMP/git.log" | tr '\n' ';'))"

# c. the P6 regexes read the first 8 KiB of the payload only (session_id, tool_name and tool_input.file_path all precede any content), so a
#    20 MB Write costs no more than a small one; a file_path past that prefix is not judged (fail-open). Control: the same payload with a
#    short pad IS judged.
printf 'b\n' > "$R/src/far.kt"
rawrun() {  # rawrun <pad bytes>: stderr in $TMP/err, rc in $RC
  local pad; pad="$(head -c "$1" /dev/zero | tr '\0' x)"
  printf '{"session_id":"s13","transcript_path":"%s","cwd":"%s","pad":"%s","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s/src/far.kt","old_string":"a","new_string":"b"},"tool_response":{"filePath":"x"}}' \
    "$TMP/t.jsonl" "$R" "$pad" "$R" > "$TMP/raw.json"
  ( cd "$R" && env PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$R" bash "$HOOK" < "$TMP/raw.json" > /dev/null 2> "$TMP/err" ); RC=$?
}
rawrun 100;  [ "$RC" = 2 ] && warned && ok "control: file_path within the first 8 KiB of the payload is judged" || fail "control for the prefix cap: rc=$RC"
rm -f "$R/.claude/audit-gate/untracked_edit.s13"   # the control's ledger line would hide the next run
rawrun 9000; [ "$RC" = 0 ] && ! warned && ok "a file_path past the first 8 KiB is not judged: the scan is bounded to a prefix" || fail "prefix cap: rc=$RC (a 9 KB pad before tool_input must hide it)"

# c2. content before file_path inside tool_input (a tool whose arguments come in another order): the prefix holds "tool_input" but no path, so the
#     hook makes ONE full match (it used to judge nothing and the old hook warned). The decoy above (the pad BEFORE "tool_input") stays unjudged.
printf 'b\n' > "$R/src/late.kt"
LATE="$(head -c 20000 /dev/zero | tr '\0' x)"
printf '{"session_id":"s17","transcript_path":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"old_string":"%s","file_path":"%s/src/late.kt","new_string":"b"},"tool_response":{"filePath":"x"}}' \
  "$TMP/t.jsonl" "$R" "$LATE" "$R" > "$TMP/late.json"
( cd "$R" && env PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$R" bash "$HOOK" < "$TMP/late.json" > /dev/null 2> "$TMP/err" ); RC=$?
[ "$RC" = 2 ] && grep -q 'late.kt' "$TMP/err" && ok "a file_path after 20 KB of tool_input content is still judged (one full match when the prefix holds tool_input but no path)" || fail "late file_path: rc=$RC (want 2) $(head -1 "$TMP/err")"

# the slice and the update match run under LC_ALL=C (ASCII patterns: no UTF-8 decode of a big payload); a non-ASCII path must still be judged
# whole, the warning must still name it, and the locale the hook was started with must be back for everything after (a UTF-8 shell here)
if locale -a 2>/dev/null | grep -qiE '^en_US\.UTF-?8$'; then
  printf 'b\n' > "$R/src/Vùng.kt"
  run s16 Edit "$R/src/Vùng.kt" '{"filePath":"x"}' LC_ALL=en_US.UTF-8
  [ "$RC" = 2 ] && grep -q 'Vùng.kt' "$TMP/err" && ok "a non-ASCII file name is judged and named whole (UTF-8 locale, slice under LC_ALL=C)" || fail "non-ASCII path: rc=$RC err=$(head -1 "$TMP/err")"
  # the children the hook starts afterwards see the ORIGINAL locale, not the C the slice ran under (a restore that does nothing leaves C behind)
  [ -s "$TMP/lcall.log" ] && [ "$(sort -u "$TMP/lcall.log")" = "en_US.UTF-8" ] && ok "the locale is restored: git ran under LC_ALL=en_US.UTF-8, as the hook was started" || fail "LC_ALL seen by git after the slice: $(sort -u "$TMP/lcall.log" | tr '\n' ' ') (want en_US.UTF-8)"
  printf 'b\n' > "$R/src/Vùng2.kt"
  run s16 Write "$R/src/Vùng2.kt" '{"type":"update","filePath":"x"}' LC_ALL=en_US.UTF-8
  [ "$RC" = 2 ] && grep -q 'Vùng2.kt' "$TMP/err" && ok "a Write 'update' over an untracked non-ASCII file still warns (the update match under LC_ALL=C)" || fail "non-ASCII Write update: rc=$RC"
  [ "$(sort -u "$TMP/lcall.log")" = "en_US.UTF-8" ] && ok "  … and the locale is back after the update match too" || fail "LC_ALL after the update match: $(sort -u "$TMP/lcall.log" | tr '\n' ' ')"
else
  echo "- skipped: the en_US.UTF-8 locale is not installed, so the locale-restore and non-ASCII cases cannot be exercised here"
fi
# a hook started WITHOUT LC_ALL (or with whatever this shell has) leaves its children exactly that
printf 'b\n' > "$R/src/lcdefault.kt"
run s19 Edit "$R/src/lcdefault.kt" '{"filePath":"x"}'
[ -s "$TMP/lcall.log" ] && [ "$(sort -u "$TMP/lcall.log")" = "${LC_ALL-<unset>}" ] && ok "LC_ALL as this shell has it (${LC_ALL-<unset>}) reaches the hook's children unchanged" || fail "default LC_ALL seen by git: $(sort -u "$TMP/lcall.log" | tr '\n' ' ') (want ${LC_ALL-<unset>})"

# d. the check looks at the git INDEX (ls-files), not at HEAD: say so (a file another session has staged passes silently although HEAD lacks it)
printf 'b\n' > "$R/src/wording.kt"
run s15 Edit "$R/src/wording.kt" '{"filePath":"x"}'
grep -q "index" "$TMP/err" && ok "the warning says it is the git index that lacks the file" || fail "warning text does not mention the index: $(cat "$TMP/err")"

# e. a ledger path that is a directory must not make the warning appear on every edit (fail-open: silent, and logged)
printf 'b\n' > "$R/src/dirledger.kt"; mkdir -p "$R/.claude/audit-gate/untracked_edit.s14"
run s14 Edit "$R/src/dirledger.kt" '{"filePath":"x"}'; RC1=$RC
run s14 Edit "$R/src/dirledger.kt" '{"filePath":"x"}'
[ "$RC1" = 0 ] && [ "$RC" = 0 ] && ! warned && ok "a directory in place of the ledger file: no warning on any edit (fail-open)" || fail "ledger is a directory: rc=$RC1/$RC"
rmdir "$R/.claude/audit-gate/untracked_edit.s14"

# f. an unwritable ledger: the hook's own redirection errors must not reach Claude (for a failed `>> file` the shell prints "Permission denied"
#    before a 2>/dev/null written after it takes effect). The warning itself still comes (the file is judged untracked; nothing could record it).
if [ "$(id -u)" != 0 ]; then
  printf 'b\n' > "$R/src/rolock.kt"; printf '%s\n' "$R/src/other.kt" > "$R/.claude/audit-gate/untracked_edit.s20"; chmod 444 "$R/.claude/audit-gate/untracked_edit.s20"
  run s20 Edit "$R/src/rolock.kt" '{"filePath":"x"}'
  [ "$RC" = 2 ] && warned && ! grep -qi 'permission denied' "$TMP/err" && ok "an unwritable ledger: the warning comes and no shell error text reaches the agent" || fail "unwritable ledger: rc=$RC err=$(grep -i 'denied' "$TMP/err" | head -1)"
  chmod 644 "$R/.claude/audit-gate/untracked_edit.s20"
else
  echo "- skipped: running as root, a read-only file does not refuse the write"
fi

# 10. the ledger stays inside .claude/audit-gate (gitignored there), never in the tree being judged
[ -z "$(git -C "$R" status --porcelain --untracked-files=all | grep -v 'src/\|sub dir/\|build.log' )" ] \
  && ok "the hook left nothing else in the repo's tree" || fail "stray files in the tree: $(git -C "$R" status --porcelain --untracked-files=all)"

[ "$FAILS" -eq 0 ] && echo "✅ test_untracked_edit_warning: all passed" || { echo "❌ test_untracked_edit_warning: $FAILS failed"; exit 1; }
