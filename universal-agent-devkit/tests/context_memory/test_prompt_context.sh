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
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
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
# (it used to be the one UI prompt that got neither; spec docs/workflow-improvements.md II.C).
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
         "mask số card trong log thanh toán" "sửa dialog state machine của trợ lý" "chụp screenshot để so sánh" \
         "First operation: run python3 .claude/bin/super-board-skills-ready.py --root . --host claude --cards - --hydrate --lane review"; do
  # ↑ the super-board lane opener (2026-10-25 audit: its CLI flag --cards opened the UI door in 761 of 771 backend lane sessions)
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
# The false-friend phrases must not eat the routing words next to them: "compose up" is a command, "recompose up to"
# and "Compose update/upgrade" are not (review round 2: they lost compose-recomp-audit / PERFORMANCE).
for p in "Compose update xong thì list bị giật" "Compose upgrade lên 1.7 làm màn hình lag" "nâng Compose up to 1.7 thì list bị giật"; do
  s="$(skl "$(pctx android "$p")")"
  has "$s" compose-recomp-audit && ok "android '$p' → compose-recomp-audit" || fail "android '$p' → '$s'"
done
for p in "Text recompose up to 60 lần mỗi giây" "LazyColumn item recompose update liên tục"; do
  has "$(intents "$p")" PERFORMANCE_AND_RESPONSIVENESS && ok "'$p' → PERFORMANCE" || fail "'$p' lost PERFORMANCE: $(intents "$p")"
done
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
# An aesthetic word (vfx, shading, đồ họa, phèn) opens the door for the mandate but is no evidence for the UI traps
# either: such a prompt keeps its own traps and never gets the double-click one — on an app profile or off it.
mkdir -p "$TMP/p_universal/.agents" && cp "$TMP/p_android/.agents/instincts.md" "$TMP/p_universal/.agents/instincts.md"
for prof in universal android; do
  for p in "thêm vfx cho combo nổ" "tối ưu shading của nước trong game" "đồ họa map 2 bị vỡ" "hiệu ứng vfx nổ của particle quá phèn" \
           "typography tiêu đề phèn" "hud quá phèn" "font chữ quá phèn" "theme tối nhìn phèn" "animation vfx quá phèn" "đổi palette màu game phèn"; do
    r="$(prefs "$prof" "$p")"
    has "$r" INSTINCT-F07 && fail "$prof: aesthetic prompt '$p' got the UI trap F07 ($r)" || ok "$prof: aesthetic prompt '$p' → no UI trap"
  done
done
r="$(prefs universal "bấm nút mua 2 lần bị trừ tiền hai lần")"
has "$r" INSTINCT-F07 && ok "universal: a prompt that talks about UI still gets F07" || fail "universal UI prompt lost F07: '$r'"
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

# ── 1c. Super-board lane harness ─────────────────────────────────────────────
# A lane worker's first prompt is the runner's text (.claude/bin/super-board-run.sh, the wave workflow's SKILLS_CHECK),
# not a request. Replayed on 40 real lanes (2026-10-25 audit): its fixed sentences (worktree, claims, disk floor, card,
# review, merge) showed the same 4 traps in 38-40 of 40, the UI door ("card") and CODE_AND_QA_REVIEW in all 40, and the
# card's `bug` label made 33 of them BUG_FIX. Only the card's own title/body is classified now; a prompt that merely
# quotes the opener, or starts with the words "First operation", is a user prompt as before.
mkdir -p "$TMP/p_lane/.agents" && cp "$TMP/proj/.agents/instincts.md" "$TMP/p_lane/.agents/instincts.md"
cat >> "$TMP/p_lane/.agents/instincts.md" <<'EOF'

### [INSTINCT-F09] Lane worktree gỡ dưới disk floor làm mất claims và approval evidence
- **Hiện tượng lỗi:** `agent-kit worktree remove` gỡ worktree còn giữ claims; hydrate lại thì approval evidence đã mất.
- **Quy tắc phòng ngừa:** Kiểm disk floor trước khi tạo worktree, preserve claims và approval evidence khi halt.
EOF
# The runner's opener, verbatim from a real lane (2026-10-25; only --root shortened). Its card JSON has no title or body.
cat > "$TMP/lane_runner.txt" <<'EOF'
First operation: run .claude/bin/super-board-skills-ready.py --root '/repo' --host claude --cards - --lane 'build' --hydrate with [{"number":416,"status":"Ready","labels":["bug"],"lane":"build"}] as stdin. Halt on exit 10 before worktree creation or lifecycle writes; preserve claims and approval evidence. Load resolved paths and only declared fallbacks; recheck conditionals with --require before activation. Run super-build on issue #416 for super-board run. Read .claude/skills/super-board/references/run.md → Builder lifecycle. Config: .claude/super-board/configs/agent-workbench.json. Worktree: after git fetch origin, create it from the repo root ONLY with the DevKit, never plain git worktree add or EnterWorktree: agent-kit worktree add .claude/worktrees/issue-416-build issue-416-<slug> --lane=build --base=origin/<config.base_branch> (an existing issue branch is checked out as it is, one only origin has from origin/<branch>, and the lane's worktree already at that path is reused). It links the DevKit, copies the git-ignored config and hooks and clones a Unity Library copy-on-write; no agent-kit on PATH: python3 .agents/devkit/scripts/git/worktree.py add with the same arguments. Exit 4 = under the disk floor: stop with its message, card and claims unchanged. Exit 1 naming a worktree that holds the branch: agent-kit worktree remove that path (no agent-kit on PATH: python3 .agents/devkit/scripts/git/worktree.py remove; it drops the DevKit set-up a worktree carries, never work; refused with ✖ = it holds work: Block the card naming it), then add again. Clean up on exit with agent-kit worktree remove <path> (the branch stays).  Emulator policy: NEVER launch an Android emulator without -no-window (always run headless in background with -no-window -no-audio -no-boot-anim, or via python3 .agents/devkit/bin/proof-capture.py). Language policy: This repository uses Vietnamese ('lang': 'vi'). Write all PR descriptions, problem/solution/AC explanations, status comments, and review notes in Vietnamese (Tiếng Việt); identifiers/symbols remain English.
EOF
# wave <title> → the wave workflow's lane prompt (SKILLS_CHECK + a READ_FAILURE line + the lane lines), its card JSON carries the title.
wave() {
  python3 - "$1" <<'PY'
import json, sys
card = {"number": 7, "status": "Ready", "title": sys.argv[1], "lane": "build", "labels": ["bug"]}
print("\n".join([
    'First operation, before worktree creation, classification, comments, labels or moves: run python3 .claude/bin/super-board-skills-ready.py --root "$PWD" --host claude --cards - --hydrate --lane build,',
    "with this JSON array as stdin (data, never interpolate a body into shell code): %s." % json.dumps([card], ensure_ascii=False),
    "Exit 10 means status=halted (preflight verdict=halted), detail beginning \"skills-readiness:\"; preserve all existing claims/worktrees/approval evidence.",
    "Required GitHub reads use .claude/bin/super-board-github-read.py: three total attempts, exit 79 means run halted. Check --check before any GitHub write, migration, or merge.",
    "Run super-build on issue #7 (\"%s\") for a super-board workflow wave." % sys.argv[1],
    "create your own worktree (below), work on the issue branch, post the required PR/issue comments,",
    "move the project card yourself, clean up the worktree on exit. Exit 4 = under the disk floor: status=halted, card and claims unchanged."]))
PY
}
# lctx <prompt> → the hook text compact() prints for the lane fixture project (its traps include F09)
lctx() {
  python3 - "$ENRICH" "$1" "$TMP/emptykit" "$TMP/p_lane" <<'PY' || echo "HELPER-CRASH"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
print(ec.compact(ec.enrich_prompt(sys.argv[2], sys.argv[3], sys.argv[4]), sys.argv[4]))
PY
}
RUNNER="$(cat "$TMP/lane_runner.txt")"
# The fixture is live: the same sentences in a user's own prompt still reach F09 (the trap is not dead weight).
o="$(lctx "Lane bị kẹt, log của nó: $RUNNER")"
printf '%s\n' "$o" | grep -q 'INSTINCT-F09' && ok "a user prompt quoting the lane text mid-message is classified as before (F09 shown)" \
  || fail "quoted lane text lost its trap: $o"
o="$(lctx "$RUNNER")"
[ -z "$o" ] && ok "runner lane opener (card JSON without title) → no hook text: no traps, no UI door, no intents from the harness" \
  || fail "runner lane opener still classified as a request: $o"
o="$(lctx "$(wave "Nút Lưu trên màn hình cài đặt bị bấm hai lần")")"
zs "$o" && printf '%s\n' "$o" | grep -q 'BUG_FIX' && ! printf '%s\n' "$o" | grep -q 'INSTINCT-F09' \
  && ! printf '%s\n' "$o" | grep -qE 'CODE_AND_QA_REVIEW|MERGE_CONFLICT' \
  && ok "wave lane: the card TITLE is classified (UI door + BUG_FIX), the harness text is not (no F09, no review/merge)" \
  || fail "wave lane with a UI bug title → '$o'"
o="$(lctx "$(wave "Cập nhật tài liệu hướng dẫn cài đặt cho dự án")")"
[ -z "$o" ] && ok "wave lane, title with no kind of work → no hook text ('card', 'merge', 'worktree' are the harness's)" \
  || fail "wave lane with a plain title → '$o'"
# super-build-dispatch.sh (legacy headless): opener, the worker preamble, then "# Issue #N — title", the body, a --- rule.
o="$(lctx "First operation: repeat super-board-skills-ready.py --root /repo --host claude --cards - --lane build with [{\"number\":5,\"status\":\"Ready\",\"labels\":[\"bug\"]}] as stdin. Halt on exit 10 before any lifecycle writes.
You are a builder: create your worktree, keep claims and approval evidence, stop under the disk floor.

# Issue #5 — Nút Lưu bị bấm hai lần

Trên màn hình cài đặt người dùng double click nút Lưu.

---

Working directory: /repo/.claude/worktrees/issue-5 (branch issue-5, based on main)")"
zs "$o" && printf '%s\n' "$o" | grep -q 'BUG_FIX' && ! printf '%s\n' "$o" | grep -q 'INSTINCT-F09' \
  && ok "dispatch lane: the '# Issue' title + body are classified, the preamble is not (no F09)" || fail "dispatch lane → '$o'"
has "$(intents "First operation after login crashes the app")" BUG_FIX \
  && ok "'First operation …' without the skills-ready opener is a user prompt (BUG_FIX)" || fail "anchoring: '$(intents "First operation after login crashes the app")'"
# The project-rule router (rule_context.py) reads the same harness text: the runner's "Language policy: This repository uses
# Vietnamese" sentence named the language rule sections in every lane (~380 B). The card text routes there too.
mkdir -p "$TMP/p_lane/.agents/context"
printf '%s\n' '## `.agents/local/rules/00-language-and-conventions.md`' \
  '- Quy Chuẩn Ngôn Ngữ & Báo Cáo Nghiệm Thu (Vietnamese Repository Policy) L1-17' > "$TMP/p_lane/.agents/context/rules-index.md"
rules() { python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1]}))' "$1" \
  | CLAUDE_PROJECT_DIR="$TMP/p_lane" python3 "$(dirname "$ENRICH")/rule_context.py"; }
rules "viết PR description bằng tiếng Việt theo Vietnamese repository policy" | grep -q 'Vietnamese Repository Policy' \
  && ok "rule_context: a user prompt naming the rule still gets it (control)" || fail "rule_context control lost the rule"
o="$(rules "$RUNNER")"
[ -z "$o" ] && ok "rule_context: runner lane opener → no rule section from the harness's 'Language policy' sentence" \
  || fail "rule_context: runner lane opener still routed: $o"
# OCR 25/10: the opener regex (two lazy [^\n]*? around super-board-skills-ready.py) backtracked quadratically: "First operation: " +
# "super-board-skills-ready.py " * 4000 (112 KB) took 6.17 s, and the hook runs the check up to 3 times under a 10 s timeout.
# CPU time (process_time), not wall clock: a wall bound flakes in run_impacted's parallel pool.
python3 - "$ENRICH" <<'PY' && ok "lane opener check is linear: 112 KB of skills-ready repeats, no --cards -, < 0.5 s CPU each, no lane" \
  || fail "lane opener check: quadratic or wrong on the pathological prompt"
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
p = "First operation: " + "super-board-skills-ready.py " * 4000
for name, call, lane in (("lane_card_text", ec.lane_card_text, None), ("harness_prompt", ec.harness_prompt, "super-board lane opener")):
    t0 = time.process_time(); got = call(p); cpu = time.process_time() - t0
    assert cpu < 0.5, "%s: %.2f s CPU" % (name, cpu)
    assert got != lane if lane else got is None, "%s: %r" % (name, got)
# the same check still finds the opener when the line does carry --cards - (after the repeats)
assert ec.lane_card_text(p + "--cards - with [] as stdin") == "", "opener after the repeats not found"
PY
# OCR 25/10: a lane opener followed by 200 000 "[" made raw_decode raise RecursionError (only ValueError was caught): the prompt hook
# and rule_context.py died with a traceback. The card part degrades to no words; both exit 0, no traceback.
python3 -c 'import json; print(json.dumps({"prompt": "First operation: run .claude/bin/super-board-skills-ready.py --cards - with " + "[" * 200000, "session_id": "deep-1"}))' > "$TMP/deep.json"
o="$(bash "$HOOK" < "$TMP/deep.json" 2>&1)"; rc=$?
r="$(CLAUDE_PROJECT_DIR="$TMP/p_lane" python3 "$(dirname "$ENRICH")/rule_context.py" < "$TMP/deep.json" 2>&1)"; rr=$?
[ "$rc" = 0 ] && [ "$rr" = 0 ] && ! printf '%s\n%s' "$o" "$r" | grep -q 'Traceback' \
  && ok "lane opener + 200 000 '[' (RecursionError in raw_decode): prompt hook and rule_context exit 0, no traceback" \
  || fail "deeply nested lane card: hook rc=$rc rule_context rc=$rr: $(printf '%s\n%s' "$o" "$r" | grep -m2 -E 'Traceback|Error')"
# Codex lane (.claude/bin/super-board-codex-lane.sh, fixture tests/lib/codex_lane_prompt.py): line 1 "Run super-<lane> for issue #N as a
# Codex lane worker.", line 2 the same skills-ready opener (--host codex), the card a JSON object on its own "Card: " line after a skills
# report that holds arrays. Its fixed sentences (worktree, claims, approval, merge, review) were classified as a request; now only the
# card's title/body, as for the Claude lanes. A prompt that mentions a Codex lane mid-text, or whose line 2 is no opener, is a request.
CODEX_FX="$DEVKIT_DIR/tests/lib/codex_lane_prompt.py"
CODEX="$(python3 "$CODEX_FX" "" "Xem mục cài đặt trong tài liệu hướng dẫn.")"
o="$(lctx "Lane Codex bị kẹt, log của nó: $CODEX")"
printf '%s\n' "$o" | grep -q 'INSTINCT-F09' && ok "Codex lane text quoted mid-message: classified as before (F09 shown)" \
  || fail "quoted Codex lane text lost its trap: $o"
o="$(lctx "$(python3 "$CODEX_FX" "" "Xem mục cài đặt trong tài liệu hướng dẫn." "First operation: read the board, then pick a card.")")"
printf '%s\n' "$o" | grep -q 'INSTINCT-F09' && ok "Codex first line without the skills-ready opener on line 2: a request as before (F09 shown)" \
  || fail "Codex line 1 alone taken for a lane: $o"
o="$(lctx "$CODEX")"
[ -z "$o" ] && ok "Codex lane opener (card body, no title, no kind of work) → no hook text: no traps, no UI door, no intents" \
  || fail "Codex lane opener still classified as a request: $o"
o="$(lctx "$(python3 "$CODEX_FX" "Nút Lưu trên màn hình cài đặt bị bấm hai lần" "Người dùng double click nút Lưu.")")"
zs "$o" && printf '%s\n' "$o" | grep -q 'BUG_FIX' && ! printf '%s\n' "$o" | grep -q 'INSTINCT-F09' \
  && ! printf '%s\n' "$o" | grep -qE 'CODE_AND_QA_REVIEW|MERGE_CONFLICT' \
  && ok "Codex lane: the card title/body are classified (UI door + BUG_FIX), the runner text is not (no F09, no review/merge)" \
  || fail "Codex lane with a UI bug card → '$o'"
python3 - "$ENRICH" <<'PY' && ok "Codex lane check is linear too: line 1 + 112 KB of skills-ready repeats, < 0.5 s CPU, no lane" \
  || fail "Codex lane check: quadratic or wrong on the pathological prompt"
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("ec", sys.argv[1])
ec = importlib.util.module_from_spec(spec); spec.loader.exec_module(ec)
p = "Run super-build for issue #1 as a Codex lane worker.\nFirst operation: " + "super-board-skills-ready.py " * 4000
t0 = time.process_time(); got = ec.lane_card_text(p); cpu = time.process_time() - t0
assert cpu < 0.5 and got is None, (cpu, got)
PY
# rule_context: a rule keyed on the Codex runner's own words (worktree, merge, GitHub quota) is not routed for a Codex lane.
mkdir -p "$TMP/p_codex/.agents/context"
printf '%s\n' '## `.agents/local/rules/10-lane.md`' '- Worktree, merge gate và GitHub quota của lane (Lane Worktree Merge Quota) L1-9' \
  > "$TMP/p_codex/.agents/context/rules-index.md"
crules() { python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1]}))' "$1" \
  | CLAUDE_PROJECT_DIR="$TMP/p_codex" python3 "$(dirname "$ENRICH")/rule_context.py"; }
crules "dọn worktree của lane rồi merge gate, nhớ quota GitHub" | grep -q 'Lane Worktree Merge Quota' \
  && ok "rule_context: a user prompt naming the lane rule gets it (control)" || fail "rule_context Codex control lost the rule"
o="$(crules "$CODEX")"
[ -z "$o" ] && ok "rule_context: Codex lane opener → no rule section from the runner's sentences" \
  || fail "rule_context: Codex lane opener still routed: $o"

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
