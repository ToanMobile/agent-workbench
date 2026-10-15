#!/usr/bin/env bash
# docs/workflow-improvements.md I.3 P2: a layout/overlay/inset change is not "done" until a state matrix (one outcome line per cell,
# "overlaps" / "unchecked" marked) exists. Four defects shipped through green tests because nobody enumerated the cells.
# Pin: the lens text must be in the reviewer prompt, in the layout/responsive council (01) and the accessibility council (10), and in the
# device-QA skill; it must NOT be pasted into every council; the Android cell list stays in the android profile rules, not in the kit lens.
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

has_lens() { # <file>: every token of the lens is there (case-insensitive: the prompts are Vietnamese with English markers)
  local f="$1" t
  [ -f "$f" ] || return 1
  for t in 'state matrix' 'overlaps' 'unchecked' 'font scale 200%' 'RTL' 'cutout' 'orientation'; do
    grep -qiF -- "$t" "$f" || { echo "    ($(basename "$f") lacks: $t)"; return 1; }
  done
  return 0
}

for rel in agents/principal-code-reviewer.md agents/councils/01-subsystem-shared-flow.md agents/councils/10-standards-compliance-delivery.md skills/android-real-device-qa/SKILL.md; do
  has_lens "$DEVKIT_DIR/$rel" && ok "$rel carries the state-matrix lens" || fail "$rel is missing the state-matrix lens"
done

# the reviewer lists it as a lens to pick (step 3), not only as prose further down
grep -A3 -E '^3\. Chọn lens theo risk:' "$DEVKIT_DIR/agents/principal-code-reviewer.md" | grep -qi 'state matrix' \
  && ok "principal-code-reviewer step 3 lists the state-matrix lens" || fail "principal-code-reviewer step 3 does not list the state-matrix lens"

# not pasted into all ten councils: only the layout/responsive (01) and accessibility (10) ones
set_=""
for f in "$DEVKIT_DIR"/agents/councils/*.md; do
  grep -qiF 'state matrix' "$f" && set_="$set_ $(basename "$f" | cut -c1-2)"
done
[ "$set_" = " 01 10" ] && ok "only councils 01 and 10 carry the lens (not all ten)" || fail "councils with the lens:$set_ (want exactly: 01 10)"

# the Android-specific cell list lives in the profile rules, and the kit lens points there
grep -q 'compose-overlap-invariants' "$DEVKIT_DIR/profiles/android/rules/android-rules.md" \
  && ok "android-rules.md still carries the Android cell list + helper" || fail "android-rules.md lost the Android cell list"
grep -qi 'android-rules' "$DEVKIT_DIR/agents/principal-code-reviewer.md" \
  && ok "the reviewer lens points at the android profile rules for Android cells" || fail "the reviewer lens does not point at the android profile rules"

# a matrix cell is a one-line outcome
grep -qi 'mỗi ô một dòng' "$DEVKIT_DIR/agents/principal-code-reviewer.md" \
  && ok "the lens asks for one outcome line per cell" || fail "the lens does not ask for one outcome line per cell"

[ "$FAILS" -eq 0 ] && echo "✅ test_state_matrix_lens: all passed" || { echo "❌ test_state_matrix_lens: $FAILS failed"; exit 1; }
