#!/usr/bin/env bash
# Regression test: the block cache of hooks/regression_gate.sh (a Claude session whose previous Stop blocked on the same
# content gets the stored block back without running the suites) is hardened (DevKit backlog #2, measured 2026-10-10):
#   - a FAIL block that came with a suite that can never run on this machine (untested_exit) was never stored, so every
#     Stop re-ran everything (GeelyEx2: exit-1 repeats of the same state, 21 runs / 213 min in 3.9 days);
#   - the key missed the gitignored local config the suites read (.env, local.properties ...), so a FAIL from before a
#     config fix was served again; and it had no age limit (REGRESSION_GATE_REPEAT_TTL_S, default 1800 s, 0 = never reuse);
#   - a stored block outlived a fix of the hook itself (the key now holds the size and mtime of the hook and the gate);
#   - sessions share regression_gate.state.json: the file was read at the start and written minutes later, so the
#     session that finished last erased the entries of the one that finished first (read-merge-write under a lock now).
# Unchanged and checked here as controls: a block with a BUDGET suite is never stored; a third Stop of one content is
# released with a warning; unrelated ignored files do not drop the cache; the time of the reuse is the time of the REAL run.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# A Claude Code transcript (not degraded): the per-session cache applies.
printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"c-r"}' > "$TMP/claude.jsonl"

UNTESTED_SUITE=',{"id":"REG-U","name":"cannot run here","command":"exit 2","untested_exit":2}'
# mkrepo <name> [extra suite json] [command of the failing suite]: a committed matrix with one failing suite that counts its runs
# in $TMP/runs.<name>, then a dirty tree (the Stop only gates a change).
mkrepo() {
  local name="$1" extra="${2:-}" cmd="${3:-}"
  R="$TMP/$name"; mkdir -p "$R/src" "$R/.agents"
  : > "$TMP/runs.$name"
  ( cd "$R" && git init -q . && git config user.email t@t && git config user.name t
    printf '.env\n*.tmp\n' > .gitignore
    echo "fun ok() = 1" > src/Core.kt
    if [ -n "$cmd" ]; then printf '%s\n' "$cmd" > result.sh; else printf 'echo x >> "%s"\nexit 1\n' "$TMP/runs.$name" > result.sh; fi
    cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-R","name":"core","command":"sh result.sh"}$extra]}]}
JSON
    git add -A && git commit -qm init ) >/dev/null
  echo "fun ok() = 2" > "$R/src/Core.kt"
  STATE="$R/.claude/audit-gate/regression_gate.state.json"
}
# stopx <repo> <session> [NAME=value ...]: one Stop. HOOKX overrides the hook under test. Sets RC; stdout/stderr in $TMP/out.<session>, err.<session>.
stopx() {
  local repo="$1" sid="$2"; shift 2
  printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$sid" "${TP:-$TMP/claude.jsonl}" \
    | env FLAKY_RETRY=0 "$@" CLAUDE_PROJECT_DIR="$repo" bash "${HOOKX:-$HOOK}" >"$TMP/out.$sid" 2>"$TMP/err.$sid"
  RC=$?
}
runs() { grep -c x "$TMP/runs.$1" | tr -d ' '; }
REUSED="cùng nội dung với lần chặn trước"
# the stored block of a session: a field of state.repeat[sid]
rep() { python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); e = (d.get("repeat") or {}).get(sys.argv[2]) or {}
print(e.get(sys.argv[3], ""))' "$STATE" "$1" "$2"; }
set_at() { python3 -c 'import json,sys,time
p = sys.argv[1]; d = json.load(open(p))
if sys.argv[3] == "none":
    d["repeat"][sys.argv[2]].pop("at", None)
else:
    d["repeat"][sys.argv[2]]["at"] = time.time() - float(sys.argv[3])
json.dump(d, open(p, "w"))' "$STATE" "$1" "$2"; }

# (1) control: a FAIL block on the same content is served again, the suites run once.
mkrepo base
stopx "$R" s1; r1=$RC; stopx "$R" s1; r2=$RC
[ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$(runs base)" = 1 ] && grep -q "$REUSED" "$TMP/err.s1" \
  && ok "(1) FAIL block: the second Stop on the same content reuses it, suites ran once" \
  || fail "(1) control: rc=$r1/$r2 runs=$(runs base) err='$(head -2 "$TMP/err.s1" | tr '\n' ' ')'"

# (2) a suite that cannot run on this machine (untested_exit) must not stop the FAIL block from being stored.
mkrepo untested "$UNTESTED_SUITE"
stopx "$R" s1; r1=$RC; stopx "$R" s1; r2=$RC
[ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$(runs untested)" = 1 ] && grep -q "$REUSED" "$TMP/err.s1" \
  && ok "(2) FAIL + a suite that cannot run here: the block is stored and reused" \
  || fail "(2) FAIL with an UNTESTED suite was run again (rc=$r1/$r2 runs=$(runs untested))"

# (3) the gitignored local config the suites read is part of the key; other ignored files are not.
mkrepo localcfg
stopx "$R" s1
echo "TOKEN=1" > "$R/.env"; stopx "$R" s1
[ "$RC" = 2 ] && [ "$(runs localcfg)" = 2 ] && ok "(3a) .env changed after the block: the suites ran again" \
  || fail "(3a) stale FAIL served after a local config change (rc=$RC runs=$(runs localcfg))"
mkrepo ignoredjunk
stopx "$R" s1
echo "scratch" > "$R/notes.tmp"; stopx "$R" s1
[ "$RC" = 2 ] && [ "$(runs ignoredjunk)" = 1 ] && ok "(3b) an unrelated ignored file does not drop the cache" \
  || fail "(3b) unrelated ignored file invalidated the cache (rc=$RC runs=$(runs ignoredjunk))"

# (4) age limit: REGRESSION_GATE_REPEAT_TTL_S (default 1800 s, 0 = never reuse); the age counts from the REAL run.
mkrepo ttlold
stopx "$R" s1; set_at s1 2000; stopx "$R" s1
[ "$RC" = 2 ] && [ "$(runs ttlold)" = 2 ] && ok "(4a) a block older than 1800 s is not reused: the suites ran again" \
  || fail "(4a) expired block reused (rc=$RC runs=$(runs ttlold))"
mkrepo ttlyoung
stopx "$R" s1; set_at s1 100; before="$(rep s1 at)"; stopx "$R" s1; after="$(rep s1 at)"
[ "$RC" = 2 ] && [ "$(runs ttlyoung)" = 1 ] && [ -n "$before" ] && [ "$before" = "$after" ] \
  && ok "(4b) a block of 100 s is reused, and the reuse keeps the time of the real run" \
  || fail "(4b) young block (rc=$RC runs=$(runs ttlyoung) at $before -> $after)"
mkrepo ttlenv
stopx "$R" s1; set_at s1 100; stopx "$R" s1 REGRESSION_GATE_REPEAT_TTL_S=60
[ "$RC" = 2 ] && [ "$(runs ttlenv)" = 2 ] && ok "(4c) REGRESSION_GATE_REPEAT_TTL_S=60 drops a block of 100 s" || fail "(4c) TTL env ignored (runs=$(runs ttlenv))"
mkrepo ttlzero
stopx "$R" s1; stopx "$R" s1 REGRESSION_GATE_REPEAT_TTL_S=0
[ "$RC" = 2 ] && [ "$(runs ttlzero)" = 2 ] && ok "(4d) REGRESSION_GATE_REPEAT_TTL_S=0: never reuse" || fail "(4d) TTL 0 reused (runs=$(runs ttlzero))"
mkrepo ttlnone
stopx "$R" s1; set_at s1 none; stopx "$R" s1
[ "$RC" = 2 ] && [ "$(runs ttlnone)" = 2 ] && ok "(4e) a stored block without a time (written by the old hook) is not reused" || fail "(4e) block without a time reused (runs=$(runs ttlnone))"

mkrepo ttlgarbage
stopx "$R" s1; set_at s1 100; stopx "$R" s1 REGRESSION_GATE_REPEAT_TTL_S=abc
[ "$RC" = 2 ] && [ "$(runs ttlgarbage)" = 1 ] && ok "(4g) REGRESSION_GATE_REPEAT_TTL_S=abc: falls back to 1800 s, a block of 100 s is reused" || fail "(4g) garbage TTL (runs=$(runs ttlgarbage))"
mkrepo ttlfuture
stopx "$R" s1; set_at s1 -100000; stopx "$R" s1
[ "$RC" = 2 ] && [ "$(runs ttlfuture)" = 2 ] && ok "(4f) a stored time in the future (clock set back) is not trusted: the suites ran again" || fail "(4f) future time reused (runs=$(runs ttlfuture))"

# (5) a fix of the hook itself drops the stored block (the key holds the size and mtime of the hook and of the gate).
TK="$TMP/kit"; mkdir -p "$TK/hooks"
cp "$DEVKIT_DIR"/hooks/*.py "$HOOK" "$TK/hooks/"
# bin/ is a real folder of links, except post-fix-gate.py which is a copy, so a test can edit the gate without touching the kit
mkdir -p "$TK/bin"
for f in "$DEVKIT_DIR"/bin/*; do
  case "$(basename "$f")" in post-fix-gate.py) cp "$f" "$TK/bin/" ;; *) ln -s "$f" "$TK/bin/$(basename "$f")" ;; esac
done
for d in profiles templates rules scripts; do [ -e "$DEVKIT_DIR/$d" ] && ln -s "$DEVKIT_DIR/$d" "$TK/$d"; done
mkrepo kitsame
HOOKX="$TK/hooks/regression_gate.sh" stopx "$R" s1
HOOKX="$TK/hooks/regression_gate.sh" stopx "$R" s1
[ "$RC" = 2 ] && [ "$(runs kitsame)" = 1 ] && ok "(5a) copied hook, nothing changed: the stored block is reused" || fail "(5a) control (rc=$RC runs=$(runs kitsame))"
mkrepo kitfix
HOOKX="$TK/hooks/regression_gate.sh" stopx "$R" s1
echo "# edited" >> "$TK/hooks/regression_gate.sh"
HOOKX="$TK/hooks/regression_gate.sh" stopx "$R" s1
[ "$RC" = 2 ] && [ "$(runs kitfix)" = 2 ] && ok "(5b) the hook file changed: the stored block is dropped, the suites ran again" \
  || fail "(5b) hook edit did not drop the cache (runs=$(runs kitfix) rc=$RC)"

mkrepo kitgate
HOOKX="$TK/hooks/regression_gate.sh" stopx "$R" s1
echo "# edited" >> "$TK/bin/post-fix-gate.py"
HOOKX="$TK/hooks/regression_gate.sh" stopx "$R" s1
[ "$RC" = 2 ] && [ "$(runs kitgate)" = 2 ] && ok "(5d) the gate file changed: the stored block is dropped, the suites ran again" \
  || fail "(5d) gate edit did not drop the cache (runs=$(runs kitgate) rc=$RC)"
mkrepo kitharness
HOOKX="$TK/hooks/regression_gate.sh" stopx "$R" s1
echo "# edited" >> "$TK/hooks/devkit_harness.py"
HOOKX="$TK/hooks/regression_gate.sh" stopx "$R" s1
[ "$RC" = 2 ] && [ "$(runs kitharness)" = 2 ] && ok "(5e) devkit_harness.py changed: the stored block is dropped, the suites ran again" \
  || fail "(5e) harness edit did not drop the cache (runs=$(runs kitharness) rc=$RC)"

# (5c) an existing test edited by this session together with a FAIL: only a person clears the edit (the user answer, not the tree),
# so the block is never stored and the next Stop runs the suites again.
mkrepo touchfail
( cd "$R" && mkdir -p src/test && echo "assert(true)" > src/test/CoreTest.kt && git add -A && git commit -qm test \
  && echo "// weakened" > src/test/CoreTest.kt && echo "fun ok() = 3" > src/Core.kt ) >/dev/null
python3 - "$R" "$TMP/touch.jsonl" <<'PYT'
import json, sys, time
repo, tp = sys.argv[1], sys.argv[2]
open(tp, "w").write("".join(json.dumps(r) + "\n" for r in [
    {"type": "user", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 600)),
     "message": {"role": "user", "content": "fix it"}},
    {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "e1", "name": "Edit",
        "input": {"file_path": repo + "/src/test/CoreTest.kt", "old_string": "a", "new_string": "b"}}]}}]))
PYT
TP="$TMP/touch.jsonl" stopx "$R" s1; r1=$RC; TP="$TMP/touch.jsonl" stopx "$R" s1
[ "$r1" = 2 ] && grep -q "CoreTest.kt" "$TMP/err.s1" && [ "$(runs touchfail)" = 2 ] \
  && ok "(5c) FAIL + an edited existing test: the block is not stored, the suites ran again" \
  || fail "(5c) touched block was reused (rc=$r1/$RC runs=$(runs touchfail) err='$(head -3 "$TMP/err.s1" | tr '\n' ' ')')"

# (6) a block with a BUDGET suite is never stored (the next Stop must run it); the failing suite is slow so the 1 s budget is gone.
mkrepo budget ',{"id":"REG-S","name":"second","command":"true"}' 'echo x >> '"$TMP/runs.budget"'; sleep 2; exit 1'
stopx "$R" s1 REGRESSION_GATE_BUDGET_S=1; r1=$RC
stopx "$R" s1 REGRESSION_GATE_BUDGET_S=1; r2=$RC
if grep -q "BUDGET" "$TMP/err.s1" "$TMP/out.s1" 2>/dev/null; then
  [ "$r1" = 2 ] && [ "$(runs budget)" = 2 ] && ok "(6) a block with a BUDGET suite is not stored: the suites ran again" || fail "(6) BUDGET block was reused (rc=$r1/$r2 runs=$(runs budget))"
else
  ok "(6) skipped: this machine finished both suites inside the 1 s budget (no BUDGET label)"
fi

# (7) control: the third Stop of one content is released with a warning (MAX_ATTEMPTS 2), the suites still ran once.
mkrepo cap
stopx "$R" s1; stopx "$R" s1; stopx "$R" s1; r3=$RC
[ "$r3" = 0 ] && [ "$(runs cap)" = 1 ] && grep -q "systemMessage" "$TMP/out.s1" \
  && ok "(7) third Stop of one content: released with a warning, suites ran once" || fail "(7) cap control (rc=$r3 runs=$(runs cap))"

# (8) two sessions side by side: the state is read-merged-written, so the session that finishes last keeps the other's entry.
mkrepo merge '' 'echo x >> '"$TMP/runs.merge"'; sleep 2; exit 1'
( stopx_a() { printf '{"session_id":"sa","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/claude.jsonl" \
      | env FLAKY_RETRY=0 TEST_RUN_LOCK_WAIT_S=30 CLAUDE_PROJECT_DIR="$R" bash "$HOOK" >"$TMP/out.sa" 2>"$TMP/err.sa"; }; stopx_a ) &
pa=$!
sleep 0.7
printf '{"session_id":"sb","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/claude.jsonl" \
  | env FLAKY_RETRY=0 TEST_RUN_LOCK_WAIT_S=30 CLAUDE_PROJECT_DIR="$R" bash "$HOOK" >"$TMP/out.sb" 2>"$TMP/err.sb"
wait "$pa"
keys="$(python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); print(" ".join(sorted((d.get("repeat") or {}).keys())))' "$STATE")"
[ "$keys" = "sa sb" ] && ok "(8) two sessions: both stored blocks survive in the shared state" \
  || fail "(8) the later writer erased the other session (repeat keys: '$keys', runs=$(runs merge))"

if [ "$FAILS" -ne 0 ]; then echo "regression gate repeat cache: $FAILS FAILED"; exit 1; fi
echo "regression gate repeat cache: all passed"
