#!/usr/bin/env bash
# The review seal key (~/.config/agent-workbench) is never read by an agent tool call (#742 review REDUCED at 14108864):
#   ae4413f24a: judge() missed camelCase filePath / notebookPath, a Grep / Glob with no path (it searches the cwd) and a Glob whose
#               pattern hides the folder behind `?` / `[` (it cut the pattern at `*` only, and only for an absolute one);
#   e8eb813d18: .claude/settings.json registers guard-review-tamper for Edit…|Bash only, so a Read / Grep never reached it. The guard
#               registered for Read|Grep is guard-secrets.py: it now runs the same seal check (thư mục cha, cwd, glob) — no new
#               matcher in settings.json (anh Đạt 20:20: only the 5 approved hook lines).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_ALLOW_GATE_EDIT
DK="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="$(cd "$DK/.." && pwd)"
T="$DK/hooks/guard-review-tamper.py"
S="$DK/hooks/guard-secrets.py"
H="$(cd "$HOME" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
judge() {   # judge <hook> <tool> <tool_input json> <cwd> -> deny|allow
  python3 - "$@" <<'PY'
import json, subprocess, sys
g, tool, ti, cwd = sys.argv[1:5]
p = subprocess.run([sys.executable, g], input=json.dumps({"tool_name": tool, "tool_input": json.loads(ti), "cwd": cwd}),
                   capture_output=True, text=True, timeout=20)
print("deny" if '"deny"' in p.stdout else "allow")
PY
}
expect() {   # expect <deny|allow> <tool> <tool_input json> [cwd]: both hooks give the same answer
  for g in "$T" "$S"; do
    got="$(judge "$g" "$2" "$3" "${4:-/repo}")"
    [ "$got" = "$1" ] && ok "$1 ($(basename "$g")): $2 $3 ${4:-}" || fail "$(basename "$g"): $2 $3 ${4:-}: expected $1, got $got"
  done
}
# camelCase keys
expect deny Read        "{\"filePath\": \"$H/.config/agent-workbench/review.key\"}"
expect deny NotebookRead "{\"notebookPath\": \"$H/.config/agent-workbench/x.ipynb\"}"
# a search of a folder above the key, given as path or reached as the cwd
expect deny Grep "{\"pattern\": \"[0-9a-f]{64}\", \"path\": \"$H/.config\"}"
expect deny Grep "{\"pattern\": \"[0-9a-f]{64}\"}" "$H/.config"
expect deny Grep "{\"pattern\": \"[0-9a-f]{64}\"}" "$H"
expect deny Glob "{\"pattern\": \"**/*\"}" "$H/.config/agent-workbench"
# a Glob pattern that hides the folder behind ? or [
expect deny Glob '{"pattern": "~/.conf?g/agent-workbench/*"}'
expect deny Glob "{\"pattern\": \"$H/.con[f]ig/agent-workbench/*\"}"
expect deny Glob "{\"pattern\": \".conf?g/**\", \"path\": \"$H\"}"
expect deny Glob '{"pattern": "../../../.conf?g/agent-workbench/*"}' "$H/a/b/c"
# ordinary reads stay allowed
expect allow Read "{\"filePath\": \"/repo/src/app.py\"}"
expect allow Grep '{"pattern": "review_sign"}' /repo
expect allow Grep '{"pattern": "TODO", "path": "/repo/universal-agent-devkit"}' /repo
expect allow Glob '{"pattern": "**/*.py"}' /repo
expect allow Glob '{"pattern": "src/**/*.ts", "path": "/repo"}' /repo
# the wiring that makes the guard-secrets half real: settings.json sends Read and Grep to guard-secrets.py
python3 - "$ROOT/.claude/settings.json" <<'PY' && ok "settings.json: guard-secrets.py runs for Read and Grep" || fail "settings.json: guard-secrets.py is not registered for Read and Grep"
import json, re, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except OSError:
    print("skip: no .claude/settings.json (devkit outside the monorepo)"); sys.exit(0)
m = [e.get("matcher") or "" for e in d.get("hooks", {}).get("PreToolUse", [])
     if any("guard-secrets.py" in h.get("command", "") for h in e.get("hooks", []))]
sys.exit(0 if all(any(re.fullmatch(x, t) for x in m) for t in ("Read", "Grep")) else 1)
PY
got="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.config/agent-workbench/review.key"},"cwd":"/repo"}' "$H" | DEVKIT_ALLOW_GATE_EDIT=1 python3 "$S")"
case "$got" in *'"deny"'*) ok "guard-secrets: DEVKIT_ALLOW_GATE_EDIT=1 does not open the key file itself (its own SECRET_RE)";; *) fail "guard-secrets: key file read allowed in maintenance mode";; esac
[ "$FAILS" = 0 ] && { echo "guard review tamper read paths: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
