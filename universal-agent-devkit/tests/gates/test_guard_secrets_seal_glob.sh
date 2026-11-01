#!/usr/bin/env bash
# hooks/guard-secrets.py, BUG-REV-968dac9af3 (review of #742): Bash read the seal key (~/.config/agent-workbench/review.key) through a
# shell glob — `cat ~/.config/agent-work*/*`, `cat ~/.conf*/agent-wo*/*` — because only the literal folder / file name was matched.
# Now a word that expands to the folder (or into it) is denied, read component by component against the folder with the shell's
# rules; and since a cd before the glob moves its base, a command with a glob word that names .config is denied too (fail closed).
# Ordinary globs and a commit message that only names the folder still pass. GUARD overrides the hook under test. bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export PYTHONDONTWRITEBYTECODE=1
DK="$(cd "$(dirname "$0")/../.." && pwd)"
G="${GUARD:-$DK/hooks/guard-secrets.py}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
[ -f "$G" ] || { echo "✖ $G does not exist"; exit 1; }

# a scratch HOME holding a fake seal key; the guard runs with it (never the real ~/.config)
export HOME="$TMP/home"
mkdir -p "$HOME/.config/agent-workbench" "$HOME/.config/gh" "$TMP/repo/src"
printf 'fake-test-key\n' > "$HOME/.config/agent-workbench/review.key"
REAL="$(cd "$TMP" && pwd -P)"

verdict() {   # verdict <cwd> <command or Read path> [tool] -> deny|allow
  python3 - "$G" "$1" "$2" "${3:-Bash}" <<'PY'
import json, subprocess, sys
g, cwd, v, tool = sys.argv[1:5]
ti = {"command": v} if tool == "Bash" else {"file_path": v}
p = subprocess.run([sys.executable, g], input=json.dumps({"tool_name": tool, "tool_input": ti, "cwd": cwd}),
                   capture_output=True, text=True, timeout=20)
print("deny" if '"permissionDecision": "deny"' in p.stdout else "allow")
PY
}
expect() {   # expect <deny|allow> <command or Read path> [cwd] [tool]
  local got; got="$(verdict "${3:-$TMP/repo}" "$2" "${4:-Bash}")"
  [ "$got" = "$1" ] && ok "$1: ${4:-Bash} $2" || fail "${4:-Bash} $2: expected $1, got $got"
}

# denied: the folder reached through a glob / brace / case variant
expect deny 'cat ~/.config/agent-work*/*'
expect deny 'cat ~/.config/agent-workbenc?/r*'
expect deny 'cat ~/.conf*/agent-wo*/*'
expect deny 'cat $HOME/.conf*/agent-w*/review.k*'
expect deny 'cat ${HOME}/.config/agent-w*/*'
expect deny "cat $TMP/*/.c*/agent-w*/*"
expect deny "cat $REAL/*/.c*/agent-w*/*"
expect deny 'cat ~/.config/agent-{workbench,x}/*'
expect deny 'cat ~/.{config,x}/agent-workbench/review.ke{y,z}'
expect deny 'cat ~/.[[:alpha:]]onfig/agent-workbench/*'
expect deny 'cat ~/.CONFIG/AGENT-WORKBENCH/REVIEW.KEY'
expect deny 'cat agent-w*/*' "$HOME/.config"
# a cd before the glob moves its base: a glob word with .config named anywhere on the line is denied
expect deny 'cd ~/.config && cat agent-w*/*'
expect deny 'cd ~ && cat .c*/a*/*'
expect deny 'find ~/.c* -name "review.k*" -exec cat {} +'
expect deny 'ls ~/.config/gh/*'   # accepted false positive (fail closed)
# case variants (APFS): the Read tool and a mixed-case Bash path
expect deny "$HOME/.CONFIG/AGENT-WORKBENCH/REVIEW.KEY" "$TMP/repo" Read
expect deny 'cat ~/.Config/Agent-Workbench/Review.Key'
# the parent ~/.config named as a whole: nothing in it is needed through Bash
expect deny 'grep -r . ~/.config'
expect deny 'cp -r ~/.config /tmp/c'
expect deny 'tar czf x.tgz ~/.config'
expect deny 'ls -R ~/.config'
expect deny 'grep -r . $HOME/.CONFIG/'
expect deny 'cd ~ && cp -r .config /tmp/c'
# -C / --chdir / --directory move the base like a cd (env, tar, git, make)
expect deny 'env -C ~ cp -r .config /tmp/c'
expect deny 'tar -C ~ -czf /tmp/x.tgz .config'
expect allow 'tar -C /tmp -czf x.tgz src'
expect allow 'git -C ../other status'
# controls: a sibling name, ~ itself (residual), a lone ls of the parent (names only), a subfolder file
expect allow "$HOME/.config.bak.txt" "$TMP/repo" Read
expect allow 'cat ~/.config.bak.txt'
expect allow 'ls ~'
expect allow 'ls -la ~/.config'
expect allow 'cat ~/.config/gh/hosts.yml'
# allowed: ordinary globs, a commit message that only names the folder, .config without a glob
expect allow 'ls *'
expect allow 'rm *.txt'
expect allow 'cat src/*.py'
expect allow 'git commit -m "fix ~/.config/agent-w* glob"'
expect allow 'ls ~/.config'
expect allow 'if [ -d ~/.config/gh ]; then echo yes; fi'
expect allow 'for i in {1..5}; do echo $i; done'
expect allow 'cat .env.example'

if [ "$FAILS" -ne 0 ]; then echo "guard_secrets_seal_glob: $FAILS FAILED"; exit 1; fi
echo "guard_secrets_seal_glob: all checks passed"
