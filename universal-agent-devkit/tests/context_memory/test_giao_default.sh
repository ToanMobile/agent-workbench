#!/usr/bin/env bash
# Regression test (user, 2026-10-14: "tôi muốn /giao có 1 cờ bật tắt mặc định, hiện tôi muốn nó là true: mỗi prompt đều mặc định bật /giao
# lên, khi nào tắt tôi sẽ false sau"). Before, the prompt hook added the `giao` skill only when the prompt said so ("giao cho", "antigravity").
# Now the flag `giaoDefault` of .antigravity-pm.json (global ~/.antigravity-pm.json, overridden by <project>/.antigravity-pm.json) decides:
#   1. absent -> as before (nothing added); true -> the hook adds the standing order only: no intent (OpenCodeReview 14/10: a real intent turns off
#      the noise filter of weak instinct matches and the GENERAL_TASK fallback on every chit-chat prompt) and no slot of the skill line
#   2. the project file wins over the global one, in both directions
#   3. a broken file or a value that is not a JSON boolean never turns it on, and the hook says so instead of staying silent
#   4. it reaches the real hook output (hooks/prompt_context.sh), and a slash command is still left alone
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*, no user config
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unset PROMPT_CONTEXT DEVKIT_ROOT PROMPT_DEDUPE DEVKIT_AGENT   # runner/host state (#573): another kit root, dedupe off, a bridged harness all change the hook output
mkdir -p "$TMP/home" "$TMP/tmpdir"
export HOME="$TMP/home" TMPDIR="$TMP/tmpdir" GIT_CONFIG_GLOBAL=/dev/null   # the hook and `git init` read HOME, TMPDIR and ~/.gitconfig
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/proj/.agents" "$TMP/global" && cd "$TMP/proj" || exit 1
git init -q .
export CLAUDE_PROJECT_DIR="$TMP/proj"
export ANTIGRAVITY_PM_GLOBAL_CONFIG="$TMP/global/.antigravity-pm.json"
P="cập nhật tài liệu hướng dẫn cài đặt cho dự án"
out() { printf '{"prompt":"%s","session_id":"s%s"}' "${1:-$P}" "$RANDOM$RANDOM" | bash "$HOOK" 2>&1; }   # a fresh session each call: the hook shows a context line once per session
setg() { printf '%s' "$1" > "$ANTIGRAVITY_PM_GLOBAL_CONFIG"; }
setp() { printf '%s' "$1" > "$TMP/proj/.antigravity-pm.json"; }
clear() { rm -f "$ANTIGRAVITY_PM_GLOBAL_CONFIG" "$TMP/proj/.antigravity-pm.json"; }
skill_line() { printf '%s' "$1" | grep -o 'Skill phù hợp: [^\\]*' | head -1; }

clear
o="$(out)"
printf '%s' "$o" | grep -q "GIAO MẶC ĐỊNH" && fail "1: no flag, yet the standing order is there" || ok "1: no flag -> nothing added (as before)"
printf '%s' "$o" | grep -q "DUAL_AGENT_DELEGATION" && fail "1: no flag, yet DUAL_AGENT_DELEGATION" || ok "  … and no DUAL_AGENT_DELEGATION"

setg '{"giaoDefault": true}'
o="$(out)"
printf '%s' "$o" | grep -q "GIAO MẶC ĐỊNH BẬT" && ok "1: global giaoDefault=true -> the standing order is added" || fail "1: true, no order: $o"
printf '%s' "$o" | grep -q "DUAL_AGENT_DELEGATION" && fail "  … the flag must not add a real intent (it flips the noise filter and the GENERAL_TASK fallback): $o" || ok "  … and no DUAL_AGENT_DELEGATION intent (an order, not a classification)"
# the flag takes no slot of the 5-skill line (INSTINCT-022: a skill added to a broad intent pushed others out)
PU="sửa lỗi hud bị vỡ layout trên màn hình chính"
on="$(skill_line "$(out "$PU")")"; clear; off="$(skill_line "$(out "$PU")")"; setg '{"giaoDefault": true}'
[ -n "$on" ] && [ "$on" = "$off" ] && ok "  … and the skill line is unchanged by the flag ($on)" || fail "  … the flag changed the skill line: on='$on' off='$off'"
printf '%s' "$o" | grep -q "câu hỏi" && ok "  … the order exempts a turn that changes nothing (a question is answered directly)" || fail "  … no exemption for questions"

setp '{"giaoDefault": false}'
o="$(out)"
printf '%s' "$o" | grep -q "GIAO MẶC ĐỊNH" && fail "2: project false must beat global true" || ok "2: project false overrides global true"
clear; setg '{"giaoDefault": false}'; setp '{"giaoDefault": true}'
printf '%s' "$(out)" | grep -q "GIAO MẶC ĐỊNH BẬT" && ok "2: project true overrides global false" || fail "2: project true lost to global false"

clear; setg '{"giaoDefault": "yes"}'
o="$(out)"
printf '%s' "$o" | grep -q "GIAO MẶC ĐỊNH BẬT" && fail "3: the string \"yes\" turned it on" || ok "3: a value that is not a JSON boolean never turns it on"
printf '%s' "$o" | grep -q "giaoDefault" && ok "  … and the hook says why (names the flag)" || fail "  … silent about the bad value: $o"
clear; setg '{"giaoDefault": tru'
o="$(out)"
printf '%s' "$o" | grep -q "GIAO MẶC ĐỊNH BẬT" && fail "3: a broken file turned it on" || ok "3: a broken JSON file never turns it on"
printf '%s' "$o" | grep -q "giaoDefault" && ok "  … and the hook says the file could not be read" || fail "  … silent about the broken file: $o"
[ -n "$o" ] && ok "  … and the hook still answers (no crash)" || fail "  … empty output on a broken file"

# 5: per-session dedupe (reviewer + OpenCodeReview 14/10): the order reaches a session ONCE; an identical hook text in the same session collapses to the
#    "như lượt trước" stub (the order stays in that session's context), and a NEW session gets it again. This documents the behaviour, it is not a bug.
clear; setg '{"giaoDefault": true}'
same() { printf '{"prompt":"%s","session_id":"fixed-s"}' "$P" | bash "$HOOK" 2>&1; }
a="$(same)"; b="$(same)"
printf '%s' "$a" | grep -q "GIAO MẶC ĐỊNH BẬT" && ok "5: the first prompt of a session carries the order" || fail "5: first prompt has no order: $a"
printf '%s' "$b" | grep -q "GIAO MẶC ĐỊNH BẬT" && fail "5: the order was repeated in the same session (dedupe changed?)" || ok "  … the same text again in that session collapses to a stub (the order stays in context)"
printf '%s' "$(out)" | grep -q "GIAO MẶC ĐỊNH BẬT" && ok "  … and a NEW session gets the order again" || fail "  … new session lost the order"
# 5b: a DIFFERENT prompt later in the same session does not repeat it either (2026-10-25 audit: a 50-prompt interactive session got the
#     ~370-byte order on every prompt, 19.6 KB, because the whole text differed and only identical text collapsed).
#     The prompt must change the hook text (its own "Loại việc"), or the identical-text stub hides the repeat.
c="$(printf '{"prompt":"%s","session_id":"fixed-s"}' "giải quyết conflict khi merge nhánh release" | bash "$HOOK" 2>&1)"
printf '%s' "$c" | grep -q "MERGE_CONFLICT" || fail "5b: setup — the second prompt did not change the hook text: $c"
printf '%s' "$c" | grep -q "GIAO MẶC ĐỊNH BẬT" && fail "5b: the order was repeated for another prompt of the same session" \
  || ok "5b: another prompt of the same session does not repeat the order"
# 5c (OCR 25/10): a chit-chat prompt whose only hook text was the order, asked again after another prompt of the same session, left a
#    bare "[DevKit] Ngữ cảnh tự động …:" header with nothing under it once the order was deduped: no text at all then.
s5c() { printf '{"prompt":"%s","session_id":"s5c"}' "$1" | bash "$HOOK" 2>&1; }
CHAT="bạn khỏe không hôm nay thế nào"
c1="$(s5c "$CHAT")"; s5c "giải quyết conflict khi merge nhánh release" >/dev/null; c3="$(s5c "$CHAT")"
printf '%s' "$c1" | grep -q "GIAO MẶC ĐỊNH BẬT" || fail "5c: setup — the chit-chat prompt carries no order the first time: $c1"
[ -z "$c3" ] && ok "5c: the same chit-chat prompt later in the session, its order already sent → no text (no bare header)" \
  || fail "5c: a bare header with nothing under it: '$c3'"
c4="$(s5c "sửa lỗi nút Lưu bị bấm hai lần")"
printf '%s' "$c4" | grep -q "Ngữ cảnh tự động" && printf '%s' "$c4" | grep -q "BUG_FIX" \
  && ok "  … while a prompt with its own context in that session still gets its header and lines (control)" || fail "  … control lost: '$c4'"

# 3b: the PROJECT file wins even when it is the broken one (OpenCodeReview + reviewer 14/10: a typo there used to fall through to a global true,
#     so delegation was ON while the notice said "coi như false")
clear; setg '{"giaoDefault": true}'; setp '{"giaoDefault": tru'
o="$(out)"
printf '%s' "$o" | grep -q "GIAO MẶC ĐỊNH BẬT" && fail "3b: a broken project file fell through to the global true" || ok "3b: broken project file + global true -> OFF (the project file wins, fail closed)"
printf '%s' "$o" | grep -q "giaoDefault" && ok "  … and the notice says so" || fail "  … silent: $o"
clear; setg '{"giaoDefault": true}'; setp '{"giaoDefault": "false"}'
printf '%s' "$(out)" | grep -q "GIAO MẶC ĐỊNH BẬT" && fail "3b: project \"false\" (a string) + global true turned it on" || ok "3b: project value that is not a boolean + global true -> OFF"
clear; setg '{"giaoDefault": true}'; setp '[]'
o="$(out)"
printf '%s' "$o" | grep -q "GIAO MẶC ĐỊNH BẬT" && fail "3b: a project file that is valid JSON but not an object ([]) fell through to the global true" || ok "3b: project file [] (not an object) + global true -> OFF"
printf '%s' "$o" | grep -q "giaoDefault" && ok "  … and the notice says so" || fail "  … silent: $o"
clear; setg '{"giaoDefault": true}'; setp '{"projectName": "x"}'
printf '%s' "$(out)" | grep -q "GIAO MẶC ĐỊNH BẬT" && ok "3b: a valid project file WITHOUT the key still lets the global true through" || fail "3b: project file without the key blocked the global true"

clear; setg '{"giaoDefault": true}'
[ -z "$(printf '{"prompt":"/giao tạo task mới","session_id":"t"}' | bash "$HOOK" 2>&1)" ] && ok "4: a slash command is still left alone" || fail "4: the hook answered a slash command"

# 7: a super-board lane worker never hands its card to Antigravity (2026-10-25 audit: the order reached 759 of 760 lane sessions).
#    The lane's first prompt is the runner's opener + card JSON (quotes inside: the payload is built with json.dumps). The flag is
#    still on, so the user's own prompt in the same project keeps the order (control).
lane_out() {
  python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": sys.argv[2]}))' "$1" "s7-$RANDOM$RANDOM" | bash "$HOOK" 2>&1; }
LANE="First operation: run .claude/bin/super-board-skills-ready.py --root '/repo' --host claude --cards - --lane 'build' --hydrate with [{\"number\":416,\"status\":\"Ready\",\"title\":\"Sửa tài liệu cài đặt\",\"labels\":[\"bug\"],\"lane\":\"build\"}] as stdin. Halt on exit 10 before worktree creation or lifecycle writes; preserve claims and approval evidence. Run super-build on issue #416 for super-board run. Check --check before any GitHub write, migration, or merge."
o7="$(lane_out "$LANE")"
printf '%s' "$o7" | grep -q "GIAO MẶC ĐỊNH BẬT" && fail "7: a super-board lane got the giao order: $o7" || ok "7: a super-board lane opener gets no giao order"
printf '%s' "$o7" | grep -q "Antigravity" && fail "7: a super-board lane was told to call Antigravity: $o7" || ok "  … nor the Claude ↔ Antigravity review order ('migration' is the harness's word)"
printf '%s' "$(lane_out "$P")" | grep -q "GIAO MẶC ĐỊNH BẬT" && ok "  … while a user prompt in the same project keeps the order (control)" || fail "  … control: the user prompt lost the order"
# 7b: the Codex lane (.claude/bin/super-board-codex-lane.sh; fixture tests/lib/codex_lane_prompt.py) gets no order either, while a prompt
#     that only mentions a Codex lane keeps it.
o7b="$(lane_out "$(python3 "$DEVKIT_DIR/tests/lib/codex_lane_prompt.py" "Sửa tài liệu cài đặt" "Cập nhật mục cài đặt trong README.")")"
printf '%s' "$o7b" | grep -q "GIAO MẶC ĐỊNH BẬT" && fail "7b: a Codex lane got the giao order: $o7b" || ok "7b: a Codex lane opener gets no giao order"
printf '%s' "$(lane_out "cập nhật tài liệu cài đặt cho Codex lane worker của dự án")" | grep -q "GIAO MẶC ĐỊNH BẬT" \
  && ok "  … while a user prompt mentioning a Codex lane keeps the order (control)" || fail "  … control: the Codex-mention prompt lost the order"

# 6: the "no user config" pin of tests/lib/clean_git_env.sh itself (OpenCodeReview 14/10, workflow-improvements I.4 #1). It was
#    ${TMPDIR:-/tmp}/agpm-test-no-global-config/.antigravity-pm.json: a guessable path in a shared /tmp that another user, or an old run,
#    could create with giaoDefault: true, and then every test that sources the lib was steered. The plant is tried in a PRIVATE TMPDIR
#    (a child shell sources the lib again), never in the shared one other test runs use right now.
clear
priv="$TMP/shared-tmp"; mkdir -p "$priv"
o6="$(env -u ANTIGRAVITY_PM_GLOBAL_CONFIG TMPDIR="$priv" bash -c '
  . "$1/tests/lib/clean_git_env.sh"
  echo "PIN=${ANTIGRAVITY_PM_GLOBAL_CONFIG:-}"
  { mkdir -p "$(dirname "$ANTIGRAVITY_PM_GLOBAL_CONFIG")" && printf "{\"giaoDefault\": true}" > "$ANTIGRAVITY_PM_GLOBAL_CONFIG"; } 2>/dev/null \
    && echo "PLANTED $ANTIGRAVITY_PM_GLOBAL_CONFIG"
  hook() { printf "{\"prompt\":\"%s\",\"session_id\":\"s6-%s\"}" "$2" "$RANDOM$RANDOM" | bash "$3" 2>&1; }
  echo "== LIB"; hook "$@"
  printf "{\"giaoDefault\": true}" > "$TMPDIR/control.json"
  echo "== CONTROL"; ANTIGRAVITY_PM_GLOBAL_CONFIG="$TMPDIR/control.json" hook "$@"' _ "$DEVKIT_DIR" "$P" "$HOOK")"
lib6="$(printf '%s\n' "$o6" | sed -n '/^== LIB$/,/^== CONTROL$/p')"
ctl6="$(printf '%s\n' "$o6" | sed -n '/^== CONTROL$/,$p')"
# the lib must set the pin at all: unset, the child would plant nothing (mkdir -p ., > "" fails) and its hook would read the host's own
# ~/.antigravity-pm.json, so the two checks below would pass on any host without one (principal-code-reviewer 14/10)
pin6="$(printf '%s\n' "$o6" | sed -n 's/^PIN=//p' | head -1)"
case "$pin6" in
  /*) ok "6: the lib pins the user config to an absolute path ($pin6)" ;;
  *) fail "6: the lib does not pin the user config (got '$pin6'): the checks below would pass on any host without ~/.antigravity-pm.json" ;;
esac
printf '%s' "$o6" | grep -q '^PLANTED ' && fail "6: a file could be planted where the lib points the user config: $(printf '%s' "$o6" | grep '^PLANTED ' | head -1)" \
  || ok "6: the lib's no-user-config path can hold no file (nobody can plant one)"
printf '%s' "$lib6" | grep -q "GIAO MẶC ĐỊNH BẬT" && fail "  … and the planted giaoDefault=true steered the hook" || ok "  … so no planted giaoDefault=true reaches the hook"
printf '%s' "$ctl6" | grep -q "GIAO MẶC ĐỊNH BẬT" && ok "  … (control: the same child shell shows the order for a flag file it does own, so the check above is not empty)" \
  || fail "  … control: the child shell shows no order even for its own giaoDefault=true file: the check above proves nothing ($ctl6)"

[ "$FAILS" -eq 0 ] && echo "giaoDefault flag: all checks passed" || { echo "giaoDefault flag: $FAILS FAILED"; exit 1; }
