#!/usr/bin/env bash
# hooks/guard-review-tamper.py bypasses found by the 2/2 review of #742 (31/10/2026, r14d):
#   BUG-REV-4a3ec3ef82 (F14) interpreter options before -c/-e (`python3 -I -c`, `node --no-warnings -e`, `perl -w -e`), a path-qualified interpreter
#   BUG-REV-c23bc3cb6d (F5)  a write inside `bash <<EOF` / `bash -c`, the hooks dir itself (`rm -rf …/hooks`)
#   BUG-REV-5f7bee1cb0 (F15) `cd "$VAR"` then a relative write, a line shlex cannot tokenise (fail-open `or []`), a write through a symlink
#   BUG-REV-592ad1528c (F6) / BUG-REV-738b4fa129 (F4) the seal key read by Read/Grep/Bash, the signer driven by a Bash line or a written script
# Reads of the code and ordinary work stay allowed.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_ALLOW_GATE_EDIT
DK="$(cd "$(dirname "$0")/../.." && pwd)"
G="$DK/hooks/guard-review-tamper.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
# judge <tool> <value> [cwd] [content] -> deny|allow
judge() {
  python3 - "$G" "$1" "$2" "${3:-/repo}" "${4:-}" <<'PY'
import json, subprocess, sys
g, tool, v, cwd, content = sys.argv[1:6]
key = {"Bash": "command", "Grep": "path", "Glob": "path"}.get(tool, "file_path")
ti = {key: v}
if tool == "Write":
    ti["content"] = content
elif tool == "Edit":
    ti.update(old_string="x", new_string=content)
elif tool in ("Grep", "Glob"):
    ti["pattern"] = "."
p = subprocess.run([sys.executable, g], input=json.dumps({"tool_name": tool, "tool_input": ti, "cwd": cwd}),
                   capture_output=True, text=True, timeout=20)
print("deny" if '"deny"' in p.stdout else "allow")
PY
}
expect() { got="$(judge "${@:2}")"; [ "$got" = "$1" ] && ok "$1: $2 ${3:0:90}" || fail "$2 ${3:0:120}: expected $1, got $got"; }

# F14: options between the interpreter and its inline code, an interpreter named by path
expect deny Bash "python3 -I -c 'open(\".git/review-fanout/x/summary.json\",\"w\").write(\"1\")'"
expect deny Bash "python3 -u -W ignore -c 'open(\".git/review-fanout/x/summary.json\",\"w\")'"
expect deny Bash "/usr/bin/python3 -c 'open(\".git/review-fanout/x/summary.json\",\"w\")'"
expect deny Bash "node --no-warnings -e \"require('fs').writeFileSync('.git/review-fanout/x/summary.json','1')\""
expect deny Bash "perl -w -e 'unlink \"universal-agent-devkit/hooks/review_gate.sh\"'"
# F5: a shell fed a heredoc / -c, the hooks directory itself
expect deny Bash "$(printf "bash <<'EOF'\ncp fake.json .git/review-fanout/x/summary.json\nEOF")"
expect deny Bash "sh -c 'cp /tmp/s.json .git/review-fanout/x/summary.json'"
expect deny Bash 'rm -rf universal-agent-devkit/hooks'
# F15: cd into a computed directory then a relative write; a line shlex cannot read; a symlink into the run dir
expect deny Bash 'cd "$(git rev-parse --git-common-dir)/review-fanout/H" && cp /tmp/s.json summary.json && cp /tmp/s.json.sig summary.json.sig'
expect deny Bash "echo \$'a\\'b' > .git/review-fanout/H/summary.json"
mkdir -p "$TMP/r/.git/review-fanout/H"; ln -s "$TMP/r/.git/review-fanout" "$TMP/r/rf"
expect deny Write "$TMP/r/rf/H/summary.json" "$TMP/r"
expect deny Bash 'cp /tmp/s.json rf/H/summary.json' "$TMP/r"
# F6 / F4: the seal key is never read, the signer never driven
expect deny Read "$HOME/.config/agent-workbench/review.key"
expect deny Grep "$HOME/.config"
expect deny Glob "$HOME/.config/agent-workbench"
expect deny Bash 'cat ~/.config/agent-workbench/review.key'
expect deny Bash 'base64 < "$HOME/.config/agent-workbench/review.key"'
expect deny Bash 'python3 universal-agent-devkit/bin/review_sign.py sign /tmp/x/summary.json'
expect deny Bash "python3 -c 'import sys; sys.path.insert(0, \"universal-agent-devkit/bin\"); import review_sign; review_sign.sign(\"s.json\")'"
expect deny Write /tmp/forge.py /repo 'import review_sign
review_sign.sign("/tmp/s.json")'
expect deny Write /tmp/forge.py /repo 'k = open(os.path.expanduser("~/.config/agent-workbench/review.key")).read()'
expect deny Edit /repo/tools/x.py /repo 'from review_sign import load_key'
# still allowed: running the review, reading the code, ordinary work after a cd $VAR, docs that name the signer
expect allow Bash 'bash universal-agent-devkit/bin/review-fanout.sh --repo . --base merge-base --status'
expect allow Bash 'REVIEW_SKIP_REVIEWERS=grok,ocr bash universal-agent-devkit/bin/review-fanout.sh --repo "$PWD" --base merge-base --skip grok,ocr --background'
expect allow Bash 'python3 universal-agent-devkit/bin/review_sign.py verify .git/review-fanout/H/summary.json'
expect allow Bash 'grep -n review_sign universal-agent-devkit/bin/review-merge.py'
expect allow Bash 'cd "$TMP" && echo x > notes.txt'
expect allow Bash "python3 -I -c 'print(1)'"
expect allow Bash 'bash -e scripts/build.sh'
expect allow Read /repo/universal-agent-devkit/bin/review_sign.py
expect allow Grep /repo/universal-agent-devkit
expect allow Write /repo/docs/review.md /repo 'The seal is written by bin/review_sign.py.'
expect allow Write /repo/src/app.py /repo 'print("hello")'
# guard-secrets.py is the guard registered for Read|Grep in .claude/settings.json: it refuses the seal key too (F6)
S="$DK/hooks/guard-secrets.py"
secrets() {   # secrets <tool> <value> -> deny|allow
  python3 - "$S" "$1" "$2" <<'PY'
import json, subprocess, sys
g, tool, v = sys.argv[1:4]
key = {"Bash": "command", "Grep": "path"}.get(tool, "file_path")
p = subprocess.run([sys.executable, g], input=json.dumps({"tool_name": tool, "tool_input": {key: v}}), capture_output=True, text=True, timeout=20)
print("deny" if '"deny"' in p.stdout else "allow")
PY
}
sexpect() { got="$(secrets "$2" "$3")"; [ "$got" = "$1" ] && ok "guard-secrets $1: $2 $3" || fail "guard-secrets $2 $3: expected $1, got $got"; }
sexpect deny Read "$HOME/.config/agent-workbench/review.key"
sexpect deny Grep "$HOME/.config/agent-workbench"
sexpect deny Bash 'cat ~/.config/agent-workbench/review.key'
sexpect deny Bash 'xxd review.key'
sexpect allow Read /repo/universal-agent-devkit/bin/review_sign.py
sexpect allow Bash 'ls ~/.config'
[ "$FAILS" = 0 ] && { echo "guard review tamper bypasses: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
