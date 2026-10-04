#!/usr/bin/env bash
# Regression test: hooks/prompt_context.sh does not re-inject, within one session, the
# lines it already injected (GeelyEx2, 5 days: 492 injections, the same ~700-char
# "Yêu cầu ngầm định" line re-sent 43.9k chars in total, every one re-read on each call).
#   - "Yêu cầu ngầm định", each "Bẫy đã gặp" and each "Skill phù hợp" line: first time only
#   - "Loại việc" and the RED→GREEN rule of a bug prompt: every time
#   - the whole injection identical to the previous one → a one-line reminder (+ RED→GREEN)
#   - a new session_id, or a compaction in the transcript → everything again
#   - no transcript (bridged agents) → everything again after 20 prompts
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

P="$TMP/proj"; mkdir -p "$P/.agents"
cd "$P" || { echo "✖ cd $P failed" >&2; exit 1; }
git init -q . && git config user.email t@t && git config user.name t
cat > .agents/instincts.md <<'EOF'
# Instincts

### [INSTINCT-001] Crash khi xoay màn hình mất trạng thái ViewModel
- **Hiện tượng lỗi:** xoay màn hình làm crash, ViewModel mất state.
- **Quy tắc phòng ngừa:** SavedStateHandle.

### [INSTINCT-003] Bluetooth ngắt khi đổi bài hát
- **Hiện tượng lỗi:** bluetooth mất kết nối khi đổi bài.
- **Quy tắc phòng ngừa:** giữ A2DP session.
EOF
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
: > "$TMP/tr1.jsonl"; : > "$TMP/tr2.jsonl"

# hook <out-file> <session|""> <transcript|""> <prompt>
hook() {
  python3 - "$2" "$3" "$4" > "$TMP/payload.json" <<'PY'
import json, sys
d = {"prompt": sys.argv[3]}
if sys.argv[1]:
    d["session_id"] = sys.argv[1]
if sys.argv[2]:
    d["transcript_path"] = sys.argv[2]
print(json.dumps(d, ensure_ascii=False))
PY
  bash "$HOOK" < "$TMP/payload.json" > "$1" 2>/dev/null
}
chars() { python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "$1"; }
has() { grep -qF -- "$2" "$1"; }
RED_LINE="ĐỎ trước khi sửa"
REPEATED="Yêu cầu ngầm định|Bẫy đã gặp|Skill phù hợp"

# ── three bug prompts of the same kind in one session ─────────────────────────
# Different words, same kind of work: the enricher builds the same lines for all three.
hook "$TMP/o1" s1 "$TMP/tr1.jsonl" "app bị crash khi xoay màn hình"
hook "$TMP/o2" s1 "$TMP/tr1.jsonl" "app vẫn crash khi xoay màn hình ở trang cài đặt"
hook "$TMP/o3" s1 "$TMP/tr1.jsonl" "sửa lỗi crash khi xoay màn hình, mất trạng thái"
c1="$(chars "$TMP/o1")"; c2="$(chars "$TMP/o2")"; c3="$(chars "$TMP/o3")"
echo "  chars: prompt1=$c1 prompt2=$c2 prompt3=$c3"
has "$TMP/o1" "Yêu cầu ngầm định" && has "$TMP/o1" "Bẫy đã gặp: [INSTINCT-001]" && has "$TMP/o1" "Skill phù hợp" \
  && ok "1st prompt: the full context" || fail "1st prompt incomplete: $(cat "$TMP/o1")"
for n in 2 3; do
  grep -qE "$REPEATED" "$TMP/o$n" && fail "prompt $n repeats lines already sent: $(grep -E "$REPEATED" "$TMP/o$n")" \
    || ok "prompt $n: implicit requirements, traps and skills not repeated"
  has "$TMP/o$n" "(ngữ cảnh DevKit như lượt trước)" && ok "prompt $n: same context as before → one-line reminder" \
    || fail "prompt $n: no reminder line: $(cat "$TMP/o$n")"
done
[ "$c2" -gt 0 ] && [ $((c2 * 4)) -lt "$c1" ] && [ $((c3 * 4)) -lt "$c1" ] \
  && ok "prompts 2 and 3 under a quarter of the 1st ($c2, $c3 < $c1/4)" || fail "not much shorter: $c1 → $c2, $c3"
for n in 1 2 3; do
  has "$TMP/o$n" "$RED_LINE" && ok "prompt $n: RED→GREEN rule present" || fail "prompt $n lost the RED→GREEN rule: $(cat "$TMP/o$n")"
done

# ── partly new context: only the unseen lines are added ─────────────────────────
# Same screen words as prompts 1-3 (a screen word brings the design skill, so the skill line is the same
# line), plus a network word: only the requirements line is new.
hook "$TMP/o3b" s1 "$TMP/tr1.jsonl" "app crash ViewModel mất trạng thái khi xoay màn hình, gọi API lỗi"
has "$TMP/o3b" "Loại việc" && ok "partly new context: the kind of work stays" || fail "lost 'Loại việc': $(cat "$TMP/o3b")"
has "$TMP/o3b" "$RED_LINE" && ok "partly new context: RED→GREEN rule present" || fail "RED lost: $(cat "$TMP/o3b")"
grep -qE "Bẫy đã gặp|Skill phù hợp" "$TMP/o3b" && fail "traps/skills already sent are repeated: $(cat "$TMP/o3b")" \
  || ok "partly new context: traps and skills already sent are not repeated"
has "$TMP/o3b" "Explicit Timeouts" && ok "partly new context: a different requirements line is shown" \
  || fail "new requirements line hidden: $(cat "$TMP/o3b")"

# ── a trap not yet shown in the session is still shown ─────────────────────────
hook "$TMP/o4" s1 "$TMP/tr1.jsonl" "sửa lỗi bluetooth ngắt khi đổi bài hát"
has "$TMP/o4" "Bẫy đã gặp: [INSTINCT-003]" && ok "a new trap in the session is shown" || fail "new trap hidden: $(cat "$TMP/o4")"
has "$TMP/o4" "$RED_LINE" && ok "new trap prompt: RED→GREEN rule present" || fail "RED lost: $(cat "$TMP/o4")"

# ── a new session gets everything again ─────────────────────────────────────────
hook "$TMP/o5" s2 "$TMP/tr2.jsonl" "app vẫn crash khi xoay màn hình ở trang cài đặt, ViewModel mất trạng thái"
has "$TMP/o5" "Yêu cầu ngầm định" && has "$TMP/o5" "Bẫy đã gặp: [INSTINCT-001]" && has "$TMP/o5" "Skill phù hợp" \
  && ok "new session_id: the full context again" || fail "new session suppressed: $(cat "$TMP/o5")"

# ── a compaction in the session resets it ───────────────────────────────────────
hook "$TMP/o6" s1 "$TMP/tr1.jsonl" "app vẫn crash khi xoay màn hình ở trang cài đặt, ViewModel mất trạng thái"
grep -qE "$REPEATED" "$TMP/o6" && fail "before compaction already full: $(cat "$TMP/o6")" || ok "same session before compaction: still suppressed"
printf '%s\n' '{"parentUuid":null,"isSidechain":false,"type":"system","subtype":"compact_boundary","content":"Conversation compacted","level":"info"}' >> "$TMP/tr1.jsonl"
hook "$TMP/o7" s1 "$TMP/tr1.jsonl" "app vẫn crash khi xoay màn hình ở trang cài đặt, ViewModel mất trạng thái"
has "$TMP/o7" "Yêu cầu ngầm định" && has "$TMP/o7" "Bẫy đã gặp: [INSTINCT-001]" && has "$TMP/o7" "Skill phù hợp" \
  && ok "after a compact_boundary: the full context again" || fail "after compaction still suppressed: $(cat "$TMP/o7")"
hook "$TMP/o8" s1 "$TMP/tr1.jsonl" "app vẫn crash khi xoay màn hình ở trang cài đặt, ViewModel mất trạng thái"
grep -qE "$REPEATED" "$TMP/o8" && fail "the same boundary reset twice: $(cat "$TMP/o8")" || ok "one compaction resets once"

# ── no transcript: the full context again after 20 prompts ───────────────────────
hook "$TMP/n1" s3 "" "app bị crash khi xoay màn hình, ViewModel mất trạng thái"
i=2; while [ "$i" -le 21 ]; do
  hook "$TMP/n$i" s3 "" "app bị crash khi xoay màn hình, ViewModel mất trạng thái lần $i"; i=$((i + 1))
done
grep -qE "$REPEATED" "$TMP/n2" && fail "no transcript: 2nd prompt not suppressed" || ok "no transcript: 2nd prompt suppressed"
grep -qE "$REPEATED" "$TMP/n20" && fail "no transcript: 20th prompt already full" || ok "no transcript: 20th prompt still suppressed"
has "$TMP/n21" "Yêu cầu ngầm định" && has "$TMP/n21" "Bẫy đã gặp: [INSTINCT-001]" \
  && ok "no transcript: 21st prompt full again (cap 20)" || fail "no transcript: 21st prompt still suppressed"

# ── no session_id: nothing to scope by, nothing suppressed ─────────────────────
hook "$TMP/x1" "" "" "app bị crash khi xoay màn hình, ViewModel mất trạng thái"
hook "$TMP/x2" "" "" "app bị crash khi xoay màn hình, ViewModel mất trạng thái"
has "$TMP/x2" "Yêu cầu ngầm định" && ok "no session_id: never suppressed" || fail "no session_id suppressed: $(cat "$TMP/x2")"

# ── the Zero-Slop mandate (any prompt on an app profile) is a block of lines, each sent once ─────
# dedupe_session drops repeated lines ONE BY ONE: a mandate glued onto the "Yêu cầu ngầm định" line would
# be re-sent whenever that line changes, and bullets on lines of their own would be re-sent for ever
# while their header is dropped (orphan bullets).
A="$TMP/app"; mkdir -p "$A/.agents" && printf '{"profile": "android"}\n' > "$A/.agents/active-profile.json"
: > "$TMP/tr3.jsonl"
CLAUDE_PROJECT_DIR="$A" hook "$TMP/z1" s9 "$TMP/tr3.jsonl" "sửa lại nút bấm trong màn hình inventory"
CLAUDE_PROJECT_DIR="$A" hook "$TMP/z2" s9 "$TMP/tr3.jsonl" "sửa lỗi lag khi cuộn danh sách trong màn hình inventory"
has "$TMP/z1" "ZERO-SLOP UI MANDATE" && [ "$(grep -c '^• ' "$TMP/z1")" = 6 ] \
  && ok "app profile, 1st prompt: the mandate (header + 6 bullets)" || fail "1st app prompt has no full mandate: $(cat "$TMP/z1")"
grep -qE "^• |ZERO-SLOP" "$TMP/z2" && fail "2nd prompt (different text) re-sends the mandate / orphan bullets: $(cat "$TMP/z2")" \
  || ok "app profile, 2nd prompt with other text: no mandate line repeated, no orphan bullet"
has "$TMP/z2" "Loại việc" && has "$TMP/z2" "$RED_LINE" && ok "2nd app prompt: kind of work and RED→GREEN rule stay" || fail "2nd app prompt lost lines: $(cat "$TMP/z2")"
printf '%s\n' '{"parentUuid":null,"isSidechain":false,"type":"system","subtype":"compact_boundary","content":"Conversation compacted","level":"info"}' >> "$TMP/tr3.jsonl"
CLAUDE_PROJECT_DIR="$A" hook "$TMP/z3" s9 "$TMP/tr3.jsonl" "sửa lỗi lag khi cuộn danh sách trong màn hình inventory"
has "$TMP/z3" "ZERO-SLOP UI MANDATE" && [ "$(grep -c '^• ' "$TMP/z3")" = 6 ] \
  && ok "after a compact_boundary: the whole mandate again" || fail "mandate not re-sent after compaction: $(cat "$TMP/z3")"
# The same when only the PROFILE opens the door (no UI word in either prompt, and the texts differ).
: > "$TMP/tr4.jsonl"
CLAUDE_PROJECT_DIR="$A" hook "$TMP/y1" s10 "$TMP/tr4.jsonl" "sửa null trong repository"
CLAUDE_PROJECT_DIR="$A" hook "$TMP/y2" s10 "$TMP/tr4.jsonl" "thêm trường vào repository lưu đơn hàng"
has "$TMP/y1" "ZERO-SLOP UI MANDATE" && [ "$(grep -c '^• ' "$TMP/y1")" = 6 ] \
  && ok "profile-only door, 1st prompt: the mandate" || fail "profile-only 1st prompt has no full mandate: $(cat "$TMP/y1")"
grep -qE "^• |ZERO-SLOP" "$TMP/y2" && fail "profile-only 2nd prompt re-sends the mandate: $(cat "$TMP/y2")" \
  || ok "profile-only door, 2nd prompt with other text: mandate not repeated"
has "$TMP/y2" "Loại việc: UI_INTERACTION, VISUAL_DESIGN" && ok "profile-only door: the kind of work is still named" || fail "profile-only 2nd prompt: $(cat "$TMP/y2")"

[ "$FAILS" -eq 0 ] && echo "✅ test_prompt_dedupe: all passed" || { echo "❌ test_prompt_dedupe: $FAILS failed"; exit 1; }
