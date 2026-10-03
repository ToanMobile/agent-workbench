#!/usr/bin/env bash
# Regression test: the prompt-context enricher (scripts/enrich_context.py via
# hooks/prompt_context.sh) and the instincts index (scripts/index_memory.py).
#  - defect reports ("bị xóa", "bị mất", "không chạy", "sai") are bug fixes and get
#    the RED→GREEN rule; only deliberate wording ("xoá API cũ", "deprecate") is a
#    deprecation; short keywords ("pr", "ui") don't fire inside other words.
#  - identifiers are matched by their parts (DocxEditor → docx), and one shared
#    Vietnamese phrase ("cửa sổ") is not enough to call an entry relevant.
#  - the index skips commented-out templates, its `sed -n` commands run from the
#    project root, and it stays under 20 KB without dropping entries.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ENRICH="$DEVKIT_DIR/scripts/context/enrich_context.py"
[ -f "$ENRICH" ] || ENRICH="$DEVKIT_DIR/scripts/enrich_context.py"
HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"
INDEXER="$DEVKIT_DIR/scripts/governance/index_memory.py"
[ -f "$INDEXER" ] || INDEXER="$DEVKIT_DIR/scripts/index_memory.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unset PROMPT_CONTEXT

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$TMP/proj/.agents" "$TMP/emptykit" && cd "$TMP/proj" || exit 1
git init -q .
export CLAUDE_PROJECT_DIR="$TMP/proj"
cat > .agents/instincts.md <<'EOF'
# Instincts — fixture

<!--
Mẫu ghi nhận:
### [INSTINCT-XXX] <Tên bẫy / Tình huống>
- **Hiện tượng lỗi:** <Mô tả lỗi>
-->

### [INSTINCT-F01] Xem trước DOCX tiếng Ả Rập lệch dòng bidi
- **Hiện tượng lỗi:** Trang DOCX tiếng Ả Rập vẽ lệch dòng.
- **Quy tắc phòng ngừa:** Đo `LineView` sau layout.

### [INSTINCT-F02] Fixture DOCX mới bị .gitignore nuốt
- **Hiện tượng lỗi:** File DOCX mới không vào commit.
- **Quy tắc phòng ngừa:** `git add -f` fixture.

### [INSTINCT-F03] Mở DOCX lớn qua content URI tràn heap
- **Hiện tượng lỗi:** Mở DOCX 80 MB văng OutOfMemoryError.
- **Quy tắc phòng ngừa:** Chép ra file tạm rồi mới mở.

### [INSTINCT-F48] SAXReader / DocxEditor.isWellFormedFragment: XXE hardening không được làm fatal feature mà Android Expat từ chối
- **Hiện tượng lỗi:** Trên máy thật mọi lần lưu báo `reader_error_docx_malformed_output`; chặn mọi DOCX/XLSX/PPTX.
- **Nguyên nhân:** Expat ném `SAXNotRecognizedException` cho `disallow-doctype-decl`.
- **Quy tắc phòng ngừa:** Trong `SAXReader.applyUntrustedXmlSecurity` chỉ 2 feature external-entities là fatal.

### [INSTINCT-F44] Overlay/cửa sổ trên ROM: đo trước addView; kéo vạch chia cần resizeTask
- **Hiện tượng lỗi:** Widget nổi bị WM/Dock cắt; kéo vạch chia 2 app không đổi kích thước ở freeform.
- **Quy tắc phòng ngừa:** Measure overlay trước `addView`; `resizeStack` phải kèm `resizeTask`.

### [INSTINCT-F16] Test PlayerPrefs.DeleteAll xoá save thật của bản macOS
- **Hiện tượng lỗi:** Chạy test EditMode xong thì save của người chơi mất sạch.
- **Quy tắc phòng ngừa:** Test dùng key prefix riêng, không `DeleteAll`.

### [INSTINCT-F05] Đồng bộ lịch sử phát nhạc giữa hai tài khoản
- **Hiện tượng lỗi:** Lịch sử phát của tài khoản A hiện ở tài khoản B.
- **Quy tắc phòng ngừa:** Khoá cache theo accountId.

### [INSTINCT-F06] Đăng nhập Google trả token hết hạn
- **Hiện tượng lỗi:** Token Google hết hạn sau 1 giờ, gọi API 401.
- **Quy tắc phòng ngừa:** Làm mới token trước khi gọi.
EOF
# Unrelated entries, so the fixture has a real project's spread: a word in 4 of 8
# entries is "common", in 4 of 20 it still names a topic.
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
  printf '\n### [INSTINCT-Z%02d] Gradle build cache số %s hết hạn trên CI\n- **Hiện tượng lỗi:** Job CI số %s build lại từ đầu.\n' \
    "$n" "$n" "$n" >> .agents/instincts.md
done

# intents <prompt> → the detected intents, space separated (fixture project, no DevKit traps)
intents() {
  python3 - "$ENRICH" "$1" "$TMP/emptykit" "$TMP/proj" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
print(" ".join(ec.enrich_prompt(sys.argv[2], sys.argv[3], sys.argv[4])["detected_intents"]))
PY
}
# refs <prompt> → the ids compact() would show, in order
refs() {
  python3 - "$ENRICH" "$1" "$TMP/emptykit" "$TMP/proj" <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
out = ec.compact(ec.enrich_prompt(sys.argv[2], sys.argv[3], sys.argv[4]), sys.argv[4])
print(" ".join(re.findall(r"Bẫy đã gặp: \[(INSTINCT-[\w-]+)\]", out)))
PY
}
has() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }

# ── 1. Classifier ────────────────────────────────────────────────────────────
for p in "PlayerPrefs bị xóa khi chạy test" "PlayerPrefs bị xoá khi chạy test"; do
  i="$(intents "$p")"
  has "$i" BUG_FIX && ! has "$i" DEPRECATION_MIGRATION && ! has "$i" CODE_AND_QA_REVIEW \
    && ok "'$p' → BUG_FIX only ($i)" || fail "'$p' → $i (want BUG_FIX, no DEPRECATION_MIGRATION / CODE_AND_QA_REVIEW)"
done
for p in "dữ liệu người chơi bị mất sau khi cập nhật" "màn hình chính không chạy trên Android 9" \
         "tổng tiền hiển thị sai khi có giảm giá" "export PDF crash ngay lập tức"; do
  has "$(intents "$p")" BUG_FIX && ok "defect report '$p' → BUG_FIX" || fail "defect report '$p' not BUG_FIX: $(intents "$p")"
done
for p in "xoá API cũ sau khi deprecate xong" "deprecate endpoint /v1/orders" "migrate Room sang SQLDelight"; do
  i="$(intents "$p")"
  has "$i" DEPRECATION_MIGRATION && ! has "$i" BUG_FIX \
    && ok "deliberate '$p' → DEPRECATION_MIGRATION" || fail "'$p' → $i"
done
for p in "chuẩn bị thiết bị thật để chạy thử" "tối ưu build script cho nhanh" "thiết kế lại giao diện màn hình cài đặt"; do
  i="$(intents "$p")"
  ! has "$i" BUG_FIX && ! has "$i" CODE_AND_QA_REVIEW && ! has "$i" DUAL_AGENT_DELEGATION \
    && ok "no false intent in '$p' ($i)" || fail "false intent in '$p': $i"
done
has "$(intents "tối ưu build script cho nhanh")" UI_INTERACTION \
  && fail "'ui' inside 'build' → UI_INTERACTION" || ok "short keywords match whole words only ('ui' ≠ build)"
# skills <prompt> → the "Skill phù hợp" line the hook prints (compact(), not the raw dossier)
skills() {
  python3 - "$ENRICH" "$1" "$TMP/emptykit" "$TMP/proj" <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
out = ec.compact(ec.enrich_prompt(sys.argv[2], sys.argv[3], sys.argv[4]), sys.argv[4])
m = re.search(r"Skill phù hợp: (.*)", out)
print(m.group(1).replace(",", " ") if m else "")
PY
}
for p in "thiết kế lại giao diện màn hình cài đặt" "đổi font chữ cho màn hình chính" "chọn bảng màu cho app"; do
  s="$(skills "$p")"
  has "$s" ui-ux-pro-max && ok "design request '$p' → hook shows ui-ux-pro-max" || fail "design request '$p' → hook skills '$s'"
done
# ctx <prompt> → the whole text the hook prints (fixture project, no profile, no DevKit traps)
ctx() {
  python3 - "$ENRICH" "$1" "$TMP/emptykit" "$TMP/proj" <<'PY' || echo "HELPER-CRASH"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
print(ec.compact(ec.enrich_prompt(sys.argv[2], sys.argv[3], sys.argv[4]), sys.argv[4]))
PY
}
# pctx <profile> <prompt> → the same with the real DevKit profile (exclude_skills applies)
pctx() {
  mkdir -p "$TMP/p_$1/.agents" && printf '{"profile": "%s"}\n' "$1" > "$TMP/p_$1/.agents/active-profile.json"
  python3 - "$ENRICH" "$2" "$DEVKIT_DIR" "$TMP/p_$1" <<'PY' || echo "HELPER-CRASH"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
print(ec.compact(ec.enrich_prompt(sys.argv[2], sys.argv[3], sys.argv[4]), sys.argv[4]))
PY
}
zs() { printf '%s\n' "$1" | grep -qF "ZERO-SLOP UI MANDATE"; }                       # the mandate is in the hook text
skl() { printf '%s\n' "$1" | sed -n 's/^- Skill phù hợp: //p' | tr -d ','; }          # its skill line, space separated
# A prompt that touches the screen gets the design skill and the mandate: a crash on rotation too
# (it used to be the one UI prompt that got neither; spec docs/plans/ui-context-injection-zero-slop.md).
o="$(ctx "app crash khi xoay màn hình")"
has "$(skl "$o")" ui-ux-pro-max && zs "$o" && ok "screen crash prompt → ui-ux-pro-max + ZERO-SLOP" || fail "screen crash prompt → '$o'"
s="$(skills "sửa lỗi hud bị vỡ layout")"
case "$s" in *qa-visual*ui-ux-pro-max*) ok "design skill comes after qa-visual (never crowds it out of the top 5)" ;;
  *) fail "skill order '$s' (want qa-visual before ui-ux-pro-max)" ;; esac
s="$(skills "làm màn shop cho game puzzle dọc, nút mua có hiệu ứng nảy")"
has "$s" ui-ux-pro-max && ok "game UI juice prompt → ui-ux-pro-max" || fail "game UI juice prompt → '$s'"
# pskills <profile> <prompt> → hook skill line with the real DevKit profiles (exclude_skills applies)
pskills() {
  mkdir -p "$TMP/p_$1/.agents" && printf '{"profile": "%s"}\n' "$1" > "$TMP/p_$1/.agents/active-profile.json"
  python3 - "$ENRICH" "$2" "$DEVKIT_DIR" "$TMP/p_$1" <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
out = ec.compact(ec.enrich_prompt(sys.argv[2], sys.argv[3], sys.argv[4]), sys.argv[4])
m = re.search(r"Skill phù hợp: (.*)", out)
print(m.group(1).replace(",", " ") if m else "")
PY
}
s="$(pskills game "Unity bị giật GC alloc mỗi frame trong Update")"
has "$s" unity-gc-audit && ok "game: Unity GC prompt → unity-gc-audit" || fail "game: Unity GC prompt → '$s'"
s="$(pskills android "Compose recompose liên tục làm LazyColumn lag")"
has "$s" compose-recomp-audit && ok "android: recomposition prompt → compose-recomp-audit" || fail "android: recomposition → '$s'"
s="$(pskills backend "build apk release ký keystore")"
has "$s" deploy && fail "backend profile recommends excluded skill deploy: '$s'" || ok "profile exclude_skills never recommended"
s="$(skills "fix lỗi hiệu ứng phụ khi gọi API lưu đơn")"
has "$s" ui-ux-pro-max && fail "'hiệu ứng phụ' (side effect) → design skill: '$s'" || ok "'hiệu ứng phụ' is not a design request"
mkdir -p "$TMP/pnull/.agents" && echo '{"profile": null}' > "$TMP/pnull/.agents/active-profile.json"
s="$(python3 - "$ENRICH" "app bị crash khi mở" "$DEVKIT_DIR" "$TMP/pnull" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
print(" ".join(ec.enrich_prompt(sys.argv[2], sys.argv[3], sys.argv[4])["detected_intents"]))
PY
)"
has "$s" BUG_FIX && ok "non-string profile value → context still built" || fail "non-string profile → '$s'"
# An ambiguous word routes only in its technical context.
s="$(pskills android "docker compose chậm khi build image")"
has "$s" compose-recomp-audit && fail "'docker compose' → compose-recomp-audit: '$s'" || ok "'docker compose' is not Jetpack Compose"
s="$(skills "sửa lỗi đặt lịch cho app thẩm mỹ viện")"
has "$s" ui-ux-pro-max && fail "'thẩm mỹ viện' (beauty salon) → design skill: '$s'" || ok "'thẩm mỹ viện' is a business domain, not design"
has "$(intents "skill nào là lựa chọn tối ưu nhất cho task này?")" PERFORMANCE_AND_RESPONSIVENESS \
  && fail "'lựa chọn tối ưu' (best choice) → PERFORMANCE" || ok "'tối ưu' meaning 'best' is not a performance task"
has "$(intents "tối ưu hiệu năng màn hình danh sách")" PERFORMANCE_AND_RESPONSIVENESS \
  && ok "'tối ưu hiệu năng' → PERFORMANCE" || fail "'tối ưu hiệu năng' lost PERFORMANCE"
s="$(skills "giao diện app bị phèn, làm lại cho đẹp")"
has "$s" ui-ux-pro-max && ok "'UI bị phèn' → ui-ux-pro-max" || fail "'bị phèn' → '$s'"
for p in "tối ưu startup" "tối ưu app cho mượt" "tối ưu RAM" "cách tối ưu RAM" "giải pháp tối ưu cho LazyColumn"; do
  has "$(intents "$p")" PERFORMANCE_AND_RESPONSIVENESS && ok "'$p' → PERFORMANCE" || fail "'$p' lost PERFORMANCE"
done
s="$(pskills android "Compose UI bị lag")"
has "$s" compose-recomp-audit && ok "'Compose UI bị lag' → compose-recomp-audit" || fail "'Compose UI bị lag' → '$s'"
s="$(pskills android "Jetpack Compose màn hình chính bị giật")"
has "$s" compose-recomp-audit && ok "'Jetpack Compose … giật' → compose-recomp-audit" || fail "Jetpack Compose jank → '$s'"

# ── 1b. Zero-Slop UI door ────────────────────────────────────────────────────
# A UI word in the prompt, or ANY prompt on an app profile (android / game / ios / web), switches on
# UI_INTERACTION + VISUAL_DESIGN, the ZERO-SLOP mandate and ui-ux-pro-max. Elsewhere nothing changes.
o="$(ctx "sửa lại nút bấm trong màn hình inventory")"
has "$(skl "$o")" ui-ux-pro-max && zs "$o" && ok "'nút bấm … màn hình' → ui-ux-pro-max + ZERO-SLOP" || fail "inventory prompt → '$o'"
for p in "gộp card lồng card trong danh sách" "đổi theme tối cho dialog xác nhận" "thêm popup túi đồ cho game" \
         "chỉnh view đăng nhập" "Compose chưa đúng ý" "canvas bị tràn ra ngoài" "chọn palette mới" "thêm animation mở menu" \
         "đổi font chữ tiêu đề" "widget thời tiết thiếu icon" "typography chưa cân" "chụp screen rồi so sánh" "ugui bị lệch" \
         "đổi bảng màu cho app" "UX trang checkout phèn quá"; do
  o="$(ctx "$p")"
  zs "$o" && has "$(skl "$o")" ui-ux-pro-max && ok "UI / design word '$p' → mandate + design skill" || fail "UI word '$p' → '$o'"
done
# Ambiguous words: only in their UI sense (profile universal and backend: no profile door). Each of these was a real
# false positive in the review: a SQL view, a Django view, compose.yaml, a Grafana panel, sanctions screening,
# Dialogflow, a theme_id column, a card number in a payment log.
for p in "tối ưu build script cho nhanh" "fix lỗi hiệu ứng phụ khi gọi API lưu đơn" "docker compose chậm khi build image" \
         "sửa lỗi đặt lịch cho app thẩm mỹ viện" "skill nào là lựa chọn tối ưu nhất cho task này?" \
         "refactor ViewModel lưu cache đơn hàng" "giảm cardinality của metric http_requests" \
         "cài composer cho dự án PHP" "cardholder bị trùng khi import" \
         "thêm cột discount vào sql view doanh thu" "sửa Django views trả về 500 khi thiếu token" \
         "sửa compose.yaml thêm service redis" "chạy compose up -d cho môi trường dev" "thêm panel Grafana đo độ trễ" \
         "sanctions screening chạy chậm" "tích hợp Dialogflow cho tổng đài" "thêm field theme_id vào bảng user" \
         "mask số card trong log thanh toán" "sửa dialog state machine của trợ lý" "chụp screenshot để so sánh"; do
  o="$(ctx "$p")"; b="$(pctx backend "$p")"
  case "$o$b" in *HELPER-CRASH*) fail "helper crashed on '$p'"; continue ;; esac
  if zs "$o" || zs "$b" || has "$(skl "$o")" ui-ux-pro-max || has "$(skl "$b")" ui-ux-pro-max; then
    fail "'$p' is not UI work but got the mandate / design skill"
  else ok "'$p' → no mandate, no design skill"; fi
done
# The profile alone is enough: no UI word in the prompt, still the intents, the mandate and the design skill.
for prof in android game ios web; do
  o="$(pctx "$prof" "sửa null trong repository")"
  l="$(printf '%s\n' "$o" | sed -n 's/^- Loại việc: //p')"
  case "$l" in *UI_INTERACTION*VISUAL_DESIGN*) li=1 ;; *) li=0 ;; esac
  [ "$li" = 1 ] && zs "$o" && has "$(skl "$o")" ui-ux-pro-max \
    && ok "$prof profile, no UI word → UI_INTERACTION + VISUAL_DESIGN + mandate + ui-ux-pro-max" || fail "$prof profile → '$o'"
done
o="$(pctx android "sửa null trong repository")"
has "$(skl "$o")" android-real-device-qa && fail "android profile alone pulled the device-QA skill into a non-UI prompt: $(skl "$o")" \
  || ok "android profile without a UI word → no android-real-device-qa"
# The four long game-feel lines belong to the aesthetic words ("hiệu ứng nảy", "juice"…), not to the game profile.
o="$(pctx game "sửa null trong repository")"
printf '%s\n' "$o" | grep -qF "Anti-Phèn Visual Standard" && fail "game profile alone adds the game-feel lines: $o" \
  || ok "game profile, no aesthetic word → no game-feel lines"
o="$(pctx game "thêm hiệu ứng nảy cho nút mua")"
printf '%s\n' "$o" | grep -qF "Anti-Phèn Visual Standard" && ok "game profile + aesthetic word → game-feel lines kept" || fail "game-feel lines lost: $o"
o="$(pctx android "sửa lại nút bấm trong màn hình inventory")"
has "$(skl "$o")" android-real-device-qa && ok "android + UI word → android-real-device-qa" || fail "android + UI word → '$(skl "$o")'"
# The mandate is its own block: the "Yêu cầu ngầm định" line stays one short line, the six bullets are lines of their own
# (dedupe_session drops repeated lines one by one; a bullet glued to another line would be re-sent or orphaned).
n="$(printf '%s\n' "$o" | grep -c '^• ')"
printf '%s\n' "$o" | grep '^- Yêu cầu ngầm định:' | grep -qF "ZERO-SLOP" && fail "mandate glued to the requirements line" \
  || { [ "$n" = 6 ] && ok "mandate = header + 6 bullet lines, apart from the requirements line" || fail "mandate bullets: $n (want 6): $o"; }
for w in Cardocalypse "Icon Tile" "xám trần" "Spacing" "Tactile Depth" "Touch Target"; do
  printf '%s\n' "$o" | grep '^• ' | grep -qF "$w" || fail "mandate lost its '$w' bullet"
done
# Skill line: at most 5; ui-ux-pro-max is never the one cut, and a tool audit is never the one it replaces.
for c in "android|Compose UI bị lag|compose-recomp-audit" "game|Unity bị giật GC alloc mỗi frame trong Update|unity-gc-audit" \
         "android|sửa lỗi hud bị vỡ layout trên màn hình chính|qa-visual"; do
  prof="${c%%|*}"; rest="${c#*|}"; p="${rest%%|*}"; want="${rest##*|}"
  s="$(skl "$(pctx "$prof" "$p")")"
  [ "$(printf '%s\n' $s | wc -l | tr -d ' ')" -le 5 ] && has "$s" "$want" && has "$s" ui-ux-pro-max \
    && ok "$prof '$p' → $want and ui-ux-pro-max both in the 5 ($s)" || fail "$prof '$p' → '$s' (want $want + ui-ux-pro-max, ≤5)"
done
case "$(skl "$(pctx android "sửa lỗi hud bị vỡ layout trên màn hình chính")")" in
  *qa-visual\ ui-ux-pro-max*) ok "android hud prompt: qa-visual stays right before ui-ux-pro-max" ;;
  *) fail "android hud prompt: '$(skl "$(pctx android "sửa lỗi hud bị vỡ layout trên màn hình chính")")'" ;; esac
# Traps: the UI trap terms (click, debounce, 48dp) belong to a prompt that talks about UI. When only the PROFILE
# says UI they would crowd the 4 trap slots (and dedupe then hides them): a DOCX prompt keeps its own trap.
mkdir -p "$TMP/p_android/.agents" && cp "$TMP/proj/.agents/instincts.md" "$TMP/p_android/.agents/instincts.md"
cat >> "$TMP/p_android/.agents/instincts.md" <<'EOF'

### [INSTINCT-F07] Nút mua bị bấm đúp: thiếu debounce và vùng chạm 48dp
- **Hiện tượng lỗi:** Người dùng double click nút mua, đơn bị tạo hai lần.
- **Quy tắc phòng ngừa:** Disable nút sau click đầu tiên, debounce 1000 ms, touch target 48dp.
EOF
# prefs <profile> <prompt> → the trap ids compact() shows for a project of that profile (fixture traps only)
prefs() {
  python3 - "$ENRICH" "$2" "$TMP/emptykit" "$TMP/p_$1" <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
out = ec.compact(ec.enrich_prompt(sys.argv[2], sys.argv[3], sys.argv[4]), sys.argv[4])
print(" ".join(re.findall(r"Bẫy đã gặp: \[(INSTINCT-[\w-]+)\]", out)))
PY
}
r="$(prefs android "mở file DOCX bị lỗi XML")"
has "$r" INSTINCT-F48 && ! has "$r" INSTINCT-F07 \
  && ok "android profile, DOCX prompt → its own trap (F48), not the UI trap F07 ($r)" || fail "android profile DOCX prompt traps: '$r'"
r="$(prefs android "bấm nút mua 2 lần bị trừ tiền hai lần")"
has "$r" INSTINCT-F07 && ok "a prompt that talks about UI still gets the UI trap (F07)" || fail "UI prompt lost F07: '$r'"
# A profile-only UI intent does not lift the 'strong match only' bar of a prompt that names no kind of work.
python3 - "$ENRICH" <<'PY' && ok "shown_refs: profile-only intents keep the 3-point bar, real intents lift it" || fail "shown_refs bar"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
ref = {"title": "[INSTINCT-X] t", "file": "f", "line": 1, "score": 2}
base = {"matched_instinct_refs": [ref], "detected_intents": ["UI_INTERACTION", "VISUAL_DESIGN"]}
assert ec.shown_refs({**base, "profile_intents": ["UI_INTERACTION", "VISUAL_DESIGN"]}) == [], "profile-only: weak ref shown"
assert ec.shown_refs({**base, "profile_intents": []}) == [ref], "real UI intent: weak ref hidden"
PY

# ── 2. Recall ────────────────────────────────────────────────────────────────
r="$(refs "mở file DOCX bị lỗi XML")"
[ "${r%% *}" = "INSTINCT-F48" ] && ok "DOCX + XML → the XXE entry first (DocxEditor, applyUntrustedXmlSecurity)" \
  || fail "DOCX + XML → '$r' (want INSTINCT-F48 first)"
for p in "cửa sổ xe bị kẹt" "sửa lỗi cửa sổ không lên được"; do
  r="$(refs "$p")"
  has "$r" INSTINCT-F44 && fail "'$p' matched the UI overlay window entry: $r" || ok "'$p' → no overlay-window entry"
done
has "$(refs "sửa lỗi overlay cửa sổ bị WM cắt")" INSTINCT-F44 \
  && ok "overlay + cửa sổ + WM → the overlay entry" || fail "overlay entry lost: $(refs "sửa lỗi overlay cửa sổ bị WM cắt")"
has "$(refs "PlayerPrefs bị xóa khi chạy test")" INSTINCT-F16 \
  && ok "PlayerPrefs bị xóa → the DeleteAll entry (xóa/xoá spelled either way)" || fail "DeleteAll entry missed"

# ── 3. End to end through the hook ───────────────────────────────────────────
hook() { printf '%s' "$1" | bash "$HOOK"; }
out="$(hook '{"prompt":"PlayerPrefs bị xóa khi chạy test"}')"; rc=$?
[ $rc = 0 ] && printf '%s' "$out" | grep -q "BUG_FIX" && printf '%s' "$out" | grep -q "ĐỎ trước khi sửa" \
  && ! printf '%s' "$out" | grep -q "DEPRECATION_MIGRATION" \
  && ok "hook: defect report gets the RED→GREEN rule" || fail "hook (rc=$rc): $out"
out="$(hook '{"prompt":"mở file DOCX bị lỗi XML"}')"
cmd="$(printf '%s\n' "$out" | grep "INSTINCT-F48" | sed -n "s/.*\`\(sed -n '[0-9]*,[0-9]*p' [^\`]*\)\`.*/\1/p")"
case "$cmd" in *" .agents/instincts.md") ok "hook: F48 shown with a project-relative path" ;; *) fail "hook: F48 / path wrong: $out" ;; esac
[ -n "$cmd" ] && (cd "$TMP/proj" && eval "$cmd") | head -1 | grep -q '^### \[INSTINCT-F48\]' \
  && ok "hook: its sed command prints the entry from the project root" || fail "hook: '$cmd' does not print F48"
out="$(hook '{"prompt":"cửa sổ xe bị kẹt không đóng được"}')"
printf '%s' "$out" | grep -q "INSTINCT-F44" && fail "hook: car window matched the overlay entry: $out" || ok "hook: car window ≠ overlay window"
[ -z "$(hook '{"prompt":"/help me please"}')" ] && [ -z "$(hook '{"prompt":"cảm ơn, làm tốt lắm"}')" ] \
  && ok "hook: silent for slash commands and chit-chat" || fail "hook not silent"
[ -z "$(printf '{"prompt":"PlayerPrefs bị xóa khi chạy test"}' | PROMPT_CONTEXT=0 bash "$HOOK")" ] \
  && ok "hook: PROMPT_CONTEXT=0 disables it" || fail "PROMPT_CONTEXT=0 ignored"

# ── 4. index_memory.py ───────────────────────────────────────────────────────
cd "$TMP" || exit 1   # not the project root: the index must not depend on the cwd
python3 "$INDEXER" "$TMP/proj/.agents/instincts.md" >/dev/null 2>&1
IDX="$TMP/proj/.agents/instincts-index.md"
[ -f "$IDX" ] && ok "index written next to the source" || fail "no index"
grep -q "INSTINCT-XXX" "$IDX" && fail "index lists the commented-out template" || ok "index skips entries in HTML comments"
n=0; bad=0
while IFS= read -r c; do
  n=$((n + 1)); id="${c%% *}"; c="${c#* }"
  (cd "$TMP/proj" && eval "$c" 2>/dev/null) | head -1 | grep -qF "### [$id]" || { bad=$((bad + 1)); echo "   $c ↛ $id"; }
done <<EOF
$(grep -o '\[INSTINCT-[A-Z0-9-]*\].*sed -n '"'"'[0-9]*,[0-9]*p'"'"' [^\`]*' "$IDX" \
  | sed "s/^\[\(INSTINCT-[A-Z0-9-]*\)\].*\(sed -n '[0-9]*,[0-9]*p' [^\`]*\)$/\1 \2/")
EOF
[ "$n" = 20 ] && [ "$bad" = 0 ] && ok "all 20 index sed commands print their entry from the project root" \
  || fail "index sed commands: $n found, $bad broken"
[ ! -e "$TMP/proj/.agents/instincts-index.md.tmp" ] && ! ls "$TMP/proj/.agents" | grep -q '\.tmp' \
  && ok "no temp file left behind" || fail "temp file left in .agents"

# A GeelyEx2-sized memory: 150 entries with long Vietnamese titles, ~120 KB.
mkdir -p "$TMP/big/.agents" && git -C "$TMP/big" init -q
python3 - "$TMP/big/.agents/instincts.md" <<'PY'
import sys
out = ["# Instincts — lớn", ""]
for i in range(1, 151):
    out.append(f"### [INSTINCT-{i:03d}] Đo độ trễ đánh thức giọng nói trên xe thật: không tin log ứng dụng, "
               f"phải đo bằng dấu thời gian của bộ phát âm thanh và so với ngưỡng đã đo trước đó lần {i}")
    out += [f"- **Hiện tượng lỗi:** mô tả rất dài về lỗi số {i} " * 6,
            "- **Quy tắc phòng ngừa:** đo trên xe thật trước khi khen mượt, ghi lại bảng số liệu.", ""]
open(sys.argv[1], "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
python3 "$INDEXER" "$TMP/big/.agents/instincts.md" >/dev/null 2>&1
BIG="$TMP/big/.agents/instincts-index.md"
size="$(wc -c < "$BIG" | tr -d ' ')"
[ "$size" -le 20480 ] && ok "150-entry index fits 20 KB ($size B)" || fail "150-entry index is $size B (> 20480)"
[ "$(grep -c '^- .*\[INSTINCT-[0-9]*\]' "$BIG")" = 150 ] && [ "$(grep -c 'INSTINCT-' "$BIG")" = 150 ] \
  && ok "all 150 entries kept, one line each" || fail "entries dropped or split: $(grep -c 'INSTINCT-' "$BIG")"

if [ "$FAILS" -ne 0 ]; then
  echo "prompt_context: $FAILS FAILED"; exit 1
fi
echo "prompt_context: all checks passed"
