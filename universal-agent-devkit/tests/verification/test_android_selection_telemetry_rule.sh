#!/usr/bin/env bash
# docs/workflow-improvements.md I.3 P9: a feature that acts on a user-supplied selection (translate, copy, search, share) logs a SIZE BUCKET of
# it, never the content. OfficeReader 07/10: PDF "Translate" got 1-2 words per request because the END selection handle lost a tie; no unit test
# can show that, a bucket distribution on the dashboard can. android-rules.md section 12 already says "đường dẫn -> chỉ gửi loại/nhóm (... bucket
# kích thước)" for paths; this pins the sibling rule for selections: the bucket scheme and one sample event name, in the on-demand block of
# section 12 right after the PII line (the on-demand split forbids MUST-words there: tests/context_memory/test_profile_split.sh B).
# bash 3.2 compatible.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RULES="$DEVKIT_DIR/profiles/android/rules/android-rules.md"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
[ -f "$RULES" ] || { echo "✖ $RULES missing"; exit 1; }

# the section-12 on-demand block: from its marker to the next end marker
BLOCK="$(awk '/^<!-- on-demand: §12 /{on=1} on{print} on&&/^<!-- \/on-demand -->/{exit}' "$RULES")"
[ -n "$BLOCK" ] && ok "found the section 12 on-demand block" || { fail "section 12 on-demand block not found"; BLOCK=""; }

for tok in 'selection_action' 'size_bucket' 'w1' 'w2' 'w3_5' 'w6_20' 'w21_100' 'w101_plus' 'c1_2' 'c3_10' 'c11_100' 'c101_plus'; do
  printf '%s\n' "$BLOCK" | grep -qF -- "\`$tok\`" && ok "rule names \`$tok\`" || fail "section 12 block does not name \`$tok\`"
done

# review of lane A11: the bucket spec said "text without spaces such as CJK counts characters", which also describes ONE Latin word (w1 and
# c3_10 overlapped). The rule now names the scripts: those that separate words with spaces count words, those written solid count
# characters; no script is in both lists, a long Latin word is w1, and the character-bucket edges (10 / 11) are in the boundary list.
words_cls="$(printf '%s\n' "$BLOCK" | sed -n 's/.*ngăn từ bằng dấu cách (\([^)]*\)).*/\1/p' | head -1)"
chars_cls="$(printf '%s\n' "$BLOCK" | sed -n 's/.*viết liền không ngăn từ (\([^)]*\)).*/\1/p' | head -1)"
[ -n "$words_cls" ] && [ -n "$chars_cls" ] && ok "rule lists the scripts that count words and the scripts that count characters" || fail "rule does not list the word-bucket and character-bucket scripts (words: '$words_cls' chars: '$chars_cls')"
for s in Latin Kirin; do printf '%s' "$words_cls" | grep -qF "$s" && ok "word buckets: $s" || fail "word-bucket scripts miss $s"; done
for s in Hán Hiragana Katakana Thái; do printf '%s' "$chars_cls" | grep -qF "$s" && ok "character buckets: $s" || fail "character-bucket scripts miss $s"; done
both="$(printf '%s\n' "$words_cls" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | while read -r w; do [ -n "$w" ] && printf '%s' "$chars_cls" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -qxF "$w" && echo "$w"; done)"
[ -z "$both" ] && ok "no script is in both the word list and the character list" || fail "scripts in both lists: $both"
printf '%s\n' "$BLOCK" | grep -qF 'một từ Latin dài vẫn là `w1`' && ok "a long Latin word stays w1 (it is not a c-bucket)" || fail "rule does not say a long Latin word is w1"
printf '%s\n' "$BLOCK" | grep -qF 'đếm từ: 1, 2, 3, 5, 6, 20, 21, 100, 101' && printf '%s\n' "$BLOCK" | grep -qF 'đếm ký tự: 1, 2, 3, 10, 11, 100, 101' \
  && ok "boundary list covers the word edges and the character edges (10 / 11 included)" || fail "boundary list lacks the character-bucket edges 10 / 11"
printf '%s\n' "$BLOCK" | grep -qF 'Vùng chọn trộn' && ok "rule says which bucket family a mixed selection takes" || fail "rule does not cover a mixed-script selection"

# the PII half of the rule is an obligation with no MUST-word: it lives on the always-loaded PII line, not only in the on-demand block
printf '%s\n' "$(grep '^- Không gửi PII vào analytics/Crashlytics' "$RULES")" | grep -qF 'chỉ gửi kích thước, không bao giờ gửi nội dung hay độ dài chính xác' \
  && ok "the size-only, never-content sentence is on the always-loaded PII line" || fail "the size-only sentence is not on the PII line (it would load only on demand)"

# the rule is about content never being sent, and about reading the distribution
printf '%s\n' "$BLOCK" | grep -qi 'lựa chọn' && printf '%s\n' "$BLOCK" | grep -qi 'nội dung' \
  && ok "rule is about a user selection and says content is not sent" || fail "rule does not cover user selections / content"
printf '%s\n' "$BLOCK" | grep -qiE 'phân phối|distribution' \
  && ok "rule says to read the bucket distribution" || fail "rule does not say to read the bucket distribution"
printf '%s\n' "$BLOCK" | grep -qiE 'kiểm thử|test' && printf '%s\n' "$BLOCK" | grep -qF 'ranh giới' \
  && ok "rule asks for a test of the bucket boundaries" || fail "rule does not ask for a test of the bucket boundaries"

# placement: after the PII line, inside the block (so it sits next to the PII rule), and no MUST-word that the on-demand split would reject
pii_line="$(grep -n '^- Không gửi PII vào analytics/Crashlytics' "$RULES" | head -1 | cut -d: -f1)"
sel_line="$(grep -n 'selection_action' "$RULES" | head -1 | cut -d: -f1)"
[ -n "$pii_line" ] && [ -n "$sel_line" ] && [ "$sel_line" -gt "$pii_line" ] && [ $((sel_line - pii_line)) -le 6 ] \
  && ok "the selection rule sits within 6 lines after the PII rule (PII line $pii_line, rule line $sel_line)" \
  || fail "the selection rule is not next to the PII rule (PII line '${pii_line:-none}', rule line '${sel_line:-none}')"
printf '%s\n' "$BLOCK" | grep -E 'BẮT BUỘC|[Bb]ắt buộc|MUST|CẤM|[Cc]ấm|bất biến|Bất biến|Nghiêm cấm|Tuyệt đối' | grep -qi 'selection_action\|size_bucket' \
  && fail "a selection-rule line uses a MUST-word: the on-demand split would reject the block" || ok "no MUST-word on the selection-rule lines"

[ "$FAILS" -eq 0 ] && echo "✅ test_android_selection_telemetry_rule: all passed" || { echo "❌ test_android_selection_telemetry_rule: $FAILS failed"; exit 1; }
