#!/usr/bin/env bash
# Test hồi quy (#1402): thẻ app bị chặn vì lỗi DevKit mang marker `sb-blocked-reason: devkit-incident`
# và `blocked-by: ToanMobile/agent-workbench#<N>` (không phải Needs You); khi task kit đóng và kit đã sync,
# sweep tự đưa thẻ về lane cũ (Building → Ready).
# Chạy offline, tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPS="$ROOT/.claude/bin/super-board-deps.sh"
STATUS="$ROOT/.claude/bin/super-board-status.py"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-1402.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export SB_GITHUB_HALT_FILE="$TMP/github-halt.json"

# 1. super-board-deps.sh hiểu blocked-by chéo repo (ToanMobile/agent-workbench#500)
BLK_DK='[qa] [blocker] 🛑 blocked · ⚙ lỗi DevKit (ToanMobile/agent-workbench#500)\nReason tag:  ⚙\nMove back:   drag this card to QA after the steps above are done\n<!-- sb-blocked-reason: devkit-incident repo=ToanMobile/agent-workbench issue=500 from=QA -->\nblocked-by:  ToanMobile/agent-workbench#500'
printf '[{"number":101,"title":"app card","state":"OPEN","body":"## Blocked by\\n- None.\\n","labels":{"nodes":[]},"comments":{"nodes":[{"body":"%s"}]}}]' "$BLK_DK" > "$TMP/p.json"
DEPS_OUT="$("$DEPS" --repo ToanMobile/OfficeReader --from "$TMP/p.json" 2>&1)"
if python3 - "$DEPS_OUT" <<'PY' 2>/dev/null; then
import json, sys
d = json.loads(sys.argv[1])["101"]
assert d["parseable"] is True, d
assert d["humanGated"] is False, d
assert d["agentParked"] is True, d
assert d["runnable"] is False, d
assert d["needsYou"] is False, d
assert d["externalBlockers"] == ["ToanMobile/agent-workbench#500"], d
PY
  ok "deps.sh: blocked-by chéo repo parseable=true, agentParked=true, runnable=false, needsYou=false"
else
  fail "deps.sh không hiểu blocked-by chéo repo: $DEPS_OUT"
fi

# 2. super-board-status.py nhận blocked-by chéo repo là hợp lệ
ST_OUT="$(cd "$ROOT" && PYTHONDONTWRITEBYTECODE=1 python3 - "$STATUS" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sb_status", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
comments = {
    101: [{"body": "blocked-by: ToanMobile/agent-workbench#500", "createdAt": "2026-11-21T01:00:00Z"}],
    102: [{"body": "blocked-by: #377", "createdAt": "2026-11-21T01:00:00Z"}],
}
bad, rest = m.split_unreadable_blocked_by([{"number": 101, "title": "a"}, {"number": 102, "title": "b"}], comments)
assert 101 not in bad and 102 in bad, (bad, rest)
print("OK_STATUS")
PY
)"
if printf '%s\n' "$ST_OUT" | grep -qx "OK_STATUS"; then
  ok "status.py: blocked-by chéo repo hợp lệ, #377 thiếu repo vẫn báo lỗi"
else
  fail "status.py từ chối nhầm blocked-by chéo repo: $ST_OUT"
fi

# 3. sweep_devkit_blocked trong super-board-run.sh
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/repo/wl"
cat > "$TMP/bin/super-board-github-read.py" <<'PY'
import json, os, sys
a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if a[:2] == ["issue", "view"]:
    num = a[2]
    states = json.loads(os.environ.get("FAKE_KIT_STATES", "{}"))
    info = states.get(num)
    if not info:
        sys.exit(1)
    print(json.dumps(info))
    sys.exit(0)
sys.exit(1)
PY
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
printf '#!/usr/bin/env bash\nexit "${FAKE_SYNC_RC:-0}"\n' > "$TMP/sync-check.sh"
chmod +x "$TMP/sync-check.sh"

export HOME="$TMP/home" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
SB_DEVKIT_SYNC_CHECK="$TMP/sync-check.sh"
SB_DEVKIT_SWEEP_EVERY=0
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR/noops"
WORKER_LOG_DIR="$TMP/repo/wl"; REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"; BASE_BRANCH="main"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }

PROJECT_ITEMS_JSON='{"items":[
  {"id":"PVTI_101","status":"Blocked","labels":[],"content":{"type":"Issue","number":101,"title":"qa devkit","assignees":[]}},
  {"id":"PVTI_102","status":"Blocked","labels":[],"content":{"type":"Issue","number":102,"title":"build devkit","assignees":[]}},
  {"id":"PVTI_103","status":"Blocked","labels":[],"content":{"type":"Issue","number":103,"title":"stale marker","assignees":[]}},
  {"id":"PVTI_104","status":"Blocked","labels":["needs-you"],"content":{"type":"Issue","number":104,"title":"human wait","assignees":[]}}
]}'
cap_progress_comments() {
  case "$1" in
    101) cat <<'JSON'
[{"body":"[qa] [blocker] 🛑 blocked · ⚙ lỗi DevKit (ToanMobile/agent-workbench#500)\nReason tag:  ⚙\nMove back:   drag this card to QA after the steps above are done\n<!-- sb-blocked-reason: devkit-incident repo=ToanMobile/agent-workbench issue=500 from=QA -->\nblocked-by:  ToanMobile/agent-workbench#500"}]
JSON
      ;;
    102) cat <<'JSON'
[{"body":"[builder] [blocker] 🛑 blocked · ⚙ lỗi DevKit (ToanMobile/agent-workbench#501)\nReason tag:  ⚙\nMove back:   drag this card to Ready after the steps above are done\n<!-- sb-blocked-reason: devkit-incident repo=ToanMobile/agent-workbench issue=501 from=Building -->\nblocked-by:  ToanMobile/agent-workbench#501"}]
JSON
      ;;
    103) cat <<'JSON'
[
  {"body":"[qa] [blocker] 🛑 blocked · ⚙ lỗi DevKit\n<!-- sb-blocked-reason: devkit-incident repo=ToanMobile/agent-workbench issue=500 from=QA -->\nblocked-by:  ToanMobile/agent-workbench#500"},
  {"body":"[orchestrator] [report] ↩️ back to QA · lỗi DevKit đã sửa và đồng bộ"},
  {"body":"[qa] [blocker] 🛑 blocked · 🔐 missing token\nReason tag:  🔐\nMove back:   drag this card to QA after the steps above are done\nblocked-by:  -"}
]
JSON
      ;;
    *) echo '[{"body":"[builder] [blocker] 🛑 blocked · 🙋 cần người\nReason tag:  🙋\nblocked-by:  -"}]' ;;
  esac
}

# 3a. Task kit còn OPEN, dù sync OK → giữ nguyên Blocked
: > "$TMP/writes"
DEVKIT_NON_DK_CARDS=""; DEVKIT_SWEEP_NEXT=0
export FAKE_KIT_STATES='{"500":{"state":"OPEN","stateReason":null},"501":{"state":"CLOSED","stateReason":"NOT_PLANNED"}}'
export FAKE_SYNC_RC=0
sweep_devkit_blocked
if [ ! -s "$TMP/writes" ]; then
  ok "sweep: task kit OPEN hoặc NOT_PLANNED → giữ thẻ Blocked"
else
  fail "sweep mở nhầm thẻ khi task kit còn OPEN/NOT_PLANNED: $(cat "$TMP/writes")"
fi

# 3b. Task kit đã CLOSED (COMPLETED), nhưng kit CHƯA sync (sync check exit 1) → giữ nguyên Blocked
: > "$TMP/writes"
DEVKIT_NON_DK_CARDS=""; DEVKIT_SWEEP_NEXT=0
export FAKE_KIT_STATES='{"500":{"state":"CLOSED","stateReason":"COMPLETED"},"501":{"state":"CLOSED","stateReason":"COMPLETED"}}'
export FAKE_SYNC_RC=1
sweep_devkit_blocked
if [ ! -s "$TMP/writes" ]; then
  ok "sweep: task kit CLOSED nhưng chưa sync → giữ thẻ Blocked"
else
  fail "sweep mở nhầm thẻ khi kit chưa sync: $(cat "$TMP/writes")"
fi

# 3c. Task kit đã CLOSED (COMPLETED) VÀ kit đã sync (exit 0) → đưa về lane cũ (#101→QA, #102 Building→Ready), bỏ qua #103/#104
: > "$TMP/writes"
DEVKIT_NON_DK_CARDS=""; DEVKIT_SWEEP_NEXT=0
export FAKE_SYNC_RC=0
sweep_devkit_blocked
rc_sw=$?
if [ "$rc_sw" = 0 ] \
   && grep -q "move PVTI_101 QA" "$TMP/writes" \
   && grep -q "move PVTI_102 Ready" "$TMP/writes" \
   && ! grep -q "PVTI_103" "$TMP/writes" \
   && ! grep -q "PVTI_104" "$TMP/writes"; then
  ok "sweep: task kit CLOSED + đã sync → #101 về QA, #102 (Building) về Ready; #103 (marker cũ) và #104 (needs-you) giữ nguyên"
else
  fail "sweep sai: rc=$rc_sw writes=$(tr '\n' ';' < "$TMP/writes")"
fi

[ "$FAILS" = 0 ] && { echo "PASS test_devkit_blocked_sweep_1402"; exit 0; }
echo "FAIL test_devkit_blocked_sweep_1402 ($FAILS)"; exit 1
