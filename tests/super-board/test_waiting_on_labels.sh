#!/usr/bin/env bash
# Test hồi quy #601: thẻ chỉ chờ thẻ/PR khác không vào Blocked (chung cột với thẻ cần người nên board nhìn như đứng). Luật:
#  1. preflight_gate: `sequence` có blocker MỞ → thẻ ở Ready + nhãn `waiting-on:#N` mỗi blocker, một comment, không giao, không Blocked.
#  2. top_card_in_column và wave planner bỏ qua thẻ Ready có nhãn `waiting-on:`; thẻ không nhãn vẫn được giao.
#  3. release_waiting_on: blocker đã đóng thì gỡ đúng nhãn của nó; hết nhãn thì thẻ được giao; không đọc được trạng thái thì giữ nhãn.
#  4. migrate_blocked_waiting (trong sweep): thẻ Blocked chỉ chờ thẻ mở → Ready + nhãn; không đụng needs-you; chạy lần 2 không ghi gì.
#  5. hold exact (👯 done/in-progress, ❓ unclear) vẫn vào Blocked.
# Chạy offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-waiting-on.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/sbin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/sbin/super-board-github-read.py"
# preflight stub: in verdict thật lấy từ $STUB_VERDICT
printf '#!/usr/bin/env bash\nprintf %%s\\\\n "$STUB_VERDICT"\n' > "$TMP/sbin/super-board-preflight.sh"
# blocked-by.py stub: mỗi số trong $STUB_OPEN (ví dụ "13") là còn mở; rc từ $STUB_RC
cat > "$TMP/sbin/super-board-blocked-by.py" <<'PY'
import os, sys
if os.environ.get("STUB_RC", "0") != "0":
    sys.exit(int(os.environ["STUB_RC"]))
asked = sys.argv[-1].split(",")
openn = os.environ.get("STUB_OPEN", "").split()
keep = [n for n in asked if n in openn]
print("blocked-by: " + (", ".join("#" + n for n in keep) if keep else "-"))
PY
printf '#!/usr/bin/env bash\nprintf %%s\\\\n "$STUB_PLAN"\n' > "$TMP/sbin/super-board-wave-plan.sh"
chmod +x "$TMP/sbin/"*
printf '{"project":{"owner":"x","number":1},"repo":{"path":".","remote":"https://github.com/x/y"}}' > "$TMP/cfg.json"

# $1 = items json, $2 = shell snippet run after the runner is sourced with stubs; prints the recorded writes then the snippet's stdout
run() {
  rm -f "$TMP/w"
  ( SB_LIB_ONLY=1 . "$RUNNER" || exit 99
    set +e
    log() { :; }; gh_checkpoint() { :; }
    gh_write_once() { echo "gh $*" >> "$TMP/w"; }
    set_card_status() { echo "move $1 $2" >> "$TMP/w"; }
    SB_GITHUB_READ="$TMP/sbin/super-board-github-read.py"; SB_PREFLIGHT="$TMP/sbin/super-board-preflight.sh"
    CONFIG_PATH="$TMP/cfg.json"; RUN_MANIFEST=/dev/null; SWEPT_CARDS=""; INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
    PROJECT_ITEMS_JSON="$1"; NO_DEVICE=false
    eval "$2" ) 2>/dev/null
  cat "$TMP/w" 2>/dev/null
}

# ── 1. preflight_gate: sequence với blocker mở
B1='{"items":[{"id":"I601","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":601,"title":"t","assignees":[]}}]}'
export STUB_VERDICT='{"601":{"verdict":"sequence","tag":"overlap","reason":"overlaps PR 9","blockedBy":[12,13],"evidence":["PR 9"]}}'
export STUB_OPEN="12 13"; export STUB_RC=0
OUT="$(run "$B1" 'preflight_gate 601; echo "rc=$?"')"
printf '%s\n' "$OUT" | grep -qx 'rc=1' && ok "1: sequence with open blockers → not dispatched (rc 1)" || fail "1: rc: $(echo "$OUT" | tr '\n' '|')"
printf '%s\n' "$OUT" | grep -q '^move I601 Blocked' && fail "1: card moved to Blocked" || ok "1: card is not moved to Blocked"
printf '%s\n' "$OUT" | grep -qx 'gh issue edit 601 --add-label waiting-on:#12' && printf '%s\n' "$OUT" | grep -qx 'gh issue edit 601 --add-label waiting-on:#13' \
  && ok "1: one waiting-on label per open blocker" || fail "1: labels: $(echo "$OUT" | tr '\n' '|')"
[ "$(printf '%s\n' "$OUT" | grep -c '^gh issue comment 601')" = 1 ] && ok "1: exactly one waiting comment" || fail "1: comments: $(echo "$OUT" | tr '\n' '|')"
# blocker đã đóng hết → không chặn, không nhãn (giữ hành vi cũ: proceed)
STUB_OPEN="" OUT="$(run "$B1" 'preflight_gate 601; echo "rc=$?"')"
printf '%s\n' "$OUT" | grep -qx 'rc=0' && ! printf '%s\n' "$OUT" | grep -q 'add-label' && ok "1: all blockers closed → dispatch, no label" || fail "1: closed: $(echo "$OUT" | tr '\n' '|')"
# 5. hold exact vẫn Blocked
export STUB_VERDICT='{"601":{"verdict":"hold","tag":"unclear","reason":"no AC","evidence":[]}}'
OUT="$(run "$B1" 'preflight_gate 601; echo "rc=$?"')"
printf '%s\n' "$OUT" | grep -qx 'move I601 Blocked' && ok "5: hold/unclear still goes to Blocked" || fail "5: $(echo "$OUT" | tr '\n' '|')"

# ── 2. dispatch bỏ qua thẻ waiting-on
B2='{"items":[
 {"id":"I70","status":"Ready","labels":["bug","waiting-on:#12"],"content":{"type":"Issue","number":70,"assignees":[]}},
 {"id":"I71","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":71,"assignees":[]}}]}'
TOPSTUB='issue_locked() { return 1; }; early_backoff() { return 1; }; issue_is_open() { return 0; }; ready_card_held() { return 1; }'
OUT="$(run "$B2" "$TOPSTUB"'; top_card_in_column Ready; echo "top=$TOP_ISSUE"')"
printf '%s\n' "$OUT" | grep -qx 'top=71' && ok "2: top_card_in_column skips the waiting-on card and takes #71" || fail "2: $(echo "$OUT" | tr '\n' '|')"
printf '%s' "$B2" > "$TMP/items.json"
printf '{"70":{"runnable":true,"parseable":true,"blockers":[],"openBlockers":[],"humanGated":false},"71":{"runnable":true,"parseable":true,"blockers":[],"openBlockers":[],"humanGated":false}}' > "$TMP/deps.json"
printf '{"project":{"owner":"x","number":1},"repo":{"path":".","remote":"https://github.com/x/y"},"verify_commands":["true"]}' > "$TMP/wcfg.json"
(cd "$ROOT" && SB_GITHUB_HALT_FILE="$TMP/halt.json" bash .claude/bin/super-board-wave-plan.sh --config "$TMP/wcfg.json" --items "$TMP/items.json" --deps "$TMP/deps.json" > "$TMP/plan.json" 2> "$TMP/plan.err")
[ "$(jq -c '[.cards[].number]' "$TMP/plan.json" 2>/dev/null)" = "[71]" ] && ok "2: wave planner leaves the waiting-on card out of cards" || fail "2: planner cards: $(jq -c '.cards' "$TMP/plan.json" 2>/dev/null) $(head -c 200 "$TMP/plan.err")"

# ── 3. release_waiting_on
B3='{"items":[{"id":"I80","status":"Ready","labels":["waiting-on:#12","waiting-on:#13"],"content":{"type":"Issue","number":80,"assignees":[]}}]}'
STUB_OPEN="13" OUT="$(run "$B3" 'release_waiting_on')"
{ printf '%s\n' "$OUT" | grep -qx 'gh issue edit 80 --remove-label waiting-on:#12' && ! printf '%s\n' "$OUT" | grep -q 'remove-label waiting-on:#13'; } \
  && ok "3: closed blocker #12 loses its label, open #13 keeps it" || fail "3: $(echo "$OUT" | tr '\n' '|')"
STUB_OPEN="" OUT="$(run "$B3" 'release_waiting_on')"
{ printf '%s\n' "$OUT" | grep -q 'remove-label waiting-on:#12' && printf '%s\n' "$OUT" | grep -q 'remove-label waiting-on:#13'; } \
  && ok "3: every blocker closed → both labels removed" || fail "3: $(echo "$OUT" | tr '\n' '|')"
STUB_RC=79 OUT="$(run "$B3" 'release_waiting_on')"
[ -z "$OUT" ] && ok "3: state unreadable → labels kept" || fail "3: unreadable: $(echo "$OUT" | tr '\n' '|')"

# ── 4. migration trong sweep_blocked_cards
B4='{"items":[
 {"id":"I90","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":90,"assignees":[]}},
 {"id":"I91","status":"Blocked","labels":["needs-you"],"content":{"type":"Issue","number":91,"assignees":[]}}]}'
P4='{"cards":[],"sweep":[],"pending":[{"number":90,"openBlockers":[12,13]},{"number":91,"openBlockers":[12]}]}'
SWSTUB='export STUB_PLAN='"'$P4'"'; PROJECT_ITEMS_JSON='"'$B4'"'; sweep_blocked_cards'
OUT="$(run "$B4" "$SWSTUB")"
{ printf '%s\n' "$OUT" | grep -qx 'move I90 Ready' && printf '%s\n' "$OUT" | grep -qx 'gh issue edit 90 --add-label waiting-on:#12' && printf '%s\n' "$OUT" | grep -qx 'gh issue edit 90 --add-label waiting-on:#13'; } \
  && ok "4: Blocked card waiting only on open cards → Ready + waiting-on labels" || fail "4: $(echo "$OUT" | tr '\n' '|')"
printf '%s\n' "$OUT" | grep -q 'issue edit 91 --add-label waiting-on\|move I91' && fail "4: needs-you #91 touched" || ok "4: needs-you #91 left alone"
# lần 2: bảng mới (thẻ đã Ready), plan không còn pending → không ghi gì mới ngoài việc dọn
B4b='{"items":[{"id":"I90","status":"Ready","labels":["bug","waiting-on:#12","waiting-on:#13"],"content":{"type":"Issue","number":90,"assignees":[]}}]}'
P4b='{"cards":[],"sweep":[],"pending":[]}'
OUT="$(run "$B4b" 'export STUB_PLAN='"'$P4b'"'; sweep_blocked_cards')"
printf '%s\n' "$OUT" | grep -q 'add-label\|move ' && fail "4: second run wrote again: $(echo "$OUT" | tr '\n' '|')" || ok "4: second run writes nothing (idempotent)"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
