#!/usr/bin/env bash
# 19/10 (OCR batch trên PR #111): `super-board-post-merge-clean.sh --sweep` có mà không ai gọi — grep "post-merge-clean" trong
# .claude/{bin,workflows,skills,hooks} và universal-agent-devkit/{scripts,hooks} lúc đó chỉ ra merge gate (chế độ post) và một comment
# của scratch-config, nên worktree lane của thẻ đã merge không bao giờ được dọn trên máy thật. Test này kiểm:
#   R  runner: startup_reconcile gọi sweep (sau reap/adopt lock) với base của config; sweep lỗi không làm runner dừng (set -e)
#   W  wave workflow: lời gọi cuối của wave là một agent Cleanup chạy sweep, phase có trong meta; run halted thì không có lời gọi đó
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-sweep-wiring.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ── R. runner thật, chép cạnh một post-merge-clean giả (runner tìm script cạnh chính nó)
mkdir -p "$TMP/bin"
cp "$ROOT/.claude/bin/super-board-run.sh" "$TMP/bin/super-board-run.sh"
cat > "$TMP/bin/super-board-post-merge-clean.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$SWEEP_CALLS"
echo sweep >> "$SWEEP_ORDER"
exit "${SWEEP_RC:-0}"
SH
run_startup() {  # run_startup <sweep exit code>: startup_reconcile của runner thật, mọi bước GitHub thay bằng stub
  ( cd "$TMP" && SB_LIB_ONLY=1 . "$TMP/bin/super-board-run.sh" >/dev/null 2>&1 || exit 90
    reap_finished_locks() { echo reap >> "$TMP/order"; }
    adopt_live_locks() { echo adopt >> "$TMP/order"; }
    gh_rate_guard() { :; }
    fetch_project_items() { :; }
    reclaim_stranded_building() { echo reclaim >> "$TMP/order"; }
    log() { echo "$*" >> "$TMP/log"; }
    BASE_BRANCH=trunk-x RUN_MANIFEST="$TMP/manifest"
    SWEEP_RC=$1 startup_reconcile && echo "after" >> "$TMP/order" )
}
export SWEEP_CALLS="$TMP/sweep.calls" SWEEP_ORDER="$TMP/order"
wait_sweep() { local i=0; while [ "$i" -lt 100 ] && ! grep -q sweep "$TMP/order" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done; }   # chạy nền
: > "$TMP/order"; run_startup 0; rc=$?; wait_sweep
if [ "$rc" -eq 0 ] && grep -qx -- "--sweep . --base trunk-x" "$SWEEP_CALLS" 2>/dev/null; then
  ok "R1 startup_reconcile runs the sweep with the config's base branch"
else fail "R1 startup_reconcile did not run the sweep (rc $rc, calls: $(cat "$SWEEP_CALLS" 2>/dev/null))"; fi
case "$(tr '\n' ' ' < "$TMP/order")" in
  "reap adopt reclaim sweep after "|"reap adopt reclaim after sweep ") ok "R2 the sweep starts after the dead locks are reaped and the live ones adopted" ;;
  *) fail "R2 order: $(tr '\n' ' ' < "$TMP/order")" ;;
esac
: > "$TMP/order"; : > "$SWEEP_CALLS"; run_startup 7; rc=$?; wait_sweep
[ "$rc" -eq 0 ] && grep -q after "$TMP/order" && [ -s "$SWEEP_CALLS" ] \
  && ok "R3 a failing sweep never stops the runner (set -e)" || fail "R3 a failing sweep stopped startup_reconcile (rc $rc)"

# ── W. wave workflow thật trong node, agent/pipeline/log giả
WAVE="$ROOT/.claude/workflows/super-board-wave.js"
if ! command -v node >/dev/null 2>&1; then
  echo "skip W: node not found"
else
  cat > "$TMP/harness.js" <<'JS'
const fs = require('fs')
const [src, argsJson, preflight] = [fs.readFileSync(process.argv[2], 'utf8'), process.argv[3], process.argv[4]]
const calls = []
const agent = async (prompt, opts) => {
  calls.push({ phase: opts.phase, label: opts.label, model: opts.model, prompt })
  if (opts.phase === 'Pre-flight') return { verdicts: JSON.parse(argsJson).cards.map((c) => ({ number: c.number, verdict: preflight, detail: 'stub' })) }
  if (opts.phase === 'Classify') return { kind: 'bug', complexity: 'low' }
  if (opts.phase === 'Cleanup') { if (process.argv[5] === 'throw') throw new Error('cleanup agent failed'); return { detail: 'removed 0' } }
  return { status: 'failed', column: 'Ready', detail: 'stub lane' }
}
const pipeline = async (items, s1, s2) => { const out = []; for (const it of items) out.push(await s2(await s1(it), it)); return out }
const fn = new (Object.getPrototypeOf(async function () {}).constructor)('args', 'agent', 'pipeline', 'log',
  src.replace(/^export const meta/m, 'const meta') + '\n;')
const meta = new Function(src.replace(/^export const meta\s*=/m, 'return').split(/\n}\n/)[0] + '\n}')()
fn(argsJson, agent, pipeline, () => {}).then((r) => {
  console.log(JSON.stringify({ phases: meta.phases.map((p) => p.title), calls, halted: r.halted }))
}).catch((e) => { console.log(JSON.stringify({ error: String(e) })); process.exit(1) })
JS
  ARGS='{"configPath":".claude/super-board/configs/x.json","cards":[{"number":5,"status":"Ready","title":"t","lane":"build","labels":["bug"]}]}'
  node "$TMP/harness.js" "$WAVE" "$ARGS" proceed > "$TMP/wave.json" 2>"$TMP/wave.err"; rc=$?
  python3 - "$TMP/wave.json" <<'PY' > "$TMP/wave.check"; wrc=$?
import json, sys
d = json.load(open(sys.argv[1]))
cl = [c for c in d["calls"] if c["phase"] == "Cleanup"]
assert "error" not in d, d.get("error")
assert "Cleanup" in d["phases"], "no Cleanup phase in meta"
assert len(cl) == 1, f"{len(cl)} Cleanup calls"
assert d["calls"][-1]["phase"] == "Cleanup", "Cleanup is not the last call of the wave"
p = cl[0]["prompt"]
assert "bash .claude/bin/super-board-post-merge-clean.sh --sweep ." in p, p
assert ".claude/super-board/configs/x.json" in p, "base not read from the wave's config"
print("ok")
PY
  [ "$rc" -eq 0 ] && [ "$wrc" -eq 0 ] && ok "W1 a wave ends with one Cleanup agent running the sweep (phase declared in meta)" \
    || fail "W1 wave cleanup: rc=$rc $(cat "$TMP/wave.check" "$TMP/wave.err" 2>/dev/null | tail -3)"
  node "$TMP/harness.js" "$WAVE" "$ARGS" halted > "$TMP/wave2.json" 2>"$TMP/wave2.err"; rc=$?
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["halted"] is True; assert not [c for c in d["calls"] if c["phase"]=="Cleanup"]' \
    "$TMP/wave2.json" 2>/dev/null && [ "$rc" -eq 0 ] && ok "W2 a halted wave makes no Cleanup call (no more GitHub reads)" \
    || fail "W2 halted wave: rc=$rc $(head -c 300 "$TMP/wave2.json")"
  # W3 (OCR): bước dọn chỉ là phụ — agent Cleanup lỗi thì wave vẫn trả tóm tắt của mọi thẻ đã chạy
  node "$TMP/harness.js" "$WAVE" "$ARGS" proceed throw > "$TMP/wave3.json" 2>"$TMP/wave3.err"; rc=$?
  [ "$rc" -eq 0 ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "error" not in d and d["halted"] is False' "$TMP/wave3.json" 2>/dev/null \
    && ok "W3 a failing Cleanup agent never costs the wave its result" || fail "W3 Cleanup failure lost the wave result: rc=$rc $(head -c 300 "$TMP/wave3.json")"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_post_merge_sweep_wiring: all passed" || { echo "❌ test_post_merge_sweep_wiring: $FAILS failed"; exit 1; }
