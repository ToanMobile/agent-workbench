#!/usr/bin/env bash
# Test hồi quy #95 (19/10): ~25/47 thẻ Blocked ở 5 board là việc chỉ người làm được (playtest, máy thật, tài khoản store, quyết định
# thiết kế; nhãn needs-you / human-gated). Kéo lại Ready thì runner và planner vẫn giao chúng: mỗi thẻ tốn một lượt builder/QA
# rồi về Blocked, lặp lại.
# Luật ở đây:
#  1. runner: thẻ Ready mang nhãn needs-you hoặc human-gated (nhãn ở item hay ở content, chuỗi hay {name}, hoa thường bất kỳ)
#     không được chọn; thẻ Ready khác vẫn được chọn. Thẻ ở Review/QA mang needs-you VẪN được chọn: luồng resume đưa thẻ 🙋 đã
#     được người duyệt về Review và nhãn có thể còn (run.md → resume).
#  2. planner (super-board-wave-plan.sh): các thẻ Ready đó không vào `cards`, và được liệt kê trong `waiting`.
#  3. /super-board status: nhóm "chờ người" riêng (mọi cột trừ Done), tách khỏi Block reasons.
# Chạy offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-needs-you.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

ITEMS='{"items":[
 {"id":"I30","status":"Ready","labels":["needs-you"],"content":{"type":"Issue","number":30,"title":"playtest","assignees":[]}},
 {"id":"I31","status":"Ready","content":{"type":"Issue","number":31,"title":"real phone","assignees":[],"labels":[{"name":"Human-Gated"}]}},
 {"id":"I32","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":32,"title":"plain bug","assignees":[]}},
 {"id":"I33","status":"Review","labels":["needs-you"],"content":{"type":"Issue","number":33,"title":"resumed after done","assignees":[]}},
 {"id":"I34","status":"Blocked","labels":["needs-you"],"content":{"type":"Issue","number":34,"title":"store account","assignees":[]}}]}'

# ── 1. runner
( SB_LIB_ONLY=1 . "$RUNNER" || exit 99
  set +e
  log() { :; }; issue_locked() { return 1; }; issue_is_open() { return 0; }; early_backoff() { return 1; }
  INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
  PROJECT_ITEMS_JSON="$ITEMS"
  top_card_in_column "Ready"; echo "ready=$TOP_ISSUE"
  top_card_in_column "Review"; echo "review=$TOP_ISSUE"
) > "$TMP/runner.out" 2>&1
grep -qx "ready=32" "$TMP/runner.out" && ok "runner: Ready cards labelled needs-you / human-gated are skipped, the plain one is picked" \
  || fail "runner Ready pick: $(tr '\n' ' ' < "$TMP/runner.out")"
grep -qx "review=33" "$TMP/runner.out" && ok "runner: a Review card that still carries needs-you is picked (the resume path)" \
  || fail "runner Review pick: $(tr '\n' ' ' < "$TMP/runner.out")"

# ── 2. planner, offline (--items, --deps)
printf '%s' "$ITEMS" > "$TMP/items.json"
printf '{"30":{"runnable":true,"parseable":true,"blockers":[]},"31":{"runnable":true,"parseable":true,"blockers":[]},"32":{"runnable":true,"parseable":true,"blockers":[]},"34":{"runnable":false,"parseable":true,"blockers":[],"humanGated":true}}' > "$TMP/deps.json"
(cd "$ROOT" && SB_GITHUB_HALT_FILE="$TMP/halt.json" bash .claude/bin/super-board-wave-plan.sh --config .claude/super-board/configs/agent-workbench.json \
   --items "$TMP/items.json" --deps "$TMP/deps.json" > "$TMP/plan.json" 2> "$TMP/plan.err"); rc=$?
if [ "$rc" = 0 ] && [ "$(jq -c '[.cards[].number] | sort' "$TMP/plan.json")" = "[32,33]" ]; then
  ok "planner: needs-you / human-gated Ready cards are not in the wave (Review #33 still is)"
else
  fail "planner cards: rc $rc $(jq -c '[.cards[]?.number]' "$TMP/plan.json" 2>/dev/null) $(head -c 300 "$TMP/plan.err")"
fi
[ "$(jq -c '[.waiting[]?.number] | sort' "$TMP/plan.json" 2>/dev/null)" = "[30,31]" ] && ok "planner: they are listed in waiting" \
  || fail "planner waiting: $(jq -c '.waiting' "$TMP/plan.json" 2>/dev/null)"

# ── 3. status: the waiting-on-a-person group
PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT/.claude/bin/super-board-status.py" > "$TMP/status.out" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sb_status", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
items = [
    {"number": 30, "title": "playtest", "labels": ["needs-you"], "status": "Ready"},
    {"number": 34, "title": "store account", "labels": ["needs-you"], "status": "Blocked"},
    {"number": 35, "title": "design call", "labels": ["Human-Gated"], "status": "Blocked"},
    {"number": 36, "title": "done already", "labels": ["needs-you"], "status": "Done"},
    {"number": 37, "title": "waits on #12", "labels": ["bug"], "status": "Blocked"},
]
print("waiting=" + ",".join(str(i["number"]) for i in m.waiting_on_person(items)))
PY
grep -qx "waiting=35,34,30" "$TMP/status.out" && ok "status: needs-you / human-gated cards (any column but Done) form their own group" \
  || fail "status waiting group: $(tail -3 "$TMP/status.out" | tr '\n' ' ')"

[ "$FAILS" -eq 0 ] && echo "✅ test_needs_you_skip: all passed" || { echo "❌ test_needs_you_skip: $FAILS failed"; exit 1; }
