#!/usr/bin/env bash
# #742 OCR b266f3d4 (review_gate.sh:244): the Stop gate promises to fail closed when git cannot list the uncommitted code, but
# `git diff --name-only HEAD` and `git ls-files --others` ran without a return-code check: a git that exits non-zero with empty
# stdout (corrupt index, dubious ownership) made `changed` empty, the gate logged "no uncommitted code — pass" and the Stop went
# through unreviewed. A failing git query now blocks.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P"
(cd "$P" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
  && echo "def f(): return 1" > app.py && git add -A && git commit -qm i)
P="$(cd "$P" && pwd -P)"
TR="$TMP/t.jsonl"
python3 -I - "$TR" "$P/app.py" <<'PY'
import datetime, json, sys
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
c = {"type": "tool_use", "id": "e1", "name": "Edit", "input": {"file_path": sys.argv[2], "old_string": "1", "new_string": "2"}}
open(sys.argv[1], "a").write(json.dumps({"type": "assistant", "timestamp": stamp, "message": {"role": "assistant", "content": [c]}}) + "\n")
PY
stop() { printf '{"session_id":"s","transcript_path":"%s","hook_event_name":"Stop"}' "$TR" \
  | CLAUDE_PROJECT_DIR="$P" REVIEW_GATE_AUTOSTART=0 bash "$DEVKIT_DIR/hooks/review_gate.sh" >/dev/null 2>"$TMP/err"; }
echo "def f(): return 2" > "$P/app.py"

# 1. control: edited code with no review blocks
stop; rc=$?
[ "$rc" = 2 ] && ok "edited code, no review: blocked (control)" || fail "control not blocked rc=$rc $(cat "$TMP/err")"

# 2. git cannot read the index: the gate blocks instead of passing an empty change list
cp "$P/.git/index" "$TMP/index.bak"
printf 'not an index' > "$P/.git/index"
git -C "$P" diff --name-only HEAD >/dev/null 2>&1 && fail "fixture: git still reads the corrupt index"
stop; rc=$?
[ "$rc" = 2 ] && ok "git error while listing the uncommitted code: blocked (fail-closed)" || fail "git error passed the Stop rc=$rc $(cat "$TMP/err")"
cp "$TMP/index.bak" "$P/.git/index"

# 3. clean tree after commit: nothing to review passes
git -C "$P" add -A && git -C "$P" commit -qm c
stop; rc=$?
[ "$rc" = 0 ] && ok "committed and clean: passes" || fail "clean tree blocked rc=$rc $(cat "$TMP/err")"

[ "$FAILS" -eq 0 ] && { echo "PASS: test_review_gate_git_error"; exit 0; } || { echo "FAIL: $FAILS"; exit 1; }
