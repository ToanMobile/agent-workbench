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

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENRICH="$DEVKIT_DIR/scripts/enrich_context.py"
HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"
INDEXER="$DEVKIT_DIR/scripts/index_memory.py"
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
