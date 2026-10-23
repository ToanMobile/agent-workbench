#!/usr/bin/env bash
# Test hồi quy #235 (22/10): thẻ chỉ chờ thẻ khác (blocked-by: <issue đang mở>) nằm chung cột Blocked với thẻ cần người, nhìn như
# board đứng. Luật:
#  1. planner (super-board-wave-plan.sh): `pending` = thẻ Blocked parse được, còn blocker mở, không phải thẻ cho người.
#  2. runner (sweep_blocked_cards): thẻ `pending` được gắn nhãn "⏳ chờ thẻ khác"; thẻ bị thả khỏi Blocked (hoặc không còn
#     pending) bị gỡ nhãn; thẻ 🙋 (blocked-by: - / needs-you) không bao giờ có nhãn. Plan không có khoá `pending` (planner cũ) thì
#     không đụng nhãn nào.
#  3. /super-board status: Blocked tách "chờ thẻ khác" và "cần người".
# Chạy offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-waiting.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
LBL="⏳ chờ thẻ khác"

# ── 1. planner
ITEMS='{"items":[
 {"id":"I50","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":50,"title":"waits on 12","assignees":[]}},
 {"id":"I51","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":51,"title":"needs a person","assignees":[]}},
 {"id":"I52","status":"Blocked","labels":["needs-you"],"content":{"type":"Issue","number":52,"title":"labelled person","assignees":[]}},
 {"id":"I53","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":53,"title":"blockers closed","assignees":[]}},
 {"id":"I54","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":54,"title":"unparseable","assignees":[]}}]}'
DEPS='{"50":{"runnable":false,"parseable":true,"blockers":[12],"openBlockers":[12],"humanGated":false},
 "51":{"runnable":false,"parseable":true,"blockers":[],"openBlockers":[],"humanGated":true},
 "52":{"runnable":false,"parseable":true,"blockers":[12],"openBlockers":[12],"humanGated":false},
 "53":{"runnable":true,"parseable":true,"blockers":[9],"openBlockers":[],"humanGated":false},
 "54":{"runnable":false,"parseable":false,"blockers":[],"openBlockers":[],"humanGated":false,"why":"x"}}'
printf '%s' "$ITEMS" > "$TMP/items.json"; printf '%s' "$DEPS" > "$TMP/deps.json"
printf '{"project":{"owner":"x","number":1},"repo":{"path":".","remote":"https://github.com/x/y"},"verify_commands":["bash tests/check.sh"]}' > "$TMP/cfg.json"
(cd "$ROOT" && SB_GITHUB_HALT_FILE="$TMP/halt.json" bash .claude/bin/super-board-wave-plan.sh --config "$TMP/cfg.json" \
   --items "$TMP/items.json" --deps "$TMP/deps.json" > "$TMP/plan.json" 2> "$TMP/plan.err")
[ "$(jq -c '[.pending[]?.number]' "$TMP/plan.json" 2>/dev/null)" = "[50]" ] \
  && ok "planner: only the card with an open blocker is pending (🙋, needs-you, closed blockers, unparseable are not)" \
  || fail "planner pending: $(jq -c '.pending' "$TMP/plan.json" 2>/dev/null) $(head -c 200 "$TMP/plan.err")"

# ── 2. runner sweep
mkdir -p "$TMP/sbin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/sbin/super-board-github-read.py"
printf '#!/usr/bin/env bash\nprintf %%s\\\\n "$STUB_PLAN"\n' > "$TMP/sbin/super-board-wave-plan.sh"
chmod +x "$TMP/sbin/"*
sweep() {   # $1 = board items json, $2 = plan json; prints the recorded writes
  rm -f "$TMP/w"
  ( SB_LIB_ONLY=1 . "$RUNNER" || exit 99
    set +e
    log() { :; }; gh_checkpoint() { :; }; gh_write_once() { echo "gh $*" >> "$TMP/w"; }
    set_card_status() { echo "move $1 $2" >> "$TMP/w"; }
    SB_GITHUB_READ="$TMP/sbin/super-board-github-read.py"; CONFIG_PATH="$TMP/cfg.json"; RUN_MANIFEST=/dev/null
    SWEPT_CARDS=""; PROJECT_ITEMS_JSON="$1"; export STUB_PLAN="$2"
    sweep_blocked_cards ) >/dev/null 2>&1
  cat "$TMP/w" 2>/dev/null
}
B='{"items":[
 {"id":"I60","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":60,"assignees":[]}},
 {"id":"I61","status":"Blocked","labels":["bug","⏳ chờ thẻ khác"],"content":{"type":"Issue","number":61,"assignees":[]}},
 {"id":"I62","status":"Blocked","labels":["bug","⏳ chờ thẻ khác"],"content":{"type":"Issue","number":62,"assignees":[]}},
 {"id":"I63","status":"Blocked","labels":["needs-you"],"content":{"type":"Issue","number":63,"assignees":[]}}]}'
P='{"cards":[],"sweep":[{"number":62,"clearedBy":[9]}],"pending":[{"number":60},{"number":61}]}'
OUT="$(sweep "$B" "$P")"
printf '%s\n' "$OUT" | grep -q "^gh issue edit 60 --add-label $LBL" && ok "runner: pending #60 gets the waiting label" || fail "no add-label for #60: $(echo "$OUT" | tr '\n' '|')"
printf '%s\n' "$OUT" | grep -q "issue edit 61 " && fail "#61 already labelled: written again" || ok "runner: already-labelled pending #61 is left alone"
printf '%s\n' "$OUT" | grep -q "^gh issue edit 62 --remove-label $LBL" && ok "runner: released #62 loses the label" || fail "no remove-label for #62: $(echo "$OUT" | tr '\n' '|')"
printf '%s\n' "$OUT" | grep -qx "move I62 Ready" && ok "runner: #62 still moves to Ready" || fail "#62 not moved: $(echo "$OUT" | tr '\n' '|')"
printf '%s\n' "$OUT" | grep -q "issue edit 63 " && fail "🙋 #63 touched" || ok "runner: needs-you #63 never gets the label"
OUT="$(sweep "$B" '{"cards":[],"sweep":[]}')"
printf '%s\n' "$OUT" | grep -q "issue edit" && fail "plan without pending: labels touched: $(echo "$OUT" | tr '\n' '|')" || ok "runner: a plan without a pending key touches no label"
# nhãn trên thẻ đã rời Blocked (kéo tay) cũng bị gỡ
B2='{"items":[{"id":"I70","status":"Ready","labels":["bug","⏳ chờ thẻ khác"],"content":{"type":"Issue","number":70,"assignees":[]}}]}'
OUT="$(sweep "$B2" '{"cards":[],"sweep":[],"pending":[]}')"
printf '%s\n' "$OUT" | grep -q "^gh issue edit 70 --remove-label $LBL" && ok "runner: a stale label on a card outside Blocked is removed" || fail "stale label kept: $(echo "$OUT" | tr '\n' '|')"

# ── 3. status
PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT/.claude/bin/super-board-status.py" > "$TMP/status.out" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sb_status", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
items = [
    {"number": 50, "title": "waits", "labels": ["bug", "⏳ chờ thẻ khác"], "status": "Blocked"},
    {"number": 51, "title": "stuck", "labels": ["bug"], "status": "Blocked"},
    {"number": 52, "title": "ready w/ stale label", "labels": ["⏳ chờ thẻ khác"], "status": "Ready"},
]
print("waiting=" + ",".join(str(i["number"]) for i in m.waiting_on_cards(items)))
PY
grep -qx "waiting=50" "$TMP/status.out" && ok "status: only Blocked cards with the label are 'waiting on another card'" \
  || fail "status waiting_on_cards: $(tail -3 "$TMP/status.out" | tr '\n' ' ')"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
