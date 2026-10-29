#!/usr/bin/env bash
# Wave: verdict merge không được build, và thoát advanced @ Done (không Blocked).
# Cùng cách trích preflightGo / preflightExit với test_waiting_on_wave.sh. Offline.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

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
const run = (v) => { ctx.verdicts.clear(); ctx.verdicts.set(1, { number: 1, detail: 'folded', ...v }); return { go: ctx.go({ number: 1 }), exit: ctx.exit({ number: 1 }) } }
const out = []
const check = (cond, msg) => out.push((cond ? 'OK ' : 'FAIL ') + msg)
let r = run({ verdict: 'merge', mergeInto: 7 })
check(r.go === false, 'merge is not built (got ' + r.go + ')')
check(r.exit.status === 'advanced' && r.exit.column === 'Done', 'merge exits advanced@Done (got ' + JSON.stringify(r.exit) + ')')
check(r.exit.status !== 'blocked' && r.exit.column !== 'Blocked', 'merge is not Blocked')
r = run({ verdict: 'merge', column: 'Done', mergeInto: 7 })
check(r.go === false && r.exit.status === 'advanced' && r.exit.column === 'Done', 'merge with column Done stays advanced@Done')
r = run({ verdict: 'proceed' })
check(r.go === true, 'proceed still builds')
console.log(out.join('\n'))
JS
NODE_RC=$?
[ "$NODE_RC" -eq 0 ] || { fail "node harness exit $NODE_RC: $(tail -5 "$TMP/js.out")"; echo "FAIL $FAILS"; exit 1; }
while IFS= read -r line; do
  case "$line" in
    "OK "*) ok "wave.js: ${line#OK }" ;;
    "FAIL "*) fail "wave.js: ${line#FAIL }" ;;
    "") ;;
    *) fail "wave.js unexpected: $line" ;;
  esac
done < "$TMP/js.out"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL $FAILS"; exit 1; }
