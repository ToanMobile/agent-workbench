#!/usr/bin/env bash
# docs/workflow-improvements.md I.3 P6 (commit closure at EDIT time): an edit that lands in an UNTRACKED file cannot be committed alone
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
  : > "$TMP/py.log"
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

# 10. the ledger stays inside .claude/audit-gate (gitignored there), never in the tree being judged
[ -z "$(git -C "$R" status --porcelain --untracked-files=all | grep -v 'src/\|sub dir/\|build.log' )" ] \
  && ok "the hook left nothing else in the repo's tree" || fail "stray files in the tree: $(git -C "$R" status --porcelain --untracked-files=all)"

[ "$FAILS" -eq 0 ] && echo "✅ test_untracked_edit_warning: all passed" || { echo "❌ test_untracked_edit_warning: $FAILS failed"; exit 1; }
