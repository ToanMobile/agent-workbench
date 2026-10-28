#!/usr/bin/env bash
# #571 (28/10): hooks/worktree_merge_gate.sh - a worktree of THIS session on a published branch that is not in main yet:
#   1 the branch has an open PR (gh pr list --head <branch> --state open): the Stop is not held, the note names the PR
#   2 no open PR: held as before
#   3 gh fails or hangs: held as before (fail closed)
#   4 open PR but the worktree has an unpushed commit or an uncommitted file: held (the PR does not hold that work)
#   5 several worktrees and a hanging gh: the per-call timeouts share one budget, the alarm (13 s) never passes the Stop silently
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export DEVKIT_LANG=en GIT_CONFIG_GLOBAL=/dev/null WORKTREE_AUTO_MERGE_WAIT_S=9
unset WORKTREE_TRUNK_MODE WORKTREE_MAX
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/worktree_merge_gate.sh"; WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
repo() {   # repo <name>: main checkout with a published-branch worktree of session s1 holding a commit main lacks
  local m="$TMP/$1"; mkdir -p "$m" && G "$m" init -q -b main && printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$m/.gitignore" \
    && echo a > "$m/a.txt" && G "$m" add -A && G "$m" commit -qm i && G "$m" config user.name t && G "$m" config user.email t@t
  (cd "$m" && python3 -I "$WTPY" add "$m/.claude/worktrees/w" feat-x --session=s1 --no-init >/dev/null 2>&1) || fail "setup: add w"
  echo x > "$m/.claude/worktrees/w/x.txt" && G "$m/.claude/worktrees/w" add x.txt && G "$m/.claude/worktrees/w" commit -qm x
  G "$m" update-ref refs/remotes/origin/feat-x "$(G "$m" rev-parse feat-x)"
  python3 -c 'import json,sys,time,datetime; f,p=sys.argv[1],sys.argv[2]
ts=datetime.datetime.fromtimestamp(time.time()-60, datetime.timezone.utc).isoformat().replace("+00:00","Z")
with open(f,"w") as o:
    o.write(json.dumps({"type":"user","timestamp":ts,"message":{"role":"user","content":"go"}})+"\n")
    o.write(json.dumps({"type":"assistant","timestamp":ts,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"agent-kit worktree add "+p}}]}})+"\n")' "$TMP/$1.jsonl" "$m/.claude/worktrees/w"
}
fakegh() {   # fakegh <name> <shell body>: a gh on PATH
  mkdir -p "$TMP/bin-$1" && printf '#!/bin/sh\n%s\n' "$2" > "$TMP/bin-$1/gh" && chmod +x "$TMP/bin-$1/gh"
}
stop() {   # stop <name> <bin dir>: the hook's exit code; the session is in main, its worktree w is its own
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":"s1","cwd":sys.argv[1],"transcript_path":sys.argv[2]}))' "$TMP/$1" "$TMP/$1.jsonl" \
    | env CLAUDE_PROJECT_DIR="$TMP/$1" WORKTREE_AUTO_MERGE=0 PATH="$2:$PATH" bash "$HOOK" > "$TMP/out" 2> "$TMP/err"
}

repo a; fakegh open 'echo "[{\"number\":569}]"'
stop a "$TMP/bin-open"; rc=$?
[ "$rc" = 0 ] && grep -q "#569" "$TMP/out" "$TMP/err" && ok "published branch with an open PR: Stop not held, note names #569" || fail "open PR held the Stop (rc $rc): $(head -c 300 "$TMP/err")"

repo b; fakegh none 'echo "[]"'
stop b "$TMP/bin-none"; rc=$?
[ "$rc" != 0 ] && ok "published branch without an open PR: held as before" || fail "no open PR passed the Stop (rc $rc)"

repo c; fakegh err 'exit 1'
stop c "$TMP/bin-err"; rc=$?
[ "$rc" != 0 ] && ok "gh fails: held (fail closed)" || fail "gh failure passed the Stop (rc $rc)"

repo d; fakegh hang 'sleep 30'
stop d "$TMP/bin-hang"; rc=$?
[ "$rc" != 0 ] && ok "gh hangs: held (fail closed)" || fail "gh timeout passed the Stop (rc $rc)"

repo e; fakegh open2 'echo "[{\"number\":569}]"'
echo y > "$TMP/e/.claude/worktrees/w/y.txt"   # uncommitted file
stop e "$TMP/bin-open2"; rc=$?
[ "$rc" != 0 ] && ok "open PR + dirty worktree: held" || fail "open PR + dirty worktree passed the Stop (rc $rc)"

repo f; fakegh open3 'echo "[{\"number\":569}]"'
echo z > "$TMP/f/.claude/worktrees/w/z.txt" && G "$TMP/f/.claude/worktrees/w" add z.txt && G "$TMP/f/.claude/worktrees/w" commit -qm z   # unpushed commit
stop f "$TMP/bin-open3"; rc=$?
[ "$rc" != 0 ] && ok "open PR + unpushed commit: held" || fail "open PR + unpushed commit passed the Stop (rc $rc)"

repo g; fakegh hang2 'sleep 30'
for n in 2 3 4 5; do (cd "$TMP/g" && python3 -I "$WTPY" add "$TMP/g/.claude/worktrees/w$n" feat-$n --session=s1 --no-init >/dev/null 2>&1
  echo $n > "$TMP/g/.claude/worktrees/w$n/f$n.txt" && G "$TMP/g/.claude/worktrees/w$n" add f$n.txt && G "$TMP/g/.claude/worktrees/w$n" commit -qm f$n
  G "$TMP/g" update-ref refs/remotes/origin/feat-$n "$(G "$TMP/g" rev-parse feat-$n)"); done
python3 - "$TMP/g.jsonl" "$TMP/g/.claude/worktrees" <<'PY'
import json,sys
f,base=sys.argv[1:3]
rows=[json.loads(l) for l in open(f)]
for n in "2345":
    rows.append({"type":"assistant","timestamp":rows[1]["timestamp"],"message":{"role":"assistant","content":[{"type":"tool_use","id":"t"+n,"name":"Bash","input":{"command":"agent-kit worktree add "+base+"/w"+n}}]}})
open(f,"w").write("".join(json.dumps(r)+"\n" for r in rows))
PY
stop g "$TMP/bin-hang2"; rc=$?
[ "$rc" != 0 ] && ok "5 worktrees + hanging gh: held (budget, not the alarm)" || fail "5 worktrees + hanging gh passed the Stop (rc $rc)"

[ "$FAILS" = 0 ]
