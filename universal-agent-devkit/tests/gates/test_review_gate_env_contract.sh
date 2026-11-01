#!/usr/bin/env bash
# hooks/review_gate.sh judges the DEFAULT 4-way review, whatever the session's environment says (review of #742 at 14108864,
# BUG-REV 2823727da8, hook side, r23c): _fanout_env passed REVIEW_REGRESSION_STATUS and REVIEW_CLAUDE/GROK/AGY_MODEL on to
# review-fanout.sh, so an inherited status file outside the repo (an empty checklist: the open BUG-REV rows vanish) or another
# model named another code state, and a PASS sealed for that state passed the Stop. ANTIGRAVITY_PM_AGY (the agy binary
# pm-review-audit runs) is a reviewer binary override like REVIEW_*_BIN and goes the same way. Contract (shared with
# super-board-merge-gate.sh): only a trusted caller sets the out-of-tree status (B2 of #742), never the Stop gate's environment.
# DK_HOOKS overrides the hooks dir (RED run); the hook finds bin/ next to it.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="${DK_HOOKS:-$DEVKIT_DIR/hooks}"
BIN="$HOOKS/../bin"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export HOME="$TMP/home"; mkdir -p "$HOME"   # the seal key of this test only
export REVIEW_GATE_AUTOSTART=0              # never start a reviewer here
unset REVIEW_SKIP_REVIEWERS REVIEW_CLAUDE_MODEL REVIEW_GROK_MODEL REVIEW_AGY_MODEL REVIEW_REGRESSION_STATUS ANTIGRAVITY_PM_AGY \
  REVIEW_CLAUDE_BIN REVIEW_GROK_BIN REVIEW_AGY_CLI REVIEW_DEEP_LINES
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
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
mkdir -p "$TMP/st"; echo '{"items":{}}' > "$TMP/st/empty.json"   # an outside checklist with no BUG-REV rows
printf '#!/bin/sh\nexit 0\n' > "$TMP/agy"; chmod +x "$TMP/agy"
F="$BIN/review-fanout.sh"
# seal [VAR=value…]: a signed PASS for the code state (and reviewer runtime) review-fanout computes in that environment
seal() {
  local h rt d
  h="$(env "$@" bash "$F" --repo "$P" --base merge-base --hash)" || { fail "fixture: --hash failed ($*)"; return 1; }
  rt="$(env "$@" python3 - "$BIN" <<'PY'
import importlib.util, json, os, sys
sp = importlib.util.spec_from_file_location("rr", os.path.join(sys.argv[1], "review_runner.py"))
rr = importlib.util.module_from_spec(sp); sp.loader.exec_module(rr)
print(json.dumps(rr.reviewer_runtime([])) if hasattr(rr, "reviewer_runtime") else "null")
PY
)"
  rm -rf "$P/.git/review-fanout"; d="$P/.git/review-fanout/$h"; mkdir -p "$d"
  python3 - "$d/summary.json" "$h" "$rt" <<'PY'
import json, sys
meta = {"code_hash": sys.argv[2], "required": ["claude", "antigravity", "grok", "ocr", "registry"]}
if json.loads(sys.argv[3]) is not None:
    meta["runtime"] = json.loads(sys.argv[3])
json.dump({"verdict": "PASS", "reasons": [], "meta": meta}, open(sys.argv[1], "w"))
PY
  printf '# 4-way review: PASS\n' > "$d/summary.md"
  python3 "$BIN/review_sign.py" sign "$d/summary.json" || fail "fixture: seal failed ($*)"
}
stop() { printf '{"session_id":"s","transcript_path":"%s","hook_event_name":"Stop"}' "$TR" \
  | env CLAUDE_PROJECT_DIR="$P" "$@" bash "$HOOKS/review_gate.sh" >/dev/null 2>"$TMP/err"; }

# a PASS sealed for the state an inherited override names does not pass the Stop of a session that inherits it
for v in "REVIEW_REGRESSION_STATUS=$TMP/st/empty.json" "REVIEW_CLAUDE_MODEL=claude-opus-4-1" "REVIEW_GROK_MODEL=grok-3-mini" \
         "REVIEW_AGY_MODEL=gemini-3-flash" "ANTIGRAVITY_PM_AGY=$TMP/agy"; do
  seal "$v"
  stop "$v"; rc=$?
  [ "$rc" = 2 ] && ok "inherited ${v%%=*}: a PASS sealed for its code state does not pass the Stop (rc 2)" \
    || fail "inherited ${v%%=*}: the gate took the PASS of the overridden review (rc $rc)"
done

# control: the default review's PASS passes, and the inherited overrides do not move the gate off it
seal
stop; rc=$?
[ "$rc" = 0 ] && ok "control: the default 4-way PASS passes the Stop" || fail "control: default PASS rc=$rc $(tail -3 "$TMP/err")"
stop "REVIEW_REGRESSION_STATUS=$TMP/st/empty.json" REVIEW_CLAUDE_MODEL=claude-opus-4-1 REVIEW_GROK_MODEL=grok-3-mini \
  REVIEW_AGY_MODEL=gemini-3-flash "ANTIGRAVITY_PM_AGY=$TMP/agy"; rc=$?
[ "$rc" = 0 ] && ok "with every override inherited the gate still judges the default review (rc 0)" \
  || fail "inherited overrides moved the gate off the default review (rc $rc): $(tail -3 "$TMP/err")"
[ "$FAILS" = 0 ] && { echo "review gate env contract: all checks passed"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
