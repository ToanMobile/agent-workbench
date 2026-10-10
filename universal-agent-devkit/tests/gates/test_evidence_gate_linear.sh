#!/usr/bin/env bash
# Regression test: hooks/test_evidence_gate.sh reads the whole session transcript at every Stop that carries a claim, and its cost
# must grow with the number of Bash commands in it, not with its square. DevKit backlog #4, measured 2026-10-10 with cProfile on a
# 58 MB OfficeReader transcript: 25.8 s of wall time, 25.4 s of it in _collect_assigns (1.43 million calls) because _env_for(cmd)
# rebuilt the shell variable table of EVERY earlier Bash command for each of the 2274 commands.
# The oracle is a count, not a clock (a clock is noise on a loaded machine): the Python body of the hook runs under cProfile on a
# synthetic transcript of N and of 4N Bash commands, and the number of _collect_assigns calls must stay (nearly) linear. The old
# code makes about N*N/2 calls: 20k for 200 commands, 320k for 800 (a factor of 16, not 4). A second case checks that a variable an
# earlier command assigned still reaches the later command (the table is cumulative and the later assignment wins).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${EVIDENCE_HOOK:-$DEVKIT_DIR/hooks/test_evidence_gate.sh}"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/repo" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t && echo a > a.txt && git add -A && git commit -qm init

# the Python of the hook: the heredoc body after "python3 -I <<'PY'" up to the line "PY"
python3 -I - "$HOOK" "$TMP/body.py" <<'PYX' || { echo "cannot extract the hook body"; exit 1; }
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("python3 -I <<")) + 1
end = next(i for i in range(start, len(lines)) if lines[i] == "PY")
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(lines[start:end]) + "\n")
PYX

# gen <n> <file>: a prompt, then n Bash commands that assign a variable and use it, each with a result.
gen() {
  python3 -I - "$1" "$2" <<'PYX'
import datetime, json, sys
n, path = int(sys.argv[1]), sys.argv[2]
base = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=3000)
def ts(i): return (base + datetime.timedelta(seconds=i)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
rows = [{"type": "user", "timestamp": ts(0), "message": {"role": "user", "content": "fix it"}}]
for i in range(n):
    rows.append({"type": "assistant", "timestamp": ts(1 + 2 * i), "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": "t%d" % i, "name": "Bash", "input": {"command": "V%d=out%d; npm run build -- --target $V%d && echo done" % (i % 7, i, i % 7)}}]}})
    rows.append({"type": "user", "timestamp": ts(2 + 2 * i), "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "t%d" % i, "content": "ok"}]}})
open(path, "w", encoding="utf-8").write("".join(json.dumps(r) + "\n" for r in rows))
PYX
}
# assign_calls <n>: how many times the body called _collect_assigns on a transcript of n Bash commands
assign_calls() {
  gen "$1" "$TMP/t$1.jsonl"
  local payload
  payload="$(python3 -I -c 'import json,sys; print(json.dumps({"session_id":"lin-"+sys.argv[3],"hook_event_name":"Stop","transcript_path":sys.argv[1],
    "cwd":sys.argv[2],"last_assistant_message":"Đã fix lỗi X, test PASS."}))' "$TMP/t$1.jsonl" "$TMP/repo" "$1")"
  CLAUDE_PROJECT_DIR="$TMP/repo" python3 -I -m cProfile -o "$TMP/prof$1" "$TMP/body.py" 3<<<"$payload" >/dev/null 2>&1
  python3 -I -c 'import pstats, sys
st = pstats.Stats(sys.argv[1]).stats
print(sum(v[1] for k, v in st.items() if k[2] == "_collect_assigns"))' "$TMP/prof$1"
}

small="$(assign_calls 200)"; big="$(assign_calls 800)"
if [ -z "$small" ] || [ -z "$big" ] || [ "$small" = 0 ]; then
  fail "(1) no profile: the body did not reach _collect_assigns (small='$small' big='$big')"
elif [ "$big" -lt $((small * 6)) ]; then
  ok "(1) _collect_assigns calls grow linearly: $small for 200 commands, $big for 800"
else
  fail "(1) quadratic: $small calls for 200 commands, $big for 800 (x$((big / small)); linear is x4)"
fi

# (2) a variable assigned by an EARLIER command still expands in a later one, the later assignment wins, and the table follows bash_cmds as it grows.
python3 -I - "$TMP/body.py" <<'PYX' && ok "(2) the shell variable table stays cumulative, the later assignment wins" || fail "(2) variable table changed"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
# the three helpers only, run on their own: the earlier command assigns RUNNER=pytest, the later one overrides it
ns = {"re": re}
exec(re.search(r"^_ASSIGN_RX = .*$", src, re.M).group(0), ns)
exec(src[src.index("def _collect_assigns"):src.index("def _split_segments")], ns)
ns["bash_cmds"] = ["RUNNER=pytest", "V=1", "V=2", "X=1"]
env = ns["_env_for"]("RUNNER=echo; $RUNNER tests/test_x.py")
assert env.get("RUNNER") == "echo" and env.get("X") == "1" and env.get("V") == "2", env
ns["bash_cmds"].append("Y=2")
env2 = ns["_env_for"]("true")
assert env2.get("RUNNER") == "pytest" and env2.get("Y") == "2" and env2.get("X") == "1", env2
PYX

if [ "$FAILS" -ne 0 ]; then echo "test_evidence_gate linear: $FAILS FAILED"; exit 1; fi
echo "test_evidence_gate linear: all passed"
