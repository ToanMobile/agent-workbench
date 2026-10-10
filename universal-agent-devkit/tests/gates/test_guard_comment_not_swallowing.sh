#!/usr/bin/env bash
# hooks/block-dangerous-git.sh and hooks/hardware_safety_gate.sh, a `#` must not hide the commands after it (2026-10-10 fresh-context
# review of the two guards). Both lexed the command with shlex's default commenters='#', so everything after the first `#` token was
# dropped before any segment was judged: `# note` + newline + a destructive command, and `echo a#b; <destructive>` (bash reads a#b as one
# word and runs what follows), passed with rc 0. security_gate.sh and worktree_guard.sh already set commenters="". A real comment is
# still judged as a word of the segment it sits in, so a harmless command with a trailing comment stays allowed.
# Only the hooks run here — never the command.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GIT_HOOK="${GIT_GUARD_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
HW_HOOK="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

P="$TMP/work/proj"          # the project, under mktemp (/tmp on Linux, $TMPDIR on macOS)
mkdir -p "$P/src/old" "$P/build"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'x\n' > "$P/src/a.kt" && git -C "$P" add -A && git -C "$P" commit -qm init

# check <hook> <want rc> <command>
check() {
  local hook="$1" want="$2" c="$3"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$hook" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ]; then ok "rc $rc: $(basename "$hook"): $c"; else fail "rc $rc (want $want): $(basename "$hook"): $c — $(head -c 200 "$TMP/err" | tr '\n' ' ')"; fi
}

# controls: the destructive command alone is refused
check "$GIT_HOOK" 2 'git reset --hard'
check "$HW_HOOK"  2 'rm -rf ~'

# a comment line before the command, a `#` inside a word: the command after it still runs in bash, so it is still judged
check "$GIT_HOOK" 2 $'# cleanup\ngit reset --hard'
check "$GIT_HOOK" 2 'echo a#b; git reset --hard'
check "$HW_HOOK"  2 $'# cleanup\nrm -rf ~'
check "$HW_HOOK"  2 'echo a#b; rm -rf ~'

# where the comment really ends, and what is not a comment (review of the first, naive fix: shlex commenters="" alone)
check "$GIT_HOOK" 2 $'# a comment \\\ngit reset --hard'           # a comment ends at its newline: a trailing backslash does not continue it
check "$GIT_HOOK" 2 $'echo a\\\n#; git reset --hard'              # backslash-newline joins `a#`: the # is inside a word, not a comment
check "$GIT_HOOK" 2 $'echo $\'\\\' #x\' ; git reset --hard'       # $'\'' is one quoted string: the # in it opens no comment
check "$GIT_HOOK" 2 "git branch newbr # it's"                     # a quote in a real comment must not make the lexer fail and lose the branch rule
check "$GIT_HOOK" 2 "git worktree add ../x # don't"
check "$GIT_HOOK" 2 "git checkout -b n # don't"
check "$HW_HOOK"  2 $'echo a\\\n#; rm -rf ~'
check "$HW_HOOK"  2 $'# a comment \\\nrm -rf ~'

# review 2026-10-10 (independent): a `#` that is NOT at the start of a word, in forms the first drop_comments still read as a comment
check "$HW_HOOK"  2 'echo $(echo a)#b; rm -rf ~'                  # the ) of $( ) ends a substitution inside a word, not a word
check "$HW_HOOK"  2 'echo `echo a #b`; rm -rf ~'                  # a # inside backticks belongs to the substitution
check "$HW_HOOK"  2 'echo ${x:-a #b}; rm -rf ~'                   # a # inside ${ } is data
check "$HW_HOOK"  2 'echo a\ #b; rm -rf ~'                        # an escaped space does not start a word
check "$HW_HOOK"  2 'echo a\;#b; rm -rf ~'                        # nor does an escaped ;
check "$HW_HOOK"  2 $'echo a\r#b; rm -rf ~'                       # a carriage return is not a word boundary in bash
check "$GIT_HOOK" 2 'echo a\ #b; git reset --hard'
check "$GIT_HOOK" 2 'echo a\;#b; git reset --hard'
check "$GIT_HOOK" 2 'echo ${x:-a #b}; git reset --hard'
check "$GIT_HOOK" 2 $'echo a\r#b; git reset --hard'
check "$GIT_HOOK" 2 'echo $(echo a)#b; git reset --hard'
check "$GIT_HOOK" 2 'echo `echo a #b`; git reset --hard'
check "$HW_HOOK"  0 'echo ${x:-a} # trailing note'                 # a real comment after an expansion is still a comment
check "$HW_HOOK"  0 'echo "a #b"; ls'                              # a # inside quotes
check "$GIT_HOOK" 0 'git status # ${x} note'

# no new false positive: a harmless command, with or without a trailing comment, is allowed; a command named only INSIDE a comment is not run
check "$GIT_HOOK" 0 'git status # a && git push --force'
check "$GIT_HOOK" 0 'git commit -m x # foo; git reset --hard'
check "$GIT_HOOK" 0 "ls # it's done"
check "$HW_HOOK"  0 "make # don't rm -rf; ok"
check "$HW_HOOK"  0 'rm -rf build # clean'
check "$HW_HOOK"  0 'rm -rf src/old # remove the stale copy'
check "$HW_HOOK"  0 "rm -rf src/old # don't keep it"
check "$GIT_HOOK" 0 'git status'
check "$GIT_HOOK" 0 'git status  # what changed'
check "$GIT_HOOK" 0 $'# look at the tree first\ngit status'
check "$HW_HOOK"  0 'ls -la'
check "$HW_HOOK"  0 'ls -la  # the build dir'
check "$HW_HOOK"  0 $'# look at the tree first\nls -la'

[ "$FAILS" -eq 0 ] && echo "✅ test_guard_comment_not_swallowing: all passed" || { echo "❌ test_guard_comment_not_swallowing: $FAILS failed"; exit 1; }
