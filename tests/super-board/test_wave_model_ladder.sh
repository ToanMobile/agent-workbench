#!/usr/bin/env bash
# Test #553: thang model của super-board-wave.js.
#  1. Tier medium (mặc định): model của thẻ high không yếu hơn model của thẻ medium
#     (undefined = theo model phiên, có thể là sonnet ⇒ coi là yếu nhất).
#  2. Tier low và high giữ nguyên: low = haiku/sonnet/opus, high = opus cho mọi thẻ.
#  3. Comment mô tả thang (dòng `//   <tier> (...): ...` ngay trên LADDERS) khớp giá trị LADDERS.
#  4. Tài liệu (SKILL.md, run-workflow.md) ghi thang medium khớp LADDERS.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WAVE="$ROOT/.claude/workflows/super-board-wave.js"
SKILL="$ROOT/.claude/skills/super-board/SKILL.md"
RUNWF="$ROOT/.claude/skills/super-board/references/run-workflow.md"
command -v node >/dev/null 2>&1 || { echo "✖ cần node để đọc LADDERS"; exit 1; }

node - "$WAVE" "$SKILL" "$RUNWF" <<'EOF'
const fs = require('fs')
const [wavePath, skillPath, runwfPath] = process.argv.slice(2)
const src = fs.readFileSync(wavePath, 'utf8')
let fails = 0
const ok = (m) => console.log(`✔ ${m}`)
const fail = (m) => { console.log(`✖ ${m}`); fails++ }

// Lấy đúng khối `const LADDERS = { ... }` (kết thúc ở dòng `}` đầu tiên ở cột 0) rồi tính giá trị.
const m = src.match(/^const LADDERS = \{[\s\S]*?^\}/m)
if (!m) { console.log('✖ không tìm thấy khối const LADDERS'); process.exit(1) }
const LADDERS = new Function(`${m[0]}; return LADDERS`)()
const RANK = { haiku: 1, sonnet: 2, opus: 3 }
const rank = (model) => RANK[model] || 0 // undefined/session = 0: có thể là sonnet, không bảo đảm gì
const show = (v) => (v === undefined ? 'session' : v)

// 1. Tier medium: high ≥ medium ≥ low (theo độ mạnh, undefined thua mọi model cụ thể).
const med = LADDERS.medium || {}
if (rank(med.high) >= rank(med.medium) && rank(med.high) > 0) ok(`medium tier: thẻ high = ${show(med.high)} không yếu hơn thẻ medium = ${show(med.medium)}`)
else fail(`medium tier: thẻ high = ${show(med.high)} yếu hơn (hoặc không bảo đảm bằng) thẻ medium = ${show(med.medium)}`)
if (rank(med.medium) >= rank(med.low)) ok('medium tier: thẻ medium không yếu hơn thẻ low')
else fail('medium tier: thẻ medium yếu hơn thẻ low')

// 2. Tier low và high giữ nguyên.
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)
same(LADDERS.low, { low: 'haiku', medium: 'sonnet', high: 'opus' }) ? ok('low tier giữ haiku/sonnet/opus') : fail(`low tier đổi: ${JSON.stringify(LADDERS.low)}`)
same(LADDERS.high, { low: 'opus', medium: 'opus', high: 'opus' }) ? ok('high tier giữ opus cho mọi thẻ') : fail(`high tier đổi: ${JSON.stringify(LADDERS.high)}`)

// 3. Comment ngay trên LADDERS: `//   <tier> (<flag>): a / b / c` hoặc `... : <model> for every card`.
const parseLadderText = (text) => {
  const every = text.match(/^(\w+) for every card/)
  if (every) return [every[1], every[1], every[1]]
  return text.split('/').map((s) => s.trim())
}
const head = src.slice(0, m.index).split('\n').slice(-12)
for (const tier of ['low', 'medium', 'high']) {
  const line = head.find((l) => new RegExp(`^//\\s+${tier}\\s+\\(`).test(l))
  if (!line) { fail(`comment thiếu dòng mô tả tier ${tier}`); continue }
  const said = parseLadderText(line.replace(/^\/\/\s+\w+\s+\([^)]*\):\s*/, '').trim())
  const want = ['low', 'medium', 'high'].map((c) => show(LADDERS[tier][c]))
  same(said, want) ? ok(`comment tier ${tier} khớp: ${want.join(' / ')}`) : fail(`comment tier ${tier} ghi ${said.join(' / ')}, LADDERS là ${want.join(' / ')}`)
}

// 4. Tài liệu ghi thang medium khớp LADDERS (dạng a/b/c).
const medText = ['low', 'medium', 'high'].map((c) => show(med[c])).join('/')
for (const [name, p] of [['SKILL.md', skillPath], ['run-workflow.md', runwfPath]]) {
  const doc = fs.readFileSync(p, 'utf8').replace(/\s*\n\s*/g, ' ')
  doc.includes(medText) ? ok(`${name} ghi thang medium ${medText}`) : fail(`${name} không ghi thang medium ${medText}`)
  if (doc.includes('sonnet/opus/session')) fail(`${name} còn ghi thang cũ sonnet/opus/session`)
}

if (fails) { console.log(`FAIL (${fails})`); process.exit(1) }
console.log('PASS')
EOF
