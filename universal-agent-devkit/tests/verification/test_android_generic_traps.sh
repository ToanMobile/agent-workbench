#!/usr/bin/env bash
# docs/workflow-improvements.md I.3 P10: two traps that are not project-specific must live in the android profile's instincts.md, in that
# file's own entry format (### [INSTINCT-AND-NN] ...): (1) overlapping touch targets are decided nearest-wins, never first-in-list;
# (2) no windowInsetsPadding inside an area the Scaffold already padded. And the upstream path (`agent-kit learn --generic` -> upstream-queue.md
# -> `instincts.py promote`) must reach that very file: proven here on a COPY of the real profile file in a temp kit (the real file, the project's
# .agents/instincts.md and its upstream queue are never written).
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DEVKIT_DIR/tests/lib/clean_git_env.sh"
REAL="$DEVKIT_DIR/profiles/android/instincts.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# ── A. the two entries are in the real profile file, in its format ──
entry() { awk -v id="$1" '$0 ~ "^### \\[" id "\\]" {on=1; print; next} on && /^---[[:space:]]*$/ {exit} on {print}' "$REAL"; }
E13="$(entry INSTINCT-AND-13)"; E14="$(entry INSTINCT-AND-14)"
[ -n "$E13" ] && ok "INSTINCT-AND-13 is in profiles/android/instincts.md" || fail "INSTINCT-AND-13 is missing from profiles/android/instincts.md"
[ -n "$E14" ] && ok "INSTINCT-AND-14 is in profiles/android/instincts.md" || fail "INSTINCT-AND-14 is missing from profiles/android/instincts.md"
for pair in "13|$E13" "14|$E14"; do
  n="${pair%%|*}"; body="${pair#*|}"; miss=""
  for lab in 'Hiện tượng lỗi' 'Nguyên nhân gốc rễ' 'Quy tắc bắt buộc' 'Kiểm tra tự động'; do
    printf '%s\n' "$body" | grep -q -- "^- \*\*$lab:\*\*" || miss="$miss [$lab]"
  done
  [ -z "$miss" ] && ok "AND-$n has the four fields of the existing entries" || fail "AND-$n lacks fields:$miss"
done
printf '%s\n' "$E13" | grep -qi 'nearest' && printf '%s\n' "$E13" | grep -qiE 'first|đầu tiên|thứ tự' \
  && ok "AND-13 says nearest-wins and names the first-in-list mistake" || fail "AND-13 does not say nearest-wins vs first-in-list"
printf '%s\n' "$E14" | grep -q 'windowInsetsPadding' && printf '%s\n' "$E14" | grep -q 'Scaffold' && printf '%s\n' "$E14" | grep -q 'innerPadding' && printf '%s\n' "$E14" | grep -q 'consumeWindowInsets' \
  && ok "AND-14 names windowInsetsPadding, Scaffold, innerPadding and consumeWindowInsets" || fail "AND-14 lacks windowInsetsPadding / Scaffold / innerPadding / consumeWindowInsets"
# the new entries are the only ones with their ids, and sit in section 1 (before the 'Nhật Ký Bẫy Mã Nguồn Bổ Sung' section)
c13="$(grep -c '^### \[INSTINCT-AND-13\]' "$REAL")"; c14="$(grep -c '^### \[INSTINCT-AND-14\]' "$REAL")"
l14="$(grep -n '^### \[INSTINCT-AND-14\]' "$REAL" | head -1 | cut -d: -f1)"; lsec="$(grep -n '^## 2\. ' "$REAL" | head -1 | cut -d: -f1)"
[ "$c13" = 1 ] && [ "$c14" = 1 ] && [ -n "$l14" ] && [ -n "$lsec" ] && [ "$l14" -lt "$lsec" ] \
  && ok "each id once, both before section 2" || fail "ids not unique or not in section 1 (13:$c13 14:$c14 line14=${l14:-none} section2=${lsec:-none})"
perl -0777 -ne 'exit(/---\s*\n\s*---/ ? 0 : 1)' "$REAL" && fail "the profile file has a double separator" || ok "no double separator in the profile file"

# ── B. the upstream path reaches the profile file (on a copy) ──
mkdir -p "$TMP/kit/profiles/android" "$TMP/proj/.agents/local"
cp "$REAL" "$TMP/kit/profiles/android/instincts.md"
ln -s "$DEVKIT_DIR/scripts" "$TMP/kit/scripts"; ln -s "$DEVKIT_DIR/templates" "$TMP/kit/templates"
printf '# Proj Instincts\n' > "$TMP/proj/.agents/instincts.md"
export CLAUDE_PROJECT_DIR="$TMP/proj"
REAL_KIT="$DEVKIT_DIR"; export DEVKIT_ROOT="$TMP/kit"

T13="$(printf '%s\n' "$E13" | head -1 | sed -E 's/^### \[[^]]*\] //')"
"$REAL_KIT/bin/agent-kit" learn "A brand new generic android trap" --cause C --rule R --symptom S --generic >/dev/null 2>&1
"$REAL_KIT/bin/agent-kit" learn "$T13" --cause C --rule R --symptom S --generic --force >/dev/null 2>&1
Q="$TMP/proj/.agents/local/upstream-queue.md"
grep -q 'A brand new generic android trap' "$Q" 2>/dev/null && ok "agent-kit learn --generic queued the new trap in upstream-queue.md" || fail "learn --generic did not queue the new trap"

python3 -I "$REAL_KIT/bin/instincts.py" promote --from "$TMP/proj" --profile android --kit "$TMP/kit" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "promote --profile android exits 0" || fail "promote exited $rc"
P="$TMP/kit/profiles/android/instincts.md"
grep -qE '^### \[INSTINCT-006\] A brand new generic android trap' "$P" \
  && ok "the new trap landed in profiles/android/instincts.md with the next numbered id (006; the AND-NN family is left alone)" || fail "the new trap is not in the profile file as INSTINCT-006"
n="$(grep -cF -- "] $T13" "$P")"
[ -n "$T13" ] && [ "$n" = 1 ] && ok "queueing AND-13's own title does not duplicate it (promote only marks it)" || fail "AND-13's title appears $n times after promote (want 1)"
m="$(grep -c '\*\*promoted:\*\* android' "$Q" 2>/dev/null)"
[ "$m" = 2 ] && ok "both queue entries are marked promoted to android" || fail "promoted markers: ${m:-0} (want 2)"

[ "$FAILS" -eq 0 ] && echo "✅ test_android_generic_traps: all passed" || { echo "❌ test_android_generic_traps: $FAILS failed"; exit 1; }
