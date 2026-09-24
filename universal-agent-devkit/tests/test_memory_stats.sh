#!/usr/bin/env bash
# Regression test: failure-memory recall on real prompts.
#  - the prompt hook logs every prompt it handled to .claude/audit-gate/surfaced.jsonl
#    ({ts, session, prompt_sha1, instinct_ids, instinct_refs}) and, when project-rule
#    sections matched, a second line with rule_sections; SURFACED_LOG=0 off; the prompt text
#    itself is never logged (only its sha1)
#  - scripts/memory_stats.py <project>: replays the user's real prompts from the project's
#    Claude transcripts (~/.claude/projects/<slug>/*.jsonl — typed prompts only: no slash
#    commands, no <wrapped> messages, no sidechains) through the CURRENT hook, read-only
#    (no REPORTED row, no inbox write), and reports: % of prompts that got a trap or a rule,
#    the traps never surfaced, and — from what the hook really printed in those sessions —
#    how often a surfaced trap was then read (Read of that instincts.md range, or sed -n a,b)
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"; STATS="$DEVKIT_DIR/scripts/memory_stats.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset PROMPT_CONTEXT SURFACED_LOG

P="$TMP/proj"; mkdir -p "$P/.agents" "$P/src"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
cat > .agents/instincts.md <<'EOF'
# Instincts

### [INSTINCT-001] Crash khi xoay màn hình mất trạng thái ViewModel
- **Hiện tượng lỗi:** xoay màn hình làm crash, ViewModel mất state.
- **Quy tắc phòng ngừa:** SavedStateHandle.

### [INSTINCT-002] Token refresh chạy song song hai lần
- **Hiện tượng lỗi:** hai request refresh token cùng lúc, đăng xuất người dùng.
- **Quy tắc phòng ngừa:** single-flight mutex.

### [INSTINCT-003] Bluetooth ngắt khi đổi bài hát
- **Hiện tượng lỗi:** bluetooth mất kết nối khi đổi bài.
- **Quy tắc phòng ngừa:** giữ A2DP session.
EOF
printf '{"rules":[]}' > .agents/regression_matrix.active.json
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"

# ── (a) the live log ────────────────────────────────────────────────────────
python3 -c 'import json; print(json.dumps({"prompt": "app bị crash khi xoay màn hình, ViewModel mất trạng thái", "session_id": "live1"}))' \
  | bash "$HOOK" > "$TMP/out1"
L="$P/.claude/audit-gate/surfaced.jsonl"
[ -f "$L" ] && python3 -c "
import json; r=[json.loads(l) for l in open('$L')][-1]
assert r['session']=='live1' and 'INSTINCT-001' in r['instinct_ids'] and len(r['prompt_sha1'])==40, r" 2>/dev/null \
  && ok "surfaced.jsonl records the session, the prompt sha1 and the trap ids" || fail "log: $(cat "$L" 2>/dev/null)"
grep -q "xoay màn hình" "$L" && fail "prompt text leaked into the log" || ok "the prompt text itself is not logged"
python3 -c 'import json; print(json.dumps({"prompt": "cảm ơn nhé, hẹn gặp lại", "session_id": "live1"}))' | bash "$HOOK" >/dev/null
[ "$(wc -l < "$L" | tr -d ' ')" = 2 ] && ok "a prompt with no trap is logged too (it is the denominator)" || fail "lines: $(wc -l < "$L")"
python3 -c 'import json; print(json.dumps({"prompt": "app bị crash khi xoay màn hình", "session_id": "live2"}))' | SURFACED_LOG=0 bash "$HOOK" >/dev/null
[ "$(wc -l < "$L" | tr -d ' ')" = 2 ] && ok "SURFACED_LOG=0 writes nothing" || fail "SURFACED_LOG=0 wrote"
mkdir -p .agents/context && printf "# Rules index\n- Bluetooth và đổi bài hát A2DP — \`sed -n '1,20p' .agents/local/rules/audio.md\`\n" > .agents/context/rules-index.md
python3 -c 'import json; print(json.dumps({"prompt": "bluetooth ngắt khi đổi bài hát A2DP", "session_id": "live3"}))' | bash "$HOOK" > "$TMP/out3"
grep -q "Luật dự án" "$TMP/out3" && python3 -c "
import json; rs=[json.loads(l) for l in open('$L') if json.loads(l).get('session')=='live3']
assert any(r.get('rule_sections') for r in rs), rs" 2>/dev/null && ok "matched project-rule sections are logged" || fail "rules not logged: $(cat "$TMP/out3") / $(tail -2 "$L")"

# ── (b) replay real prompts from transcripts ───────────────────────────────
export HOME="$TMP/home"
SLUG="$(printf '%s' "$P" | sed 's/[^A-Za-z0-9]/-/g')"
D="$HOME/.claude/projects/$SLUG"; mkdir -p "$D"
python3 - "$D/s1.jsonl" "$P" <<'PY'
import json, sys
out, P = sys.argv[1], sys.argv[2]
def user(t, **kw): return {"type": "user", "sessionId": "s1", "isSidechain": False, "message": {"role": "user", "content": t}, **kw}
def hook(text): return {"type": "attachment", "sessionId": "s1", "attachment": {"type": "hook_success", "hookEvent": "UserPromptSubmit", "content": text}}
def tool(name, inp): return {"type": "assistant", "sessionId": "s1", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "x", "name": name, "input": inp}]}}
recs = [
  user("app bị crash khi xoay màn hình, ViewModel mất trạng thái"),
  hook("[DevKit] …\n- Bẫy đã gặp: [INSTINCT-001] Crash khi xoay — xem `sed -n '3,15p' .agents/instincts.md`"),
  tool("Read", {"file_path": f"{P}/.agents/instincts.md", "offset": 3, "limit": 12}),
  user("token refresh bị gọi hai lần cùng lúc làm đăng xuất"),
  hook("[DevKit] …\n- Bẫy đã gặp: [INSTINCT-002] Token refresh — xem `sed -n '7,19p' .agents/instincts.md`"),
  user("/fixbugs something"),
  user("<cross-session-message from=x>crash xoay màn hình</cross-session-message>"),
  user("chào buổi sáng, hôm nay thế nào"),
  user("app bị crash khi xoay màn hình, ViewModel mất trạng thái"),
  {"type": "user", "sessionId": "s1", "isSidechain": True, "message": {"role": "user", "content": "bluetooth ngắt khi đổi bài hát"}},
  {"type": "user", "sessionId": "s1", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "x", "content": "bluetooth ngắt"}]}},
]
open(out, "w").write("\n".join(json.dumps(r, ensure_ascii=False) for r in recs) + "\n")
PY
before="$(cat "$P/.agents/regression_status.json" 2>/dev/null | shasum)"; log_before="$(wc -l < "$L" | tr -d ' ')"
out="$(python3 "$STATS" "$P" --json 2>&1)"
j() { printf '%s' "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
[ "$(j "d['prompts']")" = 3 ] && ok "typed prompts only: slash, wrapped, sidechain, tool results and repeats left out (3)" || fail "prompts: $(j "d['prompts']") — $out"
[ "$(j "d['with_trap']")" = 2 ] && [ "$(j "round(d['pct_trap_or_rule'])")" = 67 ] && ok "replay: 2 of 3 prompts get a trap (67%)" || fail "coverage: $out"
[ "$(j "d['never_surfaced']")" = "['INSTINCT-003']" ] && ok "never surfaced: INSTINCT-003" || fail "never: $(j "d['never_surfaced']")"
[ "$(j "d['surfaced_events']")" = 2 ] && [ "$(j "d['read_events']")" = 1 ] && ok "hook output in the sessions: 2 traps shown, 1 read afterwards (50%)" || fail "read rate: $out"
[ "$(cat "$P/.agents/regression_status.json" 2>/dev/null | shasum)" = "$before" ] && ok "replay is read-only (no REPORTED row written)" || fail "replay wrote the checklist"
[ "$(wc -l < "$L" | tr -d ' ')" = "$log_before" ] && ok "replay writes nothing to the recall log either" || fail "replay wrote surfaced.jsonl"
python3 "$STATS" "$P" | grep -q "%" && ok "human report prints the percentages" || fail "text report"
bash "$DEVKIT_DIR/bin/agent-kit" memory-stats "$P" --json | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && ok "agent-kit memory-stats" || fail "agent-kit memory-stats"

[ "$FAILS" -eq 0 ] && echo "✅ test_memory_stats: all passed" || { echo "❌ test_memory_stats: $FAILS failed"; exit 1; }
