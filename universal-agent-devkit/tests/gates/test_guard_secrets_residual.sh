#!/usr/bin/env bash
# Regression test (#873, residual after #864): hooks/guard-secrets.py let these through although they read a secret file:
#  a) ANSI-C quoting of a dotenv name     b) a glob with no key-name hint (id_*, *_rsa)   c) braces around a dotenv name
#  d) a dotenv suffix + glob (.env.*)     e) find -name <glob> -exec <reader>             f) upper-case names (.ENV)
#  g) an internal hook error failed OPEN  -> now fails CLOSED (deny with a message).
# Everyday allows (grep '.*' in quotes, ls *, sed, find without -exec) must stay allowed, and a hostile 64 KB glob must stay linear.
# GUARD overrides the hook under test. bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="${GUARD:-$DEVKIT_DIR/hooks/guard-secrets.py}"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
[ -f "$GUARD" ] || { echo "✖ $GUARD does not exist"; exit 1; }

# verdict <tool> <value> -> deny | allow
verdict() {
  python3 - "$GUARD" "$1" "$2" <<'PY'
import json, subprocess, sys
guard, tool, value = sys.argv[1:4]
key = {"Bash": "command", "Read": "file_path", "Grep": "path"}[tool]
p = subprocess.run([sys.executable, guard], input=json.dumps({"tool_name": tool, "tool_input": {key: value}}),
                   capture_output=True, text=True, timeout=20)
print("deny" if '"permissionDecision": "deny"' in p.stdout else "allow")
PY
}
expect() { local got; got="$(verdict "$2" "$4")"; [ "$got" = "$1" ] && ok "$3" || fail "$3: expected $1, got $got"; }

# a) ANSI-C quoting
expect deny Bash 'a) $'"'"'\x2eenv'"'"'' "cat \$'\\x2eenv'"
expect deny Bash 'a) $'"'"'.e\x6ev'"'"'' "cat \$'.e\\x6ev'"
expect deny Bash 'a) octal' "cat \$'\\056env'"
# b) glob without a key-name hint
expect deny Bash 'b) cat id_*' 'cat ~/.ssh/id_*'
expect deny Bash 'b) cat *_rsa' 'cat ~/.ssh/*_rsa'
expect deny Bash 'b) cat id_?sa' 'cat ~/.ssh/id_?sa'
expect deny Bash 'b) cat id_[r]sa' 'cat ~/.ssh/id_[r]sa'
expect deny Grep 'b) Grep glob id_*' '/home/u/.ssh/id_*'
# c) braces
expect deny Bash 'c) cat {.env,x}' 'cat {.env,x}'
expect deny Bash 'c) cat .en{v,}' 'cat .en{v,}'
expect deny Bash 'c) cat .{env}' 'cat .{env}'
# d) dotenv suffix + glob
expect deny Bash 'd) cat .env.*' 'cat .env.*'
expect deny Bash 'd) cat .env.l?cal' 'cat .env.l?cal'
# e) find -name glob -exec reader
expect deny Bash 'e) find -name id_* -exec cat' "find ~ -name 'id_*' -exec cat {} \\;"
expect deny Bash 'e) find -name *_rsa -execdir' "find . -name \"*_rsa\" -execdir cat {} +"
# f) upper case
expect deny Bash 'f) cat .ENV' 'cat .ENV'
expect deny Bash 'f) cat .Env.Local' 'cat .Env.Local'
expect deny Read 'f) Read .ENV' '/repo/.ENV'
expect deny Bash 'f) cat ID_RSA' 'cat ~/.ssh/ID_RSA'
# g) fail closed: a non-string command makes the scanner raise; unparseable stdin
expect_raw() { # <label> <stdin>
  local got; got="$(printf '%s' "$2" | python3 "$GUARD")"
  case "$got" in *'"permissionDecision": "deny"'*"guard-secrets"*) ok "$1" ;; *) fail "$1: got '$got'" ;; esac
}
expect_raw 'g) internal error (command is a list) denies with a message' '{"tool_name":"Bash","tool_input":{"command":["cat",".x"]}}'
expect_raw 'g) unparseable stdin denies with a message' 'not json'

# everyday allows stay allowed
expect allow Bash "allow: grep '.*' quoted" "grep -n '.*' README.md"
expect allow Bash 'allow: ls *' 'ls *'
expect allow Bash 'allow: ls *.json' 'ls *.json'
expect allow Bash 'allow: ls .e*' 'ls src/*.py'
expect allow Bash 'allow: sed' "sed -n '1,5p' file.txt"
expect allow Bash 'allow: find without -exec' "find . -name '*.py'"
expect allow Bash 'allow: find -exec on non-secret glob' "find . -name '*.pyc' -exec rm {} \\;"
expect allow Bash 'allow: braces for source files' 'cp {a,b}.txt dir/'
expect allow Bash 'allow: ${VAR} expansion' 'echo ${HOME}/x'
expect allow Bash 'allow: $'"'"'..'"'"' plain' "echo \$'hello\\nworld'"
expect allow Bash 'allow: ls id_*.pub' 'ls ~/.ssh/id_*.pub'
expect allow Read 'allow: Read .env.example' '/repo/.env.example'

# a 64 KB hostile glob stays linear (main: 0.03 s; the earlier fnmatch version: 56 s)
python3 - "$GUARD" <<'PY' && ok "64 KB '[' glob is judged in under 3 s" || fail "64 KB '[' glob too slow or crashed"
import json, subprocess, sys, time
for body in ("cat " + "[" * 65536, "cat " + "*?" * 32768, "cat " + "[a" * 32768 + "]"):
    t = time.time()
    subprocess.run([sys.executable, sys.argv[1]], input=json.dumps({"tool_name": "Bash", "tool_input": {"command": body}}),
                   capture_output=True, text=True, timeout=30)
    assert time.time() - t < 3, time.time() - t
PY

# R1 (#873 review): many words of unclosed '{' used to cost O(n^2) per word (64 KB = 5 s; main 0.05 s). A slow word must not
# hide a secret behind it (INSTINCT-044): judged in under 3 s AND the secret after it is still denied.
python3 - "$GUARD" <<'PY' && ok "unclosed '{' words: 64 KB judged in under 3 s, secret after them still denied" || fail "unclosed '{' words too slow or secret behind them slipped"
import json, subprocess, sys, time
secret = "." + "env"
for body, want in (("cat " + " ".join(["{" * 4096] * 16), None),
                   ("cat " + " ".join(["{x" * 2048] * 16), None),
                   ("cat " + " ".join(["{" * 4096] * 16) + " " + secret, "deny")):
    t = time.time()
    p = subprocess.run([sys.executable, sys.argv[1]], input=json.dumps({"tool_name": "Bash", "tool_input": {"command": body}}),
                       capture_output=True, text=True, timeout=30)
    assert time.time() - t < 3, time.time() - t
    if want:
        assert '"permissionDecision": "deny"' in p.stdout, p.stdout
PY

if [ "$FAILS" -ne 0 ]; then echo "guard_secrets_residual: $FAILS FAILED"; exit 1; fi
echo "guard_secrets_residual: all checks passed"
