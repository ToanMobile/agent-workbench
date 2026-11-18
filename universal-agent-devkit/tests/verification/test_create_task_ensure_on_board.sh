#!/usr/bin/env bash
# Test: `create_task.py --ensure-on-board <issue url>` (18/11 board agent-workbench): gate_full reused open card #685 for a new
# red but #685 was on no project board, so its comment reached no lane and nobody fixed the red.
# Rule: an issue on no board is added to the project and set to Backlog (same as a new card); an issue already on a board is
# left where it is (never pulled back to Backlog); gh errors exit non-zero. Fake gh first on PATH. bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CT="$DEVKIT_DIR/scripts/governance/create_task.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/bin" "$TMP/repo"
export FAKE_LOG="$TMP/calls.jsonl"
cat > "$TMP/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"gh": a}) + "\n")
if a[:2] == ["issue", "view"]:
    rc = int(os.environ.get("FAKE_VIEW_RC", "0"))
    if rc:
        sys.exit(rc)
    print(json.dumps({"projectItems": json.loads(os.environ.get("FAKE_ITEMS", "[]"))})); sys.exit(0)
if a[:2] == ["project", "item-add"]:
    print(json.dumps({"id": "PVTI_9"})); sys.exit(0)
if a[:2] == ["project", "view"]:
    print(json.dumps({"id": "PVT_1"})); sys.exit(0)
if a[:2] == ["project", "field-list"]:
    print(json.dumps({"fields": [{"name": "Status", "id": "F1", "options": [{"name": "Backlog", "id": "B1"}]}]})); sys.exit(0)
if a[:2] == ["project", "item-edit"]:
    sys.exit(0)
sys.stderr.write("fake gh: unexpected %r\n" % (a,)); sys.exit(99)
PY
chmod +x "$TMP/bin/gh"
cd "$TMP/repo" && git init -q . && git remote add origin https://github.com/ToanMobile/agent-workbench.git
export PATH="$TMP/bin:$PATH"
URL=https://github.com/ToanMobile/agent-workbench/issues/685
run() { : > "$FAKE_LOG"; (cd "$TMP/repo" && python3 "$CT" --ensure-on-board "$URL") >"$TMP/out" 2>&1; echo $?; }
has() { grep -q "\"$1\", \"$2\"" "$FAKE_LOG"; }

# A. on no board: added to the project and set to Backlog, exit 0
export FAKE_ITEMS='[]' FAKE_VIEW_RC=0
rc=$(run)
[ "$rc" = 0 ] && has project item-add && grep '"item-edit"' "$FAKE_LOG" | grep -q '"B1"' && grep '"item-add"' "$FAKE_LOG" | grep -q "$URL" \
  && ok "A off-board issue: added to the project in Backlog" || fail "A: rc=$rc $(cat "$TMP/out") calls=$(cat "$FAKE_LOG")"

# B. already on a board: no add, no column change, exit 0
export FAKE_ITEMS='[{"title":"Agent Workbench","status":{"name":"Review"}}]'
rc=$(run)
[ "$rc" = 0 ] && ! has project item-add && ! has project item-edit \
  && ok "B issue already on a board: left in place" || fail "B: rc=$rc calls=$(cat "$FAKE_LOG")"

# C. gh issue view fails: non-zero exit, nothing added
export FAKE_ITEMS='[]' FAKE_VIEW_RC=1
rc=$(run)
[ "$rc" != 0 ] && ! has project item-add \
  && ok "C gh error: non-zero exit, nothing added" || fail "C: rc=$rc calls=$(cat "$FAKE_LOG")"

[ "$FAILS" -eq 0 ] && { echo "✅ test_create_task_ensure_on_board: all passed"; exit 0; } || { echo "❌ test_create_task_ensure_on_board: $FAILS failed"; exit 1; }
