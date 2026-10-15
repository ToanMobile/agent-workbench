#!/usr/bin/env bash
# A layout/overlay/inset change is not "done" until a state matrix (one outcome line per cell, "overlaps" / "unchecked" marked) exists. Four
# defects shipped through green tests because nobody enumerated the cells.
# Pin: the lens text must be in the reviewer prompt, in the layout/responsive council (01) and the accessibility council (10), and in the
# device-QA skill; it must NOT be pasted into every council; the Android cell list stays in the android profile rules, not in the kit lens.
# Review of lane A11: the check is on the LENS TEXT itself (the reviewer's State-matrix bullet, the council line, the skill's section 6), not on
# the whole file: `unchecked` already stood in agents/principal-code-reviewer.md ("Residual/unchecked phải nêu riêng"), so a grep over the file
# could not fail. The kit lens is generic ("the axes that apply to the change", each file says to drop the ones that do not): the
# document-viewer axes (loại tài liệu, thanh chỉnh sửa, trình phát nổi) belong to the android profile rules, section 15. Mutants of each pin
# must be caught, so the greps cannot pass vacuously. LENS_DIR=<copy of the kit> runs the same checks on another copy.
# bash 3.2 compatible.
set -u
DEVKIT_DIR="${LENS_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# lens_block <file>: the lens text of that file and nothing else
lens_block() {
  case "$1" in
    */agents/principal-code-reviewer.md) awk '/^- State matrix/{on=1; print; next} on&&/^  /{print; next} {on=0}' "$1" ;;   # the bullet and its indented lines
    */skills/*) awk '/^### [0-9]+\. State Matrix/{on=1; print; next} on&&/^(---|##)/{on=0} on{print}' "$1" ;;               # section 6 up to the next heading / rule
    *) grep -iF 'state matrix' "$1" | head -1 ;;                                                                         # the councils: one long bullet line
  esac
}

# verify_lens <file> <needs the drop-the-axes clause: 1|0>: prints one line per broken pin, nothing when all hold
verify_lens() {
  local f="$1" clause="$2" b t
  [ -f "$f" ] || { echo "    (missing file)"; return; }
  b="$(lens_block "$f")"
  [ -n "$b" ] || { echo "    (no lens text found)"; return; }
  for t in 'state matrix' 'font scale 200%' 'RTL' 'cutout' 'orientation'; do
    printf '%s\n' "$b" | grep -qiF -- "$t" || echo "    (the lens lacks: $t)"
  done
  for t in '`overlaps`' '`unchecked`'; do
    printf '%s\n' "$b" | grep -qF -- "$t" || echo "    (the lens lacks the backticked marker $t)"
  done
  for t in 'loại tài liệu' 'thanh chỉnh sửa' 'trình phát'; do
    printf '%s\n' "$b" | grep -qiF -- "$t" && echo "    (the kit lens names a document-viewer axis: $t; that belongs in android-rules.md section 15)"
  done
  if [ "$clause" = 1 ]; then printf '%s\n' "$b" | grep -qF 'Bỏ trục không áp dụng' || echo "    (the lens does not say to drop the axes that do not apply)"; fi
  return 0
}

LENSFILES="agents/principal-code-reviewer.md:1 agents/councils/01-subsystem-shared-flow.md:1 agents/councils/10-standards-compliance-delivery.md:0 skills/android-real-device-qa/SKILL.md:1"
for spec in $LENSFILES; do
  rel="${spec%%:*}"; clause="${spec##*:}"
  out="$(verify_lens "$DEVKIT_DIR/$rel" "$clause")"
  [ -z "$out" ] && ok "$rel carries the generic state-matrix lens" || fail "$rel: the state-matrix lens is wrong
$out"
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
grep -qi 'trình phát nổi' "$DEVKIT_DIR/profiles/android/rules/android-rules.md" \
  && ok "  … including the document-viewer axes the kit lens no longer names" || fail "android-rules.md does not carry the document-viewer axes (trình phát nổi)"
grep -qi 'android-rules' "$DEVKIT_DIR/agents/principal-code-reviewer.md" \
  && ok "the reviewer lens points at the android profile rules for Android cells" || fail "the reviewer lens does not point at the android profile rules"

# a matrix cell is a one-line outcome
grep -qi 'mỗi ô một dòng' "$DEVKIT_DIR/agents/principal-code-reviewer.md" \
  && ok "the lens asks for one outcome line per cell" || fail "the lens does not ask for one outcome line per cell"

# mutants: each damages ONE pin of ONE file in a copy; verify_lens must say so
mutant() {  # mutant <name> <rel file> <clause 1|0> <sed expression applied to the lens lines>
  local c="$TMP/m-$1/$2"; mkdir -p "$(dirname "$c")"; cp "$DEVKIT_DIR/$2" "$c"
  sed -e "$4" "$c" > "$c.new" && mv "$c.new" "$c"
  if cmp -s "$DEVKIT_DIR/$2" "$c"; then fail "mutant $1: the sed changed nothing, the pin is not where the test looks"; return; fi
  [ -n "$(verify_lens "$c" "$3")" ] && ok "mutant $1 is caught" || fail "mutant $1 survived: verify_lens said nothing"
}
# `unchecked` removed from the lens only: the rest of the reviewer file still says `unchecked` / unchecked elsewhere, which is what hid this before
mutant reviewer-no-unchecked agents/principal-code-reviewer.md 1 '/^- State matrix/,/^$/s/`unchecked`/not measured/g'
mutant council01-no-unchecked agents/councils/01-subsystem-shared-flow.md 1 's/`unchecked`/not measured/'
mutant council10-no-overlaps  agents/councils/10-standards-compliance-delivery.md 0 's/`overlaps`/clash/'
mutant skill-no-unchecked     skills/android-real-device-qa/SKILL.md 1 '/ô chưa đo/s/`unchecked`/not measured/'
mutant reviewer-viewer-axis   agents/principal-code-reviewer.md 1 's/^- State matrix (diff đổi layout\/overlay\/inset\/cử chỉ):/- State matrix (loại tài liệu, thanh chỉnh sửa, trình phát nổi):/'
mutant council01-viewer-axis  agents/councils/01-subsystem-shared-flow.md 1 's/orientation × kiểu điều hướng/loại tài liệu × orientation × kiểu điều hướng/'
mutant skill-viewer-axis      skills/android-real-device-qa/SKILL.md 1 's/orientation × điều hướng/orientation × thanh chỉnh sửa × điều hướng/'
mutant council01-no-clause    agents/councils/01-subsystem-shared-flow.md 1 's/Bỏ trục không áp dụng/Giữ mọi trục/'
mutant skill-no-clause        skills/android-real-device-qa/SKILL.md 1 's/Bỏ trục không áp dụng/Giữ mọi trục/'
mutant reviewer-no-rtl        agents/principal-code-reviewer.md 1 '/^- State matrix/,/^$/s/RTL/LTR/'

[ "$FAILS" -eq 0 ] && echo "✅ test_state_matrix_lens: all passed" || { echo "❌ test_state_matrix_lens: $FAILS failed"; exit 1; }
