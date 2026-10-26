#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh, the destructive-rm guard (audit 2026-10-09, finding C3):
#   1. a project under /tmp (or $TMPDIR, where mktemp puts it on macOS): `rm -rf <project>` was blocked but `rm -rf ..` and
#      `rm -rf <parent of the project>` exited 0 — the /tmp exemption ran before asking whether the target CONTAINS the
#      project root;
#   2. `find … -delete`, `find … -exec rm -rf {} +` and `… | xargs rm -rf` were never judged on the paths they delete: they are
#      now judged like rm -rf on those paths — find's start points (when no -name/-path/-regex filter narrows them; a filter
#      keeps today's verdict, e.g. the pinned `find . -name __pycache__ -exec rm -rf {} +`), the words of a literal echo /
#      printf piped into xargs; anything else piped into `xargs rm -r…` cannot be read and is refused.
# Only the hook runs here — never the command.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

P="$TMP/work/proj"          # the project, under mktemp (/tmp on Linux, $TMPDIR on macOS)
mkdir -p "$P/src" "$P/build" "$P/app/build" "$TMP/work/other"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'x\n' > "$P/src/a.kt" && git -C "$P" add -A && git -C "$P" commit -qm init
printf 'src\n' > "$P/list.txt"

# run <want rc> <command>
check() {
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ]; then ok "rc $rc: $c"; else fail "rc $rc (want $want): $c — $(head -c 200 "$TMP/err" | tr '\n' ' ')"; fi
}

# 1. a target that holds the project root
check 2 "rm -rf $P"                       # control: already blocked
check 2 'rm -rf ..'
check 2 'rm -rf ../'
check 2 'rm -rf ../*'
check 2 "rm -rf $TMP/work"
check 2 "rm -rf $TMP"
check 2 "cd .. && rm -rf ../work"
check 0 "rm -rf $TMP/work/other"          # a sibling under /tmp: still allowed
check 0 'rm -rf ../other'

# 2. find -delete / find -exec rm / xargs rm: judged on the paths they delete
check 2 'find . -delete'
check 2 'find . -mindepth 1 -delete'
check 2 'find . -exec rm -rf {} +'
check 2 'find . -type d -exec rm -rf {} \;'
check 2 'find src -delete'
check 2 'find . \( -type f -o -type d \) -delete'
check 2 'find . -exec echo {} \; -delete'
check 2 'echo \\; rm -rf ..'               # an escaped backslash, then a real ; — not a find operator
check 2 "echo ';' && rm -rf src"
check 2 "find $TMP/work -delete"
check 2 'find . -print0 | xargs -0 rm -rf'
check 2 'echo src | xargs rm -rf'
check 2 'cat list.txt | xargs rm -rf'
check 2 'xargs -a list.txt rm -rf'
check 2 'git ls-files | xargs -I{} rm -rf {}'
check 0 'find build -delete'
check 0 'find app/build -mindepth 1 -delete'
check 0 "find $TMP/work/other -delete"
check 0 'find . -name __pycache__ -exec rm -rf {} +'
check 0 'find build -type f | xargs rm -rf'
check 0 'echo build | xargs rm -rf'
check 0 'find . -name "*.kt" | xargs wc -l'
check 0 'find . -name "*.kt" -exec wc -l {} +'
check 0 'git ls-files | xargs rm -f'

# 3. audit 2026-10-25 A7: the agent's own scratch (/private/tmp/claude-<uid>/, /tmp/claude-<uid>/). A literal path there stays allowed, but a
#    path SPELLED under it must also end under it: no `..` out of it, and no link it reaches through (a trailing slash makes BSD rm follow
#    the link: `rm -rf link/` empties the link target — measured on macOS 25/10). Variables stay as they were (`rm -rf $X` refused).
U="$(id -u)"; mkdir -p "/tmp/claude-$U" && SCR="$(mktemp -d "/tmp/claude-$U/devkit-hw-test.XXXXXX")" || { fail "no scratch dir"; SCR=""; }
if [ -n "$SCR" ]; then
  trap 'rm -rf "$TMP" "$SCR"' EXIT
  SCRP="$(cd "$SCR" && pwd -P)"; SB="$(basename "$SCR")"
  mkdir -p "$SCR/inner" && ln -s "$HOME" "$SCR/home" && ln -s "$TMP/work/other" "$SCR/elsewhere" && ln -s "$SCRP/inner" "$SCR/inside"
  check 0 "rm -rf $SCRP/kitcopy"                              # literal, /private/tmp spelling
  check 0 "rm -rf /tmp/claude-$U/$SB/stage $SCRP/inner"        # literal, /tmp spelling, two targets
  check 0 "rm -rf $SCRP/kit*"                                 # a glob that stays in the folder
  check 0 "rm -rf $SCRP/home"                                 # no trailing slash: rm removes the link, not $HOME
  check 0 "rm -rf $SCRP/inside/"                              # a link that stays in the scratch folder
  check 2 "rm -rf /private/tmp/claude-$U/../x"
  check 2 "rm -rf /tmp/claude-$U/$SB/../../x"
  check 2 "rm -rf $SCRP/../*"
  check 2 "rm -rf $SCRP/home/"                                # trailing slash through a link to $HOME
  check 2 "rm -rf $SCRP/elsewhere/"                           # … or to a folder outside the scratch folder
  check 2 "rm -rf $SCRP/home/Documents"
  check 2 "rm -rf $SCRP/*/Documents"                          # a glob whose match is the link to \$HOME
  check 2 "rm -rf $SCRP/*/"                                   # … with a trailing slash: rm follows every matched link
  check 2 'rm -rf /'
  check 2 'rm -rf ~'
  check 2 'rm -rf $X'
  # review of A7 (25/10): the scratch check read the SPELLING (a string prefix) and the general branch dropped the trailing slash
  # (normpath), then took the link for one file — `rm -rf <link to $HOME>/` passed in any other spelling of the same folder. Every path is
  # now judged where the kernel resolves it. Spellings are built from $SCRP (the folder the test made), not from a literal /private/tmp.
  TROOT="$(dirname "$(dirname "$SCRP")")"                  # /private/tmp on macOS, /tmp elsewhere
  check 2 "rm -rf $TROOT//claude-$U/$SB/home/"             # C3: an inner //
  check 2 "rm -rf $TROOT/./claude-$U/$SB/home/"            # C4: /./
  check 2 "cd $SCRP && rm -rf home/"                       # C5: relative, after a literal cd
  check 2 "cd $SCRP && rm -rf home/."
  if [ -d "$TROOT/CLAUDE-$U/$SB" ]; then                   # C1: the same folder in another case (APFS is case-insensitive)
    check 2 "rm -rf $TROOT/CLAUDE-$U/$SB/home/"
  else
    echo "skip C1: this filesystem is case-sensitive"
  fi
  HDEPTH="$(python3 -c 'import os; print(len([x for x in os.path.realpath(os.path.expanduser("~")).split("/") if x]))')"
  check 2 "rm -rf ~/$(printf '../%.0s' $(seq "$HDEPTH"))${SCRP#/}/home/"   # ~/../../private/tmp/…: `..` resolved, not read
  check 0 "rm -rf $SCRP/inner/"                            # control: a real folder of the scratch, trailing slash
  check 0 "cd $SCRP && rm -rf inner/"                      # control: … relative
  check 0 "cd $SCRP && rm -rf home"                        # control: no trailing slash, rm removes the link only
  # principal review round 2 (25/10). A4: a `..` that stays in the scratch folder is no escape (every `..` was refused).
  # A2: a glob that can leave its folder with more than 2000 matches now cannot be judged match by match: refused (only 2000 were read).
  mkdir -p "$SCR/a/d1" "$SCR/a/d2" "$SCR/many" && ( cd "$SCR/many" && mkdir d{1..2100} )
  check 0 "cd $SCRP/a/d1 && rm -rf ../d2"
  check 2 "rm -rf $SCRP/many/*/"
  check 0 "rm -rf $SCRP/many/*"                            # control: names in that folder only, no walk
fi

# 4. review of A7 (25/10): a link inside the PROJECT to a folder outside it. With a trailing slash (or /.) rm deletes what the link points at;
#    a glob walks into it as well. Without either, rm removes the link alone (allowed as before).
ln -s "$HOME" "$P/hl" && ln -s "$HOME" "$P/app/build/hl"
check 2 'rm -rf hl/'
check 2 "rm -rf $P/hl/"
check 2 'rm -rf hl/.'
check 2 'rm -rf app/build/hl/*'                            # a glob in a build output, through the link
check 0 'rm -rf hl'
check 0 'rm -rf app/build/hl'
check 0 'rm -rf app/build/'                                # a real build output with a trailing slash
# … and a glob whose MATCH goes through such a link (the folder before the glob is a real build output / /tmp folder): each match that
# leaves that folder is judged where it lands, like the scratch case `$SCRP/*/`
mkdir -p "$P/app/build/real" "$TMP/work/other/real" && ln -s "$HOME" "$TMP/work/other/hl"
check 2 'rm -rf app/build/*/'
check 2 'rm -rf app/build/*/Documents'
check 2 "rm -rf $TMP/work/other/*/"
check 0 'rm -rf app/build/*'                               # no trailing slash: the link itself is removed
check 0 "rm -rf $TMP/work/other/*"
check 0 'rm -rf app/build/real/'

# 5. principal review round 2 (25/10)
# B1: bash expands `~` in an unquoted assignment, so `D=~/x; rm -rf "$D"/` deletes x of the home folder. The hook expanded `~` before it put
#     the variable in, and judged `<cwd>/~/x`. (`D="~/x"`, quoted, is read the same way: refused as the home folder, on purpose.)
check 2 'D=~/Documents; rm -rf "$D"/'
check 2 'D=~/Documents && rm -rf $D/'
check 2 'D=~/Documents; rm -rf $D'
check 0 'D=build; rm -rf "$D"'                             # control: a build output through a variable
# A2: more than 2000 matches of a glob that can leave its folder (trailing /, or a glob before the last name): only 2000 were read, a link
#     after them was never judged. Now refused; a glob in the last name only (`many/*`) is not walked at all, as before.
mkdir -p "$TMP/work/many" && ( cd "$TMP/work/many" && mkdir d{1..2100} )
check 2 "rm -rf $TMP/work/many/*/"
check 0 "rm -rf $TMP/work/many/*"
check 0 'rm -rf build/*'
# A3: the folder before the glob is judged before its matches are walked: a refused folder (the project root here, ~/Library in the
#     review: 7 s, and the harness kills the hook at 10 s, which lets the command run) costs no walk. Judged on the hook's CPU time.
( cd "$P" && mkdir -p deep/a{1..25}/b{1..25}/c{1..25} )
for c in 'rm -rf ./*/*/*/*/zzzz*' 'rm -rf deep/*/*/*/zzzz*'; do
  r="$(python3 -I - "$HOOK" "$P" "$c" <<'PY'
import json, os, resource, subprocess, sys
hook, P, cmd = sys.argv[1:4]
payload = json.dumps({"session_id": "s", "transcript_path": "", "cwd": P, "hook_event_name": "PreToolUse", "tool_name": "Bash",
                      "tool_input": {"command": cmd, "description": "d"}})
r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
r = subprocess.run(["bash", hook], input=payload, capture_output=True, text=True, cwd=P, env=dict(os.environ, CLAUDE_PROJECT_DIR=P))
r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
print(r.returncode, "%.2f" % ((r1.ru_utime - r0.ru_utime) + (r1.ru_stime - r0.ru_stime)))
PY
)"
  case "$r" in
    "2 "*) awk -v c="${r#2 }" 'BEGIN { exit !(c < 0.30) }' && ok "rc 2 in ${r#2 } s CPU (< 0.30): $c" || fail "rc 2 but ${r#2 } s CPU (>= 0.30, the matches were walked): $c" ;;
    *) fail "rc/cpu $r (want rc 2): $c" ;;
  esac
done
# B3: the project root compared by spelling: on APFS `<parent>/PROJ` is the project `<parent>/proj`, and `rm -rf` of it passed (a project
#     under /tmp, where the /tmp exemption answers). Compared by inode now, like the scratch folder.
if [ -d "$TMP/work/PROJ" ]; then
  check 2 "rm -rf $TMP/work/PROJ"
  check 2 "cd $TMP/work && rm -rf PROJ"
  check 2 "rm -rf $TMP/WORK"                               # holds the project root, in another case
  check 2 "rm -rf $TMP/work/proj/SRC"                      # a top-level folder of the project, in another case
else
  echo "skip B3: this filesystem is case-sensitive"
fi

# 6. OCR round 3 (25/10): the Bash tool runs /bin/zsh (measured), the hook reads the line as bash.
# H1: a ( glued to a word is a zsh glob qualifier — build/a(:a:h:h) is the project root, build/*(e:…:) any path the code names. The
#     lexer made the ( a subshell and judged `build/a`. And zsh *** follows links (build/a/hl -> $HOME), ** walks folders Python glob cannot:
#     with a trailing / or before the last name both are refused (glob_may_leave); `build/**/*.o` is one of them, on purpose.
mkdir -p "$P/build/a" && ln -s "$HOME" "$P/build/a/hl"
check 2 'rm -rf build/a(:a:h:h)'
check 2 'rm -rf build/*(:A:h:h)'
check 2 "rm -rf build/*(e:'reply=(/Users/x)':)"
check 2 'rm -rf build/***/'
check 2 'rm -rf build/**/'
check 2 'rm -rf build/**/*.o'
check 2 'rm -rf build/*/*/'                                # control: already refused (the link at depth 2)
check 0 'rm -rf build/*'
check 0 'rm -rf node_modules'
check 0 'rm -rf "$TMPDIR/x"'
check 0 'f() { echo; }; rm -rf build'                     # () of a function is no qualifier
check 0 'x=$(ls build); rm -rf build'                     # nor $( … )
# H2: ~+ (the cwd) and ~- (the previous one) are left as they are by expanduser: `~-/Documents` was judged as `<cwd>/~-/Documents`
check 2 'rm -rf ~+/src'
check 2 'rm -rf ~-/Documents'
check 2 "cd $HOME && cd $P && rm -rf ~-/Documents"
check 2 "cd $HOME && cd $P && cd ~- && rm -rf Documents"
check 2 'rm -rf ~nosuchuser-devkit/x'
check 0 'rm -rf ~+/build'                                 # ~+ is the cwd: a build output

[ "$FAILS" -eq 0 ] && echo "✅ test_hardware_rm_containment: all passed" || { echo "❌ test_hardware_rm_containment: $FAILS failed"; exit 1; }
