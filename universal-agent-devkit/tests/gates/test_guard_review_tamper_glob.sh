#!/usr/bin/env bash
# hooks/guard-review-tamper.py, BUG-REV-b91e0de56a (review of #742): a Bash write target, an interpreter / sed -i operand or the signer
# named through a shell glob or brace (`.git/review-fanou?/H/`, `{.git,x}/review-fanout/…`, `.claude/setting*.json`, `hoo?s/`,
# `bin/review_sig?.py`) was matched only as literal text and went through. Now each one is judged on what the shell can expand it to.
# Reads stay allowed, and a glob whose expansions hold nothing protected (`rm -f .git/*.lock`, `cp a build/*`) still passes.
# GUARD overrides the hook under test (RED run against an old copy). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_ALLOW_GATE_EDIT
export PYTHONDONTWRITEBYTECODE=1
DK="$(cd "$(dirname "$0")/../.." && pwd)"
G="${GUARD:-$DK/hooks/guard-review-tamper.py}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
[ -f "$G" ] || { echo "✖ $G does not exist"; exit 1; }

# fixture: a repo whose run dir, settings and lock file exist; a second one before any review ran
H=0123abcd
R="$TMP/repo"; N="$TMP/fresh"
mkdir -p "$R/.git/review-fanout/$H" "$R/.claude" "$R/build" "$R/tests" "$N/.git"
touch "$R/.git/review-fanout/$H/summary.json" "$R/.git/review-fanout/$H/summary.md" "$R/.claude/settings.json" "$R/.git/index.lock" \
  "$R/build/a.o" "$R/tests/test_a.py" "$R/x.py" "$R/a"

export HOME="$TMP/home"; mkdir -p "$HOME"   # a scratch HOME: the seal key path judged below is never the real one

judge() {   # judge <cwd> <command or Read path> [tool] -> deny|allow
  python3 - "$G" "$1" "$2" "${3:-Bash}" <<'PY'
import json, subprocess, sys
g, cwd, v, tool = sys.argv[1:5]
ti = {"command": v} if tool == "Bash" else {"file_path": v}
p = subprocess.run([sys.executable, g], input=json.dumps({"tool_name": tool, "tool_input": ti, "cwd": cwd}),
                   capture_output=True, text=True, timeout=30)
print("deny" if '"deny"' in p.stdout else "allow")
PY
}
expect() {   # expect <deny|allow> <cwd> <command or Read path> [tool]
  local got; got="$(judge "$2" "$3" "${4:-Bash}")"
  [ "$got" = "$1" ] && ok "$1: ${4:-Bash} ${3:0:110}" || fail "${4:-Bash} ${3:0:140}: expected $1, got $got"
}

# denied: a glob / brace that expands into the machinery
expect deny "$R" "cp /tmp/x/summary.json .git/review-fanou?/$H/"
expect deny "$R" "cat x > .git/review-fanou*/$H/summary.json"
expect deny "$R" "mv a {.git,x}/review-fanout/$H/summary.json"
expect deny "$R" "mv a {x,{.git,y}}/review-fanout/$H/summary.json"
expect deny "$R" 'echo "{}" | tee .claude/setting*.json'
expect deny "$R" "cp x $DK/hooks/gua*.py"
expect deny "$R" "cp x $DK/hoo?s/guard-secrets.py"
expect deny "$R" "cp x $DK/hoo[^x]s/guard-secrets.py"
expect deny "$R" "cp x $DK/[[:alpha:]]ooks/guard-secrets.py"
expect deny "$R" "sed -i '' s/a/b/ $DK/hoo?s/guard-secrets.py"
expect deny "$R" "python3 tool.py $DK/hoo?s/guard-secrets.py"
expect deny "$R" 'rm -r -f .gi?'
expect deny "$R" "cd .git && cp x review-fanou?/$H/"
expect deny "$R" "echo x | tee .git/(review-fanout|y)/$H/summary.json"
# the run dir made later on the same line (no review ran yet when the line is judged)
expect deny "$N" 'bash review-fanout.sh; cp x .git/review-fanou?/H1/summary.json'
expect deny "$N" 'cp x .git/*/H1/summary.json'
# the signer driven through a glob / brace
expect deny "$R" "python3 $DK/bin/review_sig?.py sign .git/review-fanou?/$H/summary.json"
expect deny "$R" "python3 $DK/bin/rev*_sign.py sign /tmp/s.json"
expect deny "$R" "python3 $DK/bin/[r]*[n].py sign /tmp/s.json"
expect deny "$R" "python3 $DK/bin/{review_sign,x}.py sign /tmp/s.json"
expect deny "$R" "bash -c \"python3 $DK/b?n/review_s*.py sign /tmp/s.json\""
# case variants: APFS opens .GIT/REVIEW-FANOUT as .git/review-fanout and runs CP / TEE / PYTHON3
expect deny "$R" "cp x .GIT/REVIEW-FANOUT/$H/summary.json"
expect deny "$R" 'echo "{}" | tee .Claude/Settings.json'
expect deny "$R" "CP x .git/review-fanout/$H/summary.json"
expect deny "$R" "PYTHON3 $DK/bin/review_sign.py sign /tmp/s.json"
expect deny "$R" "$HOME/.CONFIG/AGENT-WORKBENCH/REVIEW.KEY" Read
# a write target computed by $( ) / backtick / $VAR on a line that points at the machinery
expect deny "$R" 'cp x $(pwd)/kit/hooks/g.py'
expect deny "$R" 'echo x > "$(git rev-parse --git-common-dir)/review-fanout/H/summary.json"'
expect deny "$R" 'echo x > `git rev-parse --git-dir`/review-fanout/H/summary.json'
# an interpreter handed a protected path that does not exist yet
expect deny "$R" "python3 w.py .git/review-fanout/$H/new.json"
# controls for the three above
expect allow "$R" "cat .GIT/REVIEW-FANOUT/$H/summary.md"
expect allow "$R" "$HOME/.config.bak.txt" Read
expect allow "$R" 'echo $(date) > out.txt'
expect allow "$R" 'python3 tool.py install hooks'
expect allow "$R" "python3 $DK/hooks/guard-secrets.py"
# audit of c42aef31: the case-folded copy alone moved a heredoc end (`SH` -> `sh`), so a later `<<END` swallowed the real cp
expect deny "$R" "$(printf 'cat <<%s > /tmp/a\nSH\ncat <<%s\nsh\ncp x .git/review-fanout/%s/summary.json\nEND' "'sh'" "'END'" "$H")"
expect allow "$R" "$(printf 'cat <<%s > /tmp/a\ncp x .git/review-fanout/%s/summary.json\nsh\necho done' "'sh'" "$H")"
# the signer is executable: run directly, through VAR= / env / nohup / xargs / find -exec / a backtick, it is still driven
expect deny "$R" "$DK/bin/review_sign.py sign .git/review-fanout/$H/summary.json"
expect deny "$DK" "./bin/review_sig?.py sign /tmp/s.json"
expect deny "$R" "env X=1 $DK/bin/review_sign.py sign /tmp/s.json"
expect deny "$R" "nohup $DK/bin/review_sign.py sign /tmp/s.json"
expect deny "$R" "X=1 $DK/bin/REVIEW_SIGN.py sign /tmp/s.json"
expect deny "$R" "echo f | xargs -I{} $DK/bin/review_sign.py sign {}"
expect deny "$R" "find . -name summary.json -exec $DK/bin/review_sign.py sign {} ;"
expect deny "$R" "x=\`$DK/bin/review_sign.py sign /tmp/s.json\`"
expect allow "$R" "cat $DK/bin/review_sign.py"
expect allow "$R" "grep -n load_key $DK/bin/review_sign.py"
expect allow "$R" "sed -n 1,20p $DK/bin/review_sign.py"
# nocaseglob (bash) / NO_CASE_GLOB (zsh): a glob matches a folder in any case
expect deny "$R" "shopt -s nocaseglob; cp x $DK/HOO?S/guard-secrets.py"
# allowed: reads, and globs that expand to nothing protected
expect allow "$R" 'cat .git/review-fanout/*/summary.md'
expect allow "$R" "sed -n 1,5p $DK/hoo?s/guard-secrets.py"
expect allow "$R" 'rm -f .git/*.lock'
expect allow "$N" 'rm -f .git/*.lock'
expect allow "$R" 'cp a build/*'
expect allow "$R" 'rm -r -f build/*'
expect allow "$R" 'python3 x.py'
expect allow "$R" 'python3 -m pytest tests/*.py'
expect allow "$R" 'ls * && rm -f *.txt'

[ "$FAILS" = 0 ] && { echo "guard review tamper glob: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
