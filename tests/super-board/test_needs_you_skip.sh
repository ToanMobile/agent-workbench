#!/usr/bin/env bash
# Test hồi quy #95 (19/10): ~25/47 thẻ Blocked ở 5 board là việc chỉ người làm được (playtest, máy thật, tài khoản store, quyết định
# thiết kế; nhãn needs-you / human-gated). Kéo lại Ready thì runner và planner vẫn giao chúng: mỗi thẻ tốn một lượt builder/QA
# rồi về Blocked, lặp lại.
# Luật ở đây:
#  1. runner: thẻ Ready mang nhãn needs-you hoặc human-gated (nhãn ở item hay ở content, chuỗi hay {name}, hoa thường bất kỳ)
#     không được chọn; thẻ Ready khác vẫn được chọn. Thẻ ở Review/QA mang needs-you VẪN được chọn: luồng resume đưa thẻ 🙋 đã
#     được người duyệt về Review và nhãn có thể còn (run.md → resume).
#  2. planner (super-board-wave-plan.sh): các thẻ Ready đó không vào `cards`, và được liệt kê trong `waiting`.
#  3. /super-board status: nhóm "chờ người" riêng (cột Ready và Blocked; Review/QA do lane làm), tách khỏi Block reasons.
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
  echo "person_ready=$(person_count Ready)"
) > "$TMP/runner.out" 2>&1
grep -qx "person_ready=2" "$TMP/runner.out" && ok "runner: the 2 Ready cards for a person are counted apart (not in Ready for dispatch or the clean exit)" \
  || fail "runner person_count: $(tr '\n' ' ' < "$TMP/runner.out")"
grep -qx "ready=32" "$TMP/runner.out" && ok "runner: Ready cards labelled needs-you / human-gated are skipped, the plain one is picked" \
  || fail "runner Ready pick: $(tr '\n' ' ' < "$TMP/runner.out")"
grep -qx "review=33" "$TMP/runner.out" && ok "runner: a Review card that still carries needs-you is picked (the resume path)" \
  || fail "runner Review pick: $(tr '\n' ' ' < "$TMP/runner.out")"

# ── 1b (review 19/10): a 🙋 card a person approved goes to Review with needs-you still on (resume); a gate exit 2/5/11 or a
#    [builder] bounce sends it back to Ready with loop:rebase / loop:rebuild-N. That card is work again, not a wait.
BOUNCED='{"items":[
 {"id":"I30","status":"Ready","labels":["needs-you"],"content":{"type":"Issue","number":30,"title":"playtest","assignees":[]}},
 {"id":"I39","status":"Ready","labels":["needs-you","loop:rebase"],"content":{"type":"Issue","number":39,"title":"approved, rebased","assignees":[]}},
 {"id":"I40","status":"Ready","content":{"type":"Issue","number":40,"title":"approved, rebuilt","assignees":[],"labels":[{"name":"needs-you"},{"name":"loop:rebuild-2"}]}}]}'
( SB_LIB_ONLY=1 . "$RUNNER" || exit 99
  set +e
  log() { :; }; issue_locked() { return 1; }; issue_is_open() { return 0; }; early_backoff() { return 1; }
  INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
  PROJECT_ITEMS_JSON="$BOUNCED"
  top_card_in_column "Ready"; echo "ready=$TOP_ISSUE"
  echo "person_ready=$(person_count Ready)"
) > "$TMP/bounced.out" 2>&1
grep -qx "ready=39" "$TMP/bounced.out" && grep -qx "person_ready=1" "$TMP/bounced.out" \
  && ok "runner: a needs-you Ready card back from the lifecycle (loop:rebase / loop:rebuild-N) is work again; only #30 waits" \
  || fail "runner bounced card: $(tr '\n' ' ' < "$TMP/bounced.out")"

# ── 1c (review 19/10): the blocked sweep keeps a card for a person in Blocked whatever the label's case or kind
mkdir -p "$TMP/sbin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/sbin/super-board-github-read.py"
printf '#!/usr/bin/env bash\nprintf %%s\\\\n "$STUB_PLAN"\n' > "$TMP/sbin/super-board-wave-plan.sh"
chmod +x "$TMP/sbin/"*
( SB_LIB_ONLY=1 . "$RUNNER" || exit 99
  set +e
  log() { :; }; gh_checkpoint() { :; }; gh_write_once() { :; }
  set_card_status() { echo "move $1 $2"; }
  SB_GITHUB_READ="$TMP/sbin/super-board-github-read.py"; CONFIG_PATH="$TMP/cfg.json"; RUN_MANIFEST=/dev/null
  PROJECT_ITEMS_JSON='{"items":[
   {"id":"I41","status":"Blocked","labels":["Human-Gated"],"content":{"type":"Issue","number":41,"assignees":[]}},
   {"id":"I42","status":"Blocked","content":{"type":"Issue","number":42,"assignees":[],"labels":[{"name":"Needs-You"}]}},
   {"id":"I43","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":43,"assignees":[]}}]}'
  export STUB_PLAN='{"cards":[],"sweep":[{"number":41,"clearedBy":[9]},{"number":42,"clearedBy":[9]},{"number":43,"clearedBy":[9]}]}'
  sweep_blocked_cards
) > "$TMP/sweep.out" 2>&1
[ "$(grep -c '^move ' "$TMP/sweep.out")" = 1 ] && grep -qx "move I43 Ready" "$TMP/sweep.out" \
  && ok "blocked sweep: Human-Gated / Needs-You cards stay Blocked, the plain one is released" || fail "sweep: $(tr '\n' ' ' < "$TMP/sweep.out")"

# ── 2. planner, offline (--items, --deps)
printf '%s' "$ITEMS" > "$TMP/items.json"
printf '{"30":{"runnable":true,"parseable":true,"blockers":[]},"31":{"runnable":true,"parseable":true,"blockers":[]},"32":{"runnable":true,"parseable":true,"blockers":[]},"34":{"runnable":false,"parseable":true,"blockers":[],"humanGated":true}}' > "$TMP/deps.json"
printf '{"project":{"owner":"x","number":1},"repo":{"path":".","remote":"https://github.com/x/y"},"verify_commands":["bash tests/check.sh"]}' > "$TMP/cfg.json"
(cd "$ROOT" && SB_GITHUB_HALT_FILE="$TMP/halt.json" bash .claude/bin/super-board-wave-plan.sh --config "$TMP/cfg.json" \
   --items "$TMP/items.json" --deps "$TMP/deps.json" > "$TMP/plan.json" 2> "$TMP/plan.err"); rc=$?
if [ "$rc" = 0 ] && [ "$(jq -c '[.cards[].number] | sort' "$TMP/plan.json")" = "[32,33]" ]; then
  ok "planner: needs-you / human-gated Ready cards are not in the wave (Review #33 still is)"
else
  fail "planner cards: rc $rc $(jq -c '[.cards[]?.number]' "$TMP/plan.json" 2>/dev/null) $(head -c 300 "$TMP/plan.err")"
fi
[ "$(jq -c '[.waiting[]?.number] | sort' "$TMP/plan.json" 2>/dev/null)" = "[30,31]" ] && ok "planner: they are listed in waiting" \
  || fail "planner waiting: $(jq -c '.waiting' "$TMP/plan.json" 2>/dev/null)"
printf '%s' "$BOUNCED" > "$TMP/items2.json"
printf '{"30":{"runnable":true,"parseable":true,"blockers":[]},"39":{"runnable":true,"parseable":true,"blockers":[]},"40":{"runnable":true,"parseable":true,"blockers":[]}}' > "$TMP/deps2.json"
(cd "$ROOT" && SB_GITHUB_HALT_FILE="$TMP/halt.json" bash .claude/bin/super-board-wave-plan.sh --config "$TMP/cfg.json" \
   --items "$TMP/items2.json" --deps "$TMP/deps2.json" > "$TMP/plan2.json" 2> "$TMP/plan2.err")
[ "$(jq -c '[.cards[].number] | sort' "$TMP/plan2.json" 2>/dev/null)" = "[39,40]" ] && [ "$(jq -c '[.waiting[].number]' "$TMP/plan2.json")" = "[30]" ] \
  && ok "planner: the bounced approved cards are in the wave, only #30 waits" || fail "planner bounced: $(jq -c '{c:[.cards[]?.number],w:[.waiting[]?.number]}' "$TMP/plan2.json" 2>/dev/null) $(head -c 200 "$TMP/plan2.err")"

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
    {"number": 38, "title": "resumed, a lane reviews it", "labels": ["needs-you"], "status": "Review"},
    {"number": 39, "title": "approved, rebased", "labels": ["needs-you", "loop:rebase"], "status": "Ready"},
]
print("waiting=" + ",".join(str(i["number"]) for i in m.waiting_on_person(items)))
PY
grep -qx "waiting=35,34,30" "$TMP/status.out" && ok "status: needs-you / human-gated Ready and Blocked cards form their own group (not Done, not a Review a lane works)" \
  || fail "status waiting group: $(tail -3 "$TMP/status.out" | tr '\n' ' ')"

[ "$FAILS" -eq 0 ] && echo "✅ test_needs_you_skip: all passed" || { echo "❌ test_needs_you_skip: $FAILS failed"; exit 1; }
