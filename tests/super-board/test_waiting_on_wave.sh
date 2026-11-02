#!/usr/bin/env bash
# Test hồi quy #601 (backend workflow): thẻ chỉ chờ thẻ khác không vào Blocked.
#  1. planner (super-board-wave-plan.sh): thẻ Ready mang nhãn `waiting-on:#N` (không phân biệt hoa/thường, nhãn dạng chuỗi
#     hoặc {name}) không vào `cards`, mà nằm trong `waiting` kèm labels; mỗi phần tử `pending` có trường `needsYou`.
#  2. super-board-wave.js: `preflightGo` cho `sequence` đi tiếp chỉ khi blockedBy rỗng; `preflightExit` của `sequence` còn
#     blocker mở → status 'waiting', column 'Ready'; `hold` vẫn Blocked.
#  3. enum status `waiting` có mặt và cùng thứ tự ở STAGE_SCHEMA, schema codex-lane và danh sách hợp lệ của codex-wave.
# Chạy offline (jq + node có sẵn, không chạy cả workflow). Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-waiting-on.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ── 1. planner
ITEMS='{"items":[
 {"id":"I80","status":"Ready","labels":[{"name":"Waiting-On:#9"}],"content":{"type":"Issue","number":80,"title":"waits on 9","assignees":[]}},
 {"id":"I81","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":81,"title":"free","assignees":[]}},
 {"id":"I82","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":82,"title":"label on content","assignees":[],"labels":[{"name":"waiting-on:#10"}]}},
 {"id":"I83","status":"Blocked","labels":["bug"],"content":{"type":"Issue","number":83,"title":"blocked on 12","assignees":[]}}]}'
DEPS='{"80":{"runnable":true,"parseable":true,"blockers":[],"openBlockers":[],"humanGated":false},
 "81":{"runnable":true,"parseable":true,"blockers":[],"openBlockers":[],"humanGated":false},
 "82":{"runnable":true,"parseable":true,"blockers":[],"openBlockers":[],"humanGated":false},
 "83":{"runnable":false,"parseable":true,"blockers":[12],"openBlockers":[12],"humanGated":false,"needsYou":true}}'
printf '%s' "$ITEMS" > "$TMP/items.json"; printf '%s' "$DEPS" > "$TMP/deps.json"
printf '{"project":{"owner":"x","number":1},"repo":{"path":".","remote":"https://github.com/x/y"},"verify_commands":["bash tests/check.sh"]}' > "$TMP/cfg.json"
(cd "$ROOT" && SB_GITHUB_HALT_FILE="$TMP/halt.json" bash .claude/bin/super-board-wave-plan.sh --config "$TMP/cfg.json" \
   --items "$TMP/items.json" --deps "$TMP/deps.json" > "$TMP/plan.json" 2> "$TMP/plan.err")
CARDS="$(jq -c '[.cards[]?.number]' "$TMP/plan.json" 2>/dev/null)"
[ "$CARDS" = "[81]" ] && ok "planner: Ready cards labelled waiting-on:#N are not launched" \
  || fail "planner cards: $CARDS $(head -c 200 "$TMP/plan.err")"
W="$(jq -c '[.waiting[]? | select(.number == 80 or .number == 82) | .number] | sort' "$TMP/plan.json" 2>/dev/null)"
[ "$W" = "[80,82]" ] && ok "planner: waiting-on cards are listed in waiting" || fail "planner waiting: $(jq -c '.waiting' "$TMP/plan.json" 2>/dev/null)"
L="$(jq -c '[.waiting[]? | select(.number == 80) | .labels[]]' "$TMP/plan.json" 2>/dev/null)"
[ "$L" = '["waiting-on:#9"]' ] && ok "planner: waiting entry carries its labels" || fail "planner waiting labels: $L"
P="$(jq -c '[.pending[]? | {number, needsYou}]' "$TMP/plan.json" 2>/dev/null)"
[ "$P" = '[{"number":83,"needsYou":true}]' ] && ok "planner: pending carries needsYou" || fail "planner pending: $P"

# ── 2. super-board-wave.js: chỉ trích hai const preflightGo / preflightExit, eval trong vm với `verdicts` giả.
node - "$ROOT/.claude/workflows/super-board-wave.js" > "$TMP/js.out" 2>&1 <<'JS'
const fs = require('fs'), vm = require('vm')
const src = fs.readFileSync(process.argv[2], 'utf8')
const pick = (name) => {
  const m = src.match(new RegExp('^const ' + name + ' = \\(card\\) => \\{[\\s\\S]*?^\\}$', 'm'))
  if (!m) throw new Error('cannot find ' + name)
  return m[0]
}
const ctx = { verdicts: new Map() }
vm.createContext(ctx)
vm.runInContext(pick('preflightGo') + '\n' + pick('preflightExit') + '\nthis.go = preflightGo; this.exit = preflightExit', ctx)
const run = (v) => { ctx.verdicts.clear(); ctx.verdicts.set(1, { number: 1, detail: 'd', ...v }); return { go: ctx.go({ number: 1 }), exit: ctx.exit({ number: 1 }) } }
const out = []
const check = (cond, msg) => out.push((cond ? 'OK ' : 'FAIL ') + msg)
let r = run({ verdict: 'sequence', blockedBy: [9], column: 'Ready' })
check(r.go === false, 'sequence blockedBy [9] column Ready is not built (got ' + r.go + ')')
check(r.exit.status === 'waiting' && r.exit.column === 'Ready', 'sequence with open blocker exits waiting@Ready (got ' + JSON.stringify(r.exit) + ')')
r = run({ verdict: 'sequence', blockedBy: [9] })
check(r.go === false && r.exit.status === 'waiting' && r.exit.column === 'Ready', 'sequence blockedBy [9] no column → waiting@Ready (got ' + JSON.stringify(r) + ')')
r = run({ verdict: 'sequence', blockedBy: [], column: 'Ready' })
check(r.go === true, 'sequence blockedBy [] proceeds (got ' + r.go + ')')
r = run({ verdict: 'sequence', blockedBy: [] })
check(r.go === true, 'sequence blockedBy [] no column proceeds (got ' + r.go + ')')
// review F2: sequence thiếu mảng blockedBy không build, không có nhãn → failed (cổng zero-progress thấy), không phải waiting.
r = run({ verdict: 'sequence' })
check(r.go === false && r.exit.status === 'failed' && r.exit.column === 'Ready', 'sequence without blockedBy → failed@Ready, not waiting (got ' + JSON.stringify(r) + ')')
r = run({ verdict: 'hold', column: 'Blocked' })
check(r.go === false && r.exit.status === 'blocked' && r.exit.column === 'Blocked', 'hold stays blocked@Blocked (got ' + JSON.stringify(r.exit) + ')')
r = run({ verdict: 'hold' })
check(r.exit.status === 'blocked' && r.exit.column === 'Blocked', 'hold without column → blocked@Blocked (got ' + JSON.stringify(r.exit) + ')')
r = run({ verdict: 'proceed' })
check(r.go === true, 'proceed builds')
console.log(out.join('\n'))
JS
NODE_RC=$?
[ "$NODE_RC" -eq 0 ] || fail "node harness exit $NODE_RC: $(tail -5 "$TMP/js.out")"
while IFS= read -r line; do
  case "$line" in
    "OK "*) ok "wave.js: ${line#OK }" ;;
    "FAIL "*) fail "wave.js: ${line#FAIL }" ;;
  esac
done < "$TMP/js.out"

# ── 3. enum status 'waiting' đồng bộ ở cả 3 nơi: STAGE_SCHEMA (wave.js), schema codex-lane, danh sách hợp lệ codex-wave.
python3 - "$ROOT" > "$TMP/enum.out" 2>&1 <<'PY'
import ast, re, sys
root = sys.argv[1]
read = lambda p: open(f'{root}/{p}', encoding='utf-8').read()
out = []
m = re.search(r'^const STAGE_SCHEMA = \{.*?status: \{[^}]*enum: (\[[^\]]*\])', read('.claude/workflows/super-board-wave.js'), re.S | re.M)
stage = ast.literal_eval(m.group(1)) if m else []
out.append(('OK ' if 'waiting' in stage else 'FAIL ') + f'STAGE_SCHEMA status enum has waiting (got {stage})')
m = re.search(r"^properties = \{\s*'status': \{[^}]*'enum': (\[[^\]]*\])", read('.claude/bin/super-board-codex-lane.sh'), re.M)
lane = ast.literal_eval(m.group(1)) if m else []
out.append(('OK ' if 'waiting' in lane else 'FAIL ') + f'codex-lane schema status enum has waiting (got {lane})')
out.append(('OK ' if lane == stage else 'FAIL ') + 'codex-lane enum equals STAGE_SCHEMA enum (same order)')
m = re.search(r"result\.get\('status'\) not in\s*(\[[^\]]*\])", read('.claude/bin/super-board-codex-wave.sh'))
wave = ast.literal_eval(m.group(1)) if m else []
out.append(('OK ' if wave == stage else 'FAIL ') + f'codex-wave valid status list equals STAGE_SCHEMA enum (got {wave})')
print('\n'.join(out))
PY
while IFS= read -r line; do
  case "$line" in
    "OK "*) ok "enum: ${line#OK }" ;;
    "FAIL "*) fail "enum: ${line#FAIL }" ;;
    *) fail "enum harness: $line" ;;
  esac
done < "$TMP/enum.out"

echo "---"
[ "$FAILS" -eq 0 ] && { echo "PASS test_waiting_on_wave"; exit 0; } || { echo "FAIL test_waiting_on_wave ($FAILS)"; exit 1; }
