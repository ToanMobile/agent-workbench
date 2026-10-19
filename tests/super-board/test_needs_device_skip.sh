#!/usr/bin/env bash
# Test hồi quy #95, phần thẻ cần máy thật (19/10): thẻ chỉ kiểm được trên máy Android thật vẫn được giao cho lane QA khi không có
# máy nào cắm: lane chỉ có thể park nó về Blocked, rồi kéo lại Ready thì lặp lại.
# Luật ở đây (nhãn `needs-device`, hoa thường bất kỳ, ở item hay content, chuỗi hay {name}):
#  0. super-board-device-online.py: exit 0 chỉ khi `adb devices` có máy trạng thái `device` KHÔNG phải emulator-* và KHÔNG nằm
#     trong denylist (ADB_DENY_SERIALS, ~/.config/universal-agent-devkit/adb-denylist, <repo>/.adb-denylist); adb thiếu / kit
#     thiếu: exit 1 và nói lý do.
#  1. runner: khi không có máy thật, thẻ needs-device ở QA, hoặc ở Ready có nhãn `qa`, không được chọn và không tính vào
#     Ready/QA (để lần chạy không-daemon vẫn thoát sạch). Thẻ Ready needs-device không có `qa` vẫn đi Builder; thẻ Review không
#     bị giữ; thẻ QA mang needs-you vẫn được chọn (luồng resume). Có máy thật thì mọi thẻ đó được chọn lại.
#  2. planner: các thẻ đó không vào `cards`, nằm trong `waiting` kèm `why`; có máy thì vào `cards`.
#  3. status: nhóm "Waiting on you" có các thẻ đó khi không có máy thật.
#  4. Board chỉ có thẻ thường: runner và planner để stub adb nguyên (file adb.calls rỗng) — dò máy chỉ khi có thẻ cần máy.
# Chạy offline và kín: adb là stub trên PATH, HOME tạm (denylist thật của máy không lọt vào); runner, planner, status chạy từ
# một repo giả có bản chép của .claude/bin và proof-capture.py (không đọc .agents/devkit hay .adb-denylist của checkout thật).
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-needs-device.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/home" "$TMP/repo/.claude/bin" "$TMP/repo/.agents/devkit/bin" "$TMP/nokit" "$TMP/repo2/universal-agent-devkit/bin"
cp "$ROOT"/.claude/bin/super-board-* "$TMP/repo/.claude/bin/"
RUNNER="$TMP/repo/.claude/bin/super-board-run.sh"
HELPER="$TMP/repo/.claude/bin/super-board-device-online.py"
export HOME="$TMP/home"
unset ADB_DENY_SERIALS PROOF_ADB
export ADB_CALLS="$TMP/adb.calls"
cat > "$TMP/bin/adb" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$ADB_CALLS"
[ "${1:-}" = devices ] || exit 1
printf 'List of devices attached\n'
[ -z "${STUB_ADB_OUT:-}" ] || printf '%b\n' "$STUB_ADB_OUT"
SH
chmod +x "$TMP/bin/adb"
export PATH="$TMP/bin:$PATH"
cp "$ROOT/universal-agent-devkit/bin/proof-capture.py" "$TMP/repo/.agents/devkit/bin/"
cp "$ROOT/universal-agent-devkit/bin/proof-capture.py" "$TMP/repo2/universal-agent-devkit/bin/"
REAL='R58N1234567\tdevice'

# ── 0. helper
dev() { STUB_ADB_OUT="$1" python3 "$HELPER" --repo "${2:-$TMP/repo}" > "$TMP/dev.out" 2>&1; echo $?; }
[ "$(dev '')" = 1 ] && ok "helper: no device listed → none" || fail "helper empty: $(cat "$TMP/dev.out")"
[ "$(dev "$REAL")" = 0 ] && ok "helper: a real device in state device → online" || fail "helper real: $(cat "$TMP/dev.out")"
[ "$(dev 'R58N1234567\tunauthorized\nZY22ABCDEF\toffline')" = 1 ] && ok "helper: unauthorized / offline do not count" \
  || fail "helper unauthorized/offline: $(cat "$TMP/dev.out")"
[ "$(dev 'emulator-5554\tdevice')" = 1 ] && ok "helper: an emulator is not a real device" || fail "helper emulator: $(cat "$TMP/dev.out")"
[ "$(dev '127.0.0.1:5555\tdevice')" = 1 ] && ok "helper: an AVD connected over loopback is not a real device" || fail "helper loopback: $(cat "$TMP/dev.out")"
[ "$(ADB_DENY_SERIALS=R58N1234567 dev "$REAL")" = 1 ] && ok "helper: a serial in ADB_DENY_SERIALS does not count" \
  || fail "helper env denylist: $(cat "$TMP/dev.out")"
printf '# chủ xe\nR58N1234567\n' > "$TMP/repo/.adb-denylist"
[ "$(dev "$REAL")" = 1 ] && ok "helper: a serial in <repo>/.adb-denylist does not count" || fail "helper repo denylist: $(cat "$TMP/dev.out")"
rm -f "$TMP/repo/.adb-denylist"
mkdir -p "$HOME/.config/universal-agent-devkit"; printf 'R58N1234567\n' > "$HOME/.config/universal-agent-devkit/adb-denylist"
[ "$(dev "$REAL")" = 1 ] && ok "helper: a serial in ~/.config/universal-agent-devkit/adb-denylist does not count" \
  || fail "helper home denylist: $(cat "$TMP/dev.out")"
rm -f "$HOME/.config/universal-agent-devkit/adb-denylist"
[ "$(PROOF_ADB="$TMP/no-such-adb" dev "$REAL")" = 1 ] && grep -qi 'adb' "$TMP/dev.out" \
  && ok "helper: adb missing → none, and it says so" || fail "helper adb missing: $(cat "$TMP/dev.out")"
[ "$(dev "$REAL" "$TMP/nokit")" = 1 ] && grep -qi 'devkit' "$TMP/dev.out" \
  && ok "helper: no DevKit to read the rules from → none, and it says so" || fail "helper no kit: $(cat "$TMP/dev.out")"
[ "$(dev "$REAL" "$TMP/repo2")" = 0 ] && ok "helper: finds the DevKit as universal-agent-devkit too (no .agents/devkit link)" \
  || fail "helper kit fallback: $(cat "$TMP/dev.out")"

ITEMS='{"items":[
 {"id":"I50","status":"Ready","labels":["qa","needs-device"],"content":{"type":"Issue","number":50,"title":"FPS on a phone","assignees":[]}},
 {"id":"I51","status":"Ready","labels":["feature","needs-device"],"content":{"type":"Issue","number":51,"title":"build first","assignees":[]}},
 {"id":"I52","status":"QA","content":{"type":"Issue","number":52,"title":"built, QA on a phone","assignees":[],"labels":[{"name":"Needs-Device"}]}},
 {"id":"I53","status":"QA","labels":["needs-you"],"content":{"type":"Issue","number":53,"title":"resumed","assignees":[]}},
 {"id":"I54","status":"Review","labels":["qa","needs-device"],"content":{"type":"Issue","number":54,"title":"in review","assignees":[]}},
 {"id":"I55","status":"QA","labels":["bug"],"content":{"type":"Issue","number":55,"title":"plain QA","assignees":[]}}]}'
PLAIN='{"items":[
 {"id":"I60","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":60,"title":"plain","assignees":[]}},
 {"id":"I61","status":"QA","labels":["qa"],"content":{"type":"Issue","number":61,"title":"plain qa","assignees":[]}}]}'

# ── 1. runner
runner_pick() {   # $1 = items JSON, $2 = adb output; from a folder with no DevKit: the helper must find its own checkout
  ( cd "$TMP/nokit" && SB_LIB_ONLY=1 . "$RUNNER" || exit 99
    set +e
    log() { echo "LOG $*"; }; issue_locked() { return 1; }; issue_is_open() { return 0; }; early_backoff() { return 1; }
    INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
    PROJECT_ITEMS_JSON="$1"
    export STUB_ADB_OUT="$2"
    count_board; echo "counts=$READY,$QA,$WAITING"   # what the tick dispatches from and exits on
    top_card_in_column "Ready"; echo "ready=$TOP_ISSUE"
    top_card_in_column "QA"; echo "qa=$TOP_ISSUE"
    top_card_in_column "Review"; echo "review=$TOP_ISSUE"
    echo "held=$(person_count Ready),$(person_count QA)"
  ) 2>&1
}
: > "$ADB_CALLS"
runner_pick "$ITEMS" '' > "$TMP/r0.out"
if grep -qx "ready=51" "$TMP/r0.out" && grep -qx "qa=53" "$TMP/r0.out" && grep -qx "review=54" "$TMP/r0.out" \
   && grep -qx "held=1,1" "$TMP/r0.out" && grep -qx "counts=1,2,2" "$TMP/r0.out"; then
  ok "runner, no real device: Ready qa #50 and QA #52 held (out of Ready/QA, in waiting); #51 goes to the Builder, needs-you QA #53 and Review #54 picked"
else
  fail "runner no device: $(tr '\n' ' ' < "$TMP/r0.out")"
fi
grep -q '^LOG .*#50.*#52\|^LOG .*#52.*#50' "$TMP/r0.out" && ok "runner: the hold is logged with the held cards" \
  || fail "runner hold log: $(grep '^LOG' "$TMP/r0.out" | tr '\n' ' ')"
runner_pick "$ITEMS" "$REAL" > "$TMP/r1.out"
grep -qx "ready=50" "$TMP/r1.out" && grep -qx "qa=52" "$TMP/r1.out" && grep -qx "held=0,0" "$TMP/r1.out" && grep -qx "counts=2,3,0" "$TMP/r1.out" \
  && ok "runner, real device online: #50 and #52 are picked again" || fail "runner device online: $(tr '\n' ' ' < "$TMP/r1.out")"
runner_pick "$ITEMS" 'emulator-5554\tdevice' > "$TMP/r2.out"
grep -qx "ready=51" "$TMP/r2.out" && grep -qx "held=1,1" "$TMP/r2.out" \
  && ok "runner: a running emulator does not release them" || fail "runner emulator: $(tr '\n' ' ' < "$TMP/r2.out")"
: > "$ADB_CALLS"
runner_pick "$PLAIN" '' > "$TMP/r3.out"
grep -qx "ready=60" "$TMP/r3.out" && grep -qx "qa=61" "$TMP/r3.out" && [ ! -s "$ADB_CALLS" ] \
  && ok "runner: no card needs a device → adb is not called" || fail "runner plain: $(tr '\n' ' ' < "$TMP/r3.out") adb: $(cat "$ADB_CALLS")"

# ── 2. planner, offline (--items, --deps)
printf '%s' "$ITEMS" > "$TMP/items.json"
printf '{"50":{"runnable":true,"parseable":true,"blockers":[]},"51":{"runnable":true,"parseable":true,"blockers":[]}}' > "$TMP/deps.json"
printf '{"project":{"owner":"x","number":1},"repo":{"path":".","remote":"https://github.com/x/y"},"verify_commands":["bash tests/check.sh"]}' > "$TMP/cfg.json"
plan() {   # $1 = adb output, $2 = items file
  (cd "$TMP/repo" && STUB_ADB_OUT="$1" SB_GITHUB_HALT_FILE="$TMP/halt.json" bash .claude/bin/super-board-wave-plan.sh \
     --config "$TMP/cfg.json" --items "$2" --deps "$TMP/deps.json" > "$TMP/plan.json" 2> "$TMP/plan.err"); echo $?
}
rc=$(plan '' "$TMP/items.json")
c=$(jq -c '[.cards[].number] | sort' "$TMP/plan.json" 2>/dev/null); w=$(jq -c '[.waiting[]?.number] | sort' "$TMP/plan.json" 2>/dev/null)
[ "$rc" = 0 ] && [ "$c" = "[51,53,54,55]" ] && ok "planner, no real device: #50 / #52 are not in the wave (#51 built, #53 #54 #55 in)" \
  || fail "planner cards: rc $rc $c $(head -c 300 "$TMP/plan.err")"
[ "$w" = "[50,52]" ] && [ "$(jq -r '[.waiting[] | select(.number == 52) | .why][0] // ""' "$TMP/plan.json")" != "" ] \
  && ok "planner: they are listed in waiting with a why" || fail "planner waiting: $(jq -c '.waiting' "$TMP/plan.json" 2>/dev/null)"
[ "$(head -c 1 "$TMP/plan.json")" = "{" ] && jq -e . "$TMP/plan.json" >/dev/null 2>&1 \
  && ok "planner: stdout stays one JSON document (the probe writes to stderr)" || fail "planner stdout: $(head -c 200 "$TMP/plan.json")"
rc=$(plan "$REAL" "$TMP/items.json")
[ "$rc" = 0 ] && [ "$(jq -c '[.cards[].number] | sort' "$TMP/plan.json")" = "[50,51,52,53,54,55]" ] \
  && [ "$(jq -c '.waiting' "$TMP/plan.json")" = "[]" ] && ok "planner, real device online: #50 and #52 are in the wave again" \
  || fail "planner device online: rc $rc $(jq -c '{c:[.cards[]?.number],w:.waiting}' "$TMP/plan.json" 2>/dev/null)"
printf '%s' "$PLAIN" > "$TMP/plain.json"; : > "$ADB_CALLS"
rc=$(plan '' "$TMP/plain.json")
[ "$rc" = 0 ] && [ ! -s "$ADB_CALLS" ] && ok "planner: no card needs a device → adb is not called" \
  || fail "planner plain: rc $rc adb: $(cat "$ADB_CALLS") $(head -c 200 "$TMP/plan.err")"

# ── 3. status: the waiting group
status_waiting() {   # $1 = adb output
  ( cd "$TMP/nokit" && STUB_ADB_OUT="$1" PYTHONDONTWRITEBYTECODE=1 python3 - "$TMP/repo/.claude/bin/super-board-status.py" 2>&1 ) <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sb_status", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
items = [
    {"number": 50, "title": "FPS on a phone", "labels": ["qa", "needs-device"], "status": "Ready"},
    {"number": 51, "title": "build first", "labels": ["feature", "needs-device"], "status": "Ready"},
    {"number": 52, "title": "built, QA on a phone", "labels": ["Needs-Device"], "status": "QA"},
    {"number": 54, "title": "in review", "labels": ["qa", "needs-device"], "status": "Review"},
    {"number": 56, "title": "store account", "labels": ["needs-you"], "status": "Blocked"},
]
nodev = m.no_real_device(items)
print("nodev=%s" % nodev)
print("waiting=" + ",".join(str(i["number"]) for i in m.waiting_on_person(items, no_device=nodev)))
PY
}
status_waiting '' > "$TMP/s0.out"
grep -qx "nodev=True" "$TMP/s0.out" && grep -qx "waiting=56,52,50" "$TMP/s0.out" \
  && ok "status, no real device: Ready qa #50 and QA #52 join Waiting on you (not #51 or Review #54)" \
  || fail "status no device: $(tr '\n' ' ' < "$TMP/s0.out")"
status_waiting "$REAL" > "$TMP/s1.out"
grep -qx "nodev=False" "$TMP/s1.out" && grep -qx "waiting=56" "$TMP/s1.out" \
  && ok "status, real device online: they are not waiting" || fail "status device online: $(tr '\n' ' ' < "$TMP/s1.out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_needs_device_skip: all passed" || { echo "❌ test_needs_device_skip: $FAILS failed"; exit 1; }
