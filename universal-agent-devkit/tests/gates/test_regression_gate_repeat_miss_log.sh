#!/usr/bin/env bash
# Regression test (gate speed, 2026-10-15): when a Stop of a session finds ITS OWN stored block still fresh but the key has moved, the hook
# re-runs the whole gate and used to say nothing about why. Measured on the real logs: 5 same-fingerprint repeats inside the 1800 s repeat TTL
# (OfficeReader 14/10 05:22 and 05:23, Goods 13/10 12:28, 14/10 03:57 and 10:47, GeelyEx2 and the workbench repo more) re-ran the suites, and the logs carry neither
# the session nor which part of the key moved, so nobody could tell a second session (by design) from an untracked file that a suite rewrites
# (the key hashes untracked contents, taken BEFORE the run) or a changed local config. The hook now keeps a short hash of each part of the key
# (fp, tree, local, sig) next to the stored block and writes one log line at such a miss:
#     repeat miss sid=<first 8 of the session> differs=<the parts that moved, in order, comma separated>
# Only a miss of the SAME session on a block that is still fresh is a miss: another session, a first Stop, a block past
# REGRESSION_GATE_REPEAT_TTL_S and a hit write no such line (the controls below). The line changes no decision.
#   R1 a hit writes no miss line                              R2 an untracked file rewritten under the same name: differs=tree
#   R3 a changed ignored local config file: differs=local     R4 a changed tracked file: differs=fp,tree
#   R5 another session on the same content: no miss line      R6 a stored block past the TTL: no miss line   R7 an entry stored by the old hook (no parts): differs=unknown
#   R8 the same content through a copy of the kit (the hook and the gate files are part of the key: another stat signature): differs=sig
# The gate's own result cache is off here (DEVKIT_GATE_CACHE=0, as in test_regression_gate_reminder_throttle.sh): the suite fails on unchanged content, and a
# cache that re-used suites would hide it. bash 3.2 compatible; REPEATMISS_KIT=<kit dir> tests another copy of the kit (a mutant must go red).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export WORKTREE_TRUNK_MODE=0   # K12 (18/10): các ca ở đây là phiên sửa thẳng main (không trunk mode); ở trunk mode Stop tại main không gate (test_regression_gate_trunk_main.sh)
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${REPEATMISS_KIT:-$DEVKIT_DIR}/hooks/regression_gate.sh"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
export FLAKY_RETRY=0 VACUITY_REVERT=0 DEVKIT_GATE_CACHE=0
unset REGRESSION_GATE_REPEAT_TTL_S

printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"c-r"}' > "$TMP/claude.jsonl"
R="$TMP/repo"; mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t
printf '.env\n' > .gitignore
echo "fun ok() = 1" > src/Core.kt
printf 'echo x >> "%s/runs"\nexit 1\n' "$TMP" > result.sh
cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-R","name":"core","command":"sh result.sh"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
echo "scratch v1" > scratch.txt     # untracked, present from the start: its NAME is in the fingerprint, its BYTES only in the tree part
echo "A=1" > .env                   # ignored local config
: > "$TMP/runs"
LOG="$R/.claude/audit-gate/regression_gate.log"
STATE="$R/.claude/audit-gate/regression_gate.state.json"
stopx() { # $1 = session id, then NAME=value words
  local sid="$1"; shift
  printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$sid" "$TMP/claude.jsonl" \
    | env "$@" CLAUDE_PROJECT_DIR="$R" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"
  RC=$?
}
runs() { grep -c x "$TMP/runs" | tr -d ' '; }
misses() { grep -c "repeat miss" "$LOG" 2>/dev/null | tr -d ' '; }
lastmiss() { grep "repeat miss" "$LOG" | tail -1 | sed 's/^[0-9T:-]* //'; }

stopx c-one X=1; r1=$(runs)
[ "$RC" = 2 ] && [ "$r1" = 1 ] && [ "$(misses)" = 0 ] && ok "first Stop of session c-one: the gate ran and blocked (the suite fails), no miss line (nothing was stored before)" \
  || fail "first Stop: rc=$RC runs=$r1 misses=$(misses) err='$(head -2 "$TMP/err")'"

stopx c-one X=1
[ "$(runs)" = "$r1" ] && grep -q "(reused result)" "$LOG" && [ "$(misses)" = 0 ] && ok "R1: the same content again is a hit: no gate run, no miss line" \
  || fail "R1: runs $r1 -> $(runs) misses=$(misses) log=$(tail -2 "$LOG")"

echo "scratch v2 other bytes" > scratch.txt
stopx c-one X=1
[ "$(runs)" -gt "$r1" ] && [ "$(misses)" = 1 ] && [ "$(lastmiss)" = "repeat miss sid=c-one differs=tree" ] \
  && ok "R2: an untracked file rewritten under the same name: the gate re-ran and the log says differs=tree" \
  || fail "R2: runs=$(runs) misses=$(misses) last='$(lastmiss)'"

r2=$(runs); echo "A=2" > .env
stopx c-one X=1
[ "$(runs)" -gt "$r2" ] && [ "$(lastmiss)" = "repeat miss sid=c-one differs=local" ] \
  && ok "R3: a changed ignored local config file: differs=local" || fail "R3: runs=$(runs) last='$(lastmiss)'"

echo "fun ok() = 3" > src/Core.kt
stopx c-one X=1
[ "$(lastmiss)" = "repeat miss sid=c-one differs=fp,tree" ] && ok "R4: a changed tracked file moves fp and tree: differs=fp,tree" || fail "R4: last='$(lastmiss)'"

m=$(misses)
stopx c-two X=1
[ "$(misses)" = "$m" ] && ok "R5: another session on the same content writes no miss line (its own block store is empty: a first Stop)" || fail "R5: a miss line for another session: $(lastmiss)"
stopx c-one X=1
[ "$(misses)" = "$m" ] && ok "R5 control: the first session's repeat on the unchanged content is a hit again, no miss line" || fail "R5 control: $(lastmiss)"

echo "scratch v3" > scratch.txt
stopx c-one REGRESSION_GATE_REPEAT_TTL_S=0
[ "$(misses)" = "$m" ] && ok "R6: a stored block past its TTL (TTL 0) is expired by design: no miss line" || fail "R6: a miss line for an expired block: $(lastmiss)"
echo "scratch v4" > scratch.txt
stopx c-one X=1
[ "$(misses)" = "$((m + 1))" ] && [ "$(lastmiss)" = "repeat miss sid=c-one differs=tree" ] && ok "R6 control: the same change with the default TTL is a miss: differs=tree" \
  || fail "R6 control: misses=$(misses) (want $((m + 1))) last='$(lastmiss)'"

# R7: an entry the previous hook stored has no parts: the miss is still named, as unknown
python3 -I -c 'import json,sys
d = json.load(open(sys.argv[1])); e = d["repeat"]["c-one"]; e.pop("parts", None); json.dump(d, open(sys.argv[1], "w"))' "$STATE"
echo "scratch v5" > scratch.txt
stopx c-one X=1
[ "$(lastmiss)" = "repeat miss sid=c-one differs=unknown" ] && ok "R7: a stored block without parts (older hook): the miss line says differs=unknown" || fail "R7: last='$(lastmiss)'"

# R8: the key also holds a stat signature of the hook, the gate and devkit_harness.py (an edited or reinstalled kit is a new key). The same content, the same
# session, through a COPY of the kit (the same bytes, other files and mtimes) moves only that part. The log is the hook's, in the same project.
# Only hooks/ and bin/ are copied (the hook finds the gate next to itself, as test_regression_gate_stale_label.sh relies on); a copy that fails fails the row
# and the row stops there (it must not run the original kit's hook and judge that).
KIT_SRC="$(dirname "$(dirname "$HOOK")")"; KIT_COPY="$TMP/kit2"
if mkdir -p "$KIT_COPY" && cp -R "$KIT_SRC/hooks" "$KIT_COPY/hooks" && cp -R "$KIT_SRC/bin" "$KIT_COPY/bin"; then
  HOOK="$KIT_COPY/hooks/regression_gate.sh"
  stopx c-one X=1
  [ "$(lastmiss)" = "repeat miss sid=c-one differs=sig" ] && ok "R8: the same content through a copy of the kit: differs=sig" || fail "R8: last='$(lastmiss)'"
else
  fail "R8: cannot copy hooks/ and bin/ of $KIT_SRC to $KIT_COPY"
fi

cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "regression gate repeat miss log: $FAILS FAILED"; exit 1; fi
echo "regression gate repeat miss log: all checks passed"
