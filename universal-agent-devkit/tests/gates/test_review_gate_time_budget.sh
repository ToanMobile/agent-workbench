#!/usr/bin/env bash
# hooks/review_gate.sh must end by itself before Claude Code's 20 s Stop-hook timeout (review of #742, ab09d0a1f2 + 24d852716a):
# Claude Code lets a Stop THROUGH when it kills a hook at its "timeout", so a slow path (git on a big tree, then the tree hash of
# review-fanout.sh --status and --background, 15 s cap each) turned the fail-closed gate fail-open. Contract: one deadline for the
# whole hook; every step gets only the time left; a step with too little time left is not started; the Stop is blocked (exit 2)
# well before 20 s. A fake review-fanout.sh that sleeps and a slow `git` (PATH shim) stand for the big tree; the hook is run directly
# and timed (no Claude Code kill). DK_HOOKS overrides the hooks dir (RED run); the bin/ next to it is copied with the fake in place
# of review-fanout.sh (review_runner.py stays: _fanout_env loads it). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS_SRC="${DK_HOOKS:-$DEVKIT_DIR/hooks}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
LIMIT=19   # seconds: the hook must have exited by itself (Claude Code kills it at 20 s and the Stop goes through)

KIT="$TMP/kit"; mkdir -p "$KIT"
cp -R "$HOOKS_SRC" "$KIT/hooks" && cp -R "$HOOKS_SRC/../bin" "$KIT/bin" || { echo "fixture: kit copy failed"; exit 1; }
cat > "$KIT/bin/review-fanout.sh" <<'SH'
#!/usr/bin/env bash
# fake review-fanout.sh: fake.conf sets STATUS_SLEEP/STATUS_OUT and BG_SLEEP/BG_OUT; an empty *_OUT hangs (exec: a kill hits the sleep)
here="$(cd "$(dirname "$0")" && pwd)"; . "$here/fake.conf"
case " $* " in
  *" --status "*) s="$STATUS_SLEEP"; out="$STATUS_OUT" ;;
  *" --background "*) s="$BG_SLEEP"; out="$BG_OUT"; echo bg >> "$here/bg.calls" ;;
  *) echo "fake review-fanout: unexpected $*" >&2; exit 2 ;;
esac
[ -n "$out" ] || exec sleep "$s"
sleep "$s"; echo "$out"
SH
fake() { printf 'STATUS_SLEEP=%s\nSTATUS_OUT="%s"\nBG_SLEEP=%s\nBG_OUT="%s"\n' "$1" "$2" "$3" "$4" > "$KIT/bin/fake.conf"; rm -f "$KIT/bin/bg.calls"; }

# slow git (PATH shim): `rev-parse --show-toplevel` (the hook's first git call) takes <top> s; with <hang>, `rev-parse -q --verify HEAD`
# (devkit_harness.verified_head, under its own 10 s cap: a step the hook cannot cut short, only its watchdog can) hangs <hang> s
REAL_GIT="$(command -v git)"
slowgit() {   # slowgit <dir> <top s> [<hang s>]
  mkdir -p "$1"
  { printf '#!/usr/bin/env bash\ncase " $* " in\n  *" rev-parse --show-toplevel "*) sleep %s ;;\n' "$2"
    [ -z "${3:-}" ] || printf '  *" rev-parse -q --verify HEAD "*) exec sleep %s ;;\n' "$3"
    printf 'esac\nexec "%s" "$@"\n' "$REAL_GIT"; } > "$1/git"
  chmod +x "$1/git"
}
slowgit "$TMP/slow-top" 6
slowgit "$TMP/slow-harness" 8 12

P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo "def f(): return 1" > app.py && git add -A && git commit -qm i)
echo "def f(): return 2" > "$P/app.py"
TR="$TMP/t.jsonl"
python3 - "$TR" "$P/app.py" <<'PY'
import datetime, json, sys
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
c = {"type": "tool_use", "id": "e1", "name": "Edit", "input": {"file_path": sys.argv[2], "old_string": "1", "new_string": "2"}}
open(sys.argv[1], "a").write(json.dumps({"type": "assistant", "timestamp": stamp, "message": {"role": "assistant", "content": [c]}}) + "\n")
PY

now() { python3 -c 'import time; print("%.2f" % time.time())'; }
under() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }
# stop <REVIEW_GATE_AUTOSTART> [dir first on PATH]: one Stop through the kit's hook; sets RC and WALL (seconds)
stop() {
  local s e
  s="$(now)"
  printf '{"session_id":"s","transcript_path":"%s","hook_event_name":"Stop"}' "$TR" \
    | env CLAUDE_PROJECT_DIR="$P" REVIEW_GATE_AUTOSTART="$1" PATH="${2:+$2:}$PATH" bash "$KIT/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"
  RC=$?
  e="$(now)"
  WALL="$(python3 -c 'import sys; print("%.1f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$s" "$e")"
}
blocked_in_time() {   # blocked_in_time <case>: exit 2, under LIMIT, a REVIEW-GATE block message naming review-fanout.sh
  if [ "$RC" = 2 ] && under "$WALL" "$LIMIT" && grep -q "⛔ REVIEW-GATE" "$TMP/err" && grep -q -e "review-fanout.sh" -e "Stop hook" "$TMP/err"; then
    ok "$1: Stop blocked by the hook itself in ${WALL} s (rc 2, < ${LIMIT} s)"
  else
    fail "$1: rc=$RC in ${WALL} s (want rc 2 in < ${LIMIT} s): $(head -3 "$TMP/err")"
  fi
}

# control: a fast PASS passes, a fast NONE starts the review and blocks (existing behaviour kept)
fake 0 "PASS /x" 0 ""
stop 1
[ "$RC" = 0 ] && under "$WALL" 6 && ok "control: a fast 4-way PASS passes the Stop (rc 0, ${WALL} s)" \
  || fail "control: fast PASS rc=$RC in ${WALL} s: $(tail -3 "$TMP/err")"
fake 0 "NONE /x" 0 "review-fanout: started in the background (pid 1)"
stop 1
[ "$RC" = 2 ] && under "$WALL" 6 && grep -q "Khởi động ở nền: review-fanout: started" "$TMP/err" && [ -f "$KIT/bin/bg.calls" ] \
  && ok "control: no review yet, time left: --background started and the Stop blocked (${WALL} s)" \
  || fail "control: fast NONE rc=$RC in ${WALL} s: $(head -3 "$TMP/err")"

# (a) --status takes 12 s, --background would take 12 s more: old 12 + 12 s > 20 s
fake 12 "NONE /x" 12 "review-fanout: started in the background (pid 1)"
stop 1
blocked_in_time "(a) slow --status + slow --background"
[ ! -f "$KIT/bin/bg.calls" ] && ok "(a) --background not started with less time left than --status took (it would be killed mid-way)" \
  || fail "(a) --background was started with too little time left"

# (b) git takes 6 s, then --status hangs: old 6 s + the 15 s --status cap > 20 s
fake 30 "" 0 "review-fanout: started in the background (pid 1)"
stop 1 "$TMP/slow-top"
blocked_in_time "(b) slow git + hanging --status"

# (c) git 6 s, --status 2 s (NONE), --background hangs: old 6 + 2 s + the 15 s --background cap > 20 s
fake 2 "NONE /x" 30 ""
stop 1 "$TMP/slow-top"
blocked_in_time "(c) slow git + hanging --background"

# (d) git 8 s, then a git call inside devkit_harness hangs (its own 10 s cap, out of the hook's reach): only the watchdog ends it;
# old 8 + 10 s + --status 3 s > 20 s
fake 3 "NONE /x" 0 "review-fanout: started in the background (pid 1)"
stop 1 "$TMP/slow-harness"
blocked_in_time "(d) slow git inside devkit_harness (watchdog)"

if [ "$FAILS" -ne 0 ]; then echo "review gate time budget: $FAILS FAILED"; exit 1; fi
echo "review gate time budget: all checks passed"
