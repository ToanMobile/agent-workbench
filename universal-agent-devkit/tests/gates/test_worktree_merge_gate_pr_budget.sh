#!/usr/bin/env bash
# #708 (30/10): hooks/worktree_merge_gate.sh - the open-PR lookup. It used to run `gh pr list --head <branch>` once per worktree with ONE shared 3 s
# budget: at ~1 s per gh call the later worktrees ran out of budget, read as "no PR" and the Stop was held although their PR was open.
# Now ONE `gh pr list --repo <owner/repo> --state open --json number,headRefName --limit 200` serves the whole Stop.
#   1 six clean pushed worktrees, each branch with an open PR, gh sleeping 1 s per call: all six get their PR, the Stop passes
#   2 gh fails / hangs: held (fail closed) and the hold says gh failed or timed out, never "no PR" / "open a PR" (also with the automatic merge on in a super-board repo)
#   3 an open PR but an unpushed commit: still held
#   4 ONE gh call for the whole Stop, and its arguments carry `--repo <owner/repo>` of the origin remote
#   5 stop_hook_active=true (the Stop that follows a block): success, one warning line, no block
#   6 stop_hook_active=false and a worktree with no PR at all: held as before
# PR_BUDGET_ONLY1=1: run case 1 only and print the hook's wall time (the #708 before/after measurement).
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
repo() {   # repo <name> <n>: main checkout (origin = acme/widgets) with n published-branch worktrees w1..wn of session s1, each holding a commit main lacks
  local m="$TMP/$1" i; mkdir -p "$m" && G "$m" init -q -b main && printf '.claude/audit-gate/\n/.claude/worktrees/\n' > "$m/.gitignore" \
    && echo a > "$m/a.txt" && G "$m" add -A && G "$m" commit -qm i && G "$m" config user.name t && G "$m" config user.email t@t \
    && G "$m" remote add origin git@github.com:acme/widgets.git
  for i in $(seq 1 "$2"); do
    (cd "$m" && python3 -I "$WTPY" add "$m/.claude/worktrees/w$i" feat-$i --session=s1 --no-init >/dev/null 2>&1) || fail "setup: add w$i"
    echo $i > "$m/.claude/worktrees/w$i/f$i.txt" && G "$m/.claude/worktrees/w$i" add f$i.txt && G "$m/.claude/worktrees/w$i" commit -qm f$i
    G "$m" update-ref refs/remotes/origin/feat-$i "$(G "$m" rev-parse feat-$i)"
  done
  python3 -c 'import json,sys,time,datetime; f,base,n=sys.argv[1],sys.argv[2],int(sys.argv[3])
ts=datetime.datetime.fromtimestamp(time.time()-60, datetime.timezone.utc).isoformat().replace("+00:00","Z")
with open(f,"w") as o:
    o.write(json.dumps({"type":"user","timestamp":ts,"message":{"role":"user","content":"go"}})+"\n")
    for i in range(1,n+1):
        o.write(json.dumps({"type":"assistant","timestamp":ts,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t%d"%i,"name":"Bash","input":{"command":"agent-kit worktree add "+base+"/w%d"%i}}]}})+"\n")' \
    "$TMP/$1.jsonl" "$m/.claude/worktrees" "$2"
}
fakegh() {   # fakegh <name> <sleep s> <mode>: a gh on PATH that logs its arguments to $TMP/calls-<name>; mode ok = PR #701..#706 open on feat-1..feat-6 (the old
  # `--head <branch>` form answers for that branch alone, the new list form for all), none = no open PR, err = exit 1, hang = sleeps 30 s
  mkdir -p "$TMP/bin-$1" && : > "$TMP/calls-$1" && cat > "$TMP/bin-$1/gh" <<SH
#!/bin/sh
echo "\$*" >> "$TMP/calls-$1"
sleep $2
case "$3" in
  err) exit 1 ;;
  hang) sleep 30 ;;
  none) echo '[]' ;;
  ok) case "\$*" in
        *--head*) b=; p=; for a in "\$@"; do [ "\$p" = --head ] && b=\$a; p=\$a; done; echo "[{\"number\":\$((700 + \${b#feat-})),\"headRefName\":\"\$b\"}]" ;;
        *) echo '[{"number":706,"headRefName":"feat-6"},{"number":705,"headRefName":"feat-5"},{"number":704,"headRefName":"feat-4"},{"number":703,"headRefName":"feat-3"},{"number":702,"headRefName":"feat-2"},{"number":701,"headRefName":"feat-1"}]' ;;
      esac ;;
esac
SH
  chmod +x "$TMP/bin-$1/gh"
}
stop() {   # stop <name> <bin dir> [stop_hook_active true|false] [auto merge 0|1]: the hook's exit code; wall seconds in $TMP/secs
  local t0 t1
  t0=$(python3 -c 'import time; print(time.monotonic())')
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","session_id":"s1","cwd":sys.argv[1],"transcript_path":sys.argv[2],"stop_hook_active":sys.argv[3]=="true"}))' \
    "$TMP/$1" "$TMP/$1.jsonl" "${3:-false}" \
    | env CLAUDE_PROJECT_DIR="$TMP/$1" WORKTREE_AUTO_MERGE="${4:-0}" PATH="$2:$PATH" bash "$HOOK" > "$TMP/out" 2> "$TMP/err"
  local rc=$?
  t1=$(python3 -c 'import time; print(time.monotonic())')
  python3 -c 'import sys; print("%.2f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$t0" "$t1" > "$TMP/secs"
  return $rc
}
nopr() { ! grep -q -e "open a PR" -e "mở PR" -e "chưa có PR" -e "no open PR" "$TMP/out" "$TMP/err" 2>/dev/null; }   # a gh failure must never read as "no PR"
has() { grep -q -- "$1" "$TMP/out" "$TMP/err" 2>/dev/null; }

# 1 + 4: six worktrees, gh takes 1 s per call
repo a 6; fakegh a 1 ok
stop a "$TMP/bin-a"; rc=$?
all=1; for n in 701 702 703 704 705 706; do has "#$n" || all=0; done
echo "  hook wall time with 6 worktrees and a 1 s gh: $(cat "$TMP/secs") s"
[ "$rc" = 0 ] && [ "$all" = 1 ] && ok "1: six open PRs, 1 s per gh call: all six found, Stop not held" \
  || fail "1: PR lookup lost worktrees to the shared budget (rc $rc, all found=$all): $(head -c 500 "$TMP/err")"
calls=$(wc -l < "$TMP/calls-a" | tr -d ' ')
[ "$calls" = 1 ] && ok "4: gh called exactly once for the whole Stop" || fail "4: gh called $calls times, want 1: $(cat "$TMP/calls-a")"
grep -q -- "pr list --repo acme/widgets --state open --json number,headRefName --limit 200" "$TMP/calls-a" \
  && ok "4: the call carries --repo acme/widgets (from origin) and the list arguments" || fail "4: gh arguments: $(cat "$TMP/calls-a")"
[ -n "${PR_BUDGET_ONLY1:-}" ] && { echo "wall=$(cat "$TMP/secs")"; [ "$FAILS" = 0 ]; exit; }

# 2: gh fails / hangs: held, and the hold names gh as the reason
repo b 2; fakegh b 0 err
stop b "$TMP/bin-b"; rc=$?
[ "$rc" = 2 ] && has "gh lỗi" && nopr && ok "2: gh fails: held, reason says gh failed" \
  || fail "2: gh failure (rc $rc): $(head -c 500 "$TMP/err")"
repo c 2; fakegh c 0 hang
stop c "$TMP/bin-c"; rc=$?
[ "$rc" = 2 ] && has "gh quá thời gian" && nopr && ok "2: gh hangs: held, reason says gh timed out" \
  || fail "2: gh hang (rc $rc): $(head -c 500 "$TMP/err")"
repo d 2; fakegh d 0 err; mkdir -p "$TMP/d/.claude/super-board/configs" && echo '{}' > "$TMP/d/.claude/super-board/configs/x.json"
stop d "$TMP/bin-d" false 1; rc=$?
[ "$rc" = 2 ] && has "gh lỗi" && nopr && ok "2: gh fails in a super-board repo with the automatic merge on: no \"open a PR\" advice" \
  || fail "2: super-board repo, gh failure (rc $rc): $(head -c 700 "$TMP/err")"

# 3: an open PR does not hold unpushed work
repo e 2; fakegh e 0 ok
echo z > "$TMP/e/.claude/worktrees/w2/z.txt" && G "$TMP/e/.claude/worktrees/w2" add z.txt && G "$TMP/e/.claude/worktrees/w2" commit -qm z   # unpushed commit
stop e "$TMP/bin-e"; rc=$?
[ "$rc" = 2 ] && grep -q "$TMP/e/.claude/worktrees/w2" "$TMP/err" && has "#701" && ! grep -q "#702" "$TMP/err" && ! grep -q "worktrees/w1 \[" "$TMP/err" \
  && ok "3: open PR + unpushed commit: that worktree stays held, the clean one is released" || fail "3: unpushed commit with an open PR (rc $rc): $(head -c 600 "$TMP/err")"

# 5: the Stop that follows a block (stop_hook_active): success, one warning line
repo f 1; fakegh f 0 none
stop f "$TMP/bin-f" true; rc=$?
lines=$(grep -c . "$TMP/out" | tr -d ' ')
[ "$rc" = 0 ] && [ "$lines" = 1 ] && grep -q "stop_hook_active" "$TMP/out" && ! grep -q "⛔" "$TMP/err" \
  && ok "5: stop_hook_active=true: success, one warning line, no block" || fail "5: stop_hook_active=true (rc $rc, $lines out lines): out=$(head -c 400 "$TMP/out") err=$(head -c 400 "$TMP/err")"

# 6: a fresh Stop and a worktree with no PR: held as before
repo g 1; fakegh g 0 none
stop g "$TMP/bin-g" false; rc=$?
[ "$rc" = 2 ] && grep -q "⛔ WORKTREE-MERGE GATE" "$TMP/err" && ok "6: stop_hook_active=false, no PR: held as before" || fail "6: no PR passed the Stop (rc $rc): $(head -c 400 "$TMP/err")"

[ "$FAILS" = 0 ]
