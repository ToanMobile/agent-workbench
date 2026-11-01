#!/usr/bin/env bash
# Test hồi quy (#770): scoped_gate.decide bỏ path ghim HEAD (tree_fp.HEAD_PINNED: .claude/settings.json) khi nó CHỈ bẩn ở cây làm việc,
# đối xứng #691 (vân tay và biên nhận lấy bản của HEAD). Đo 31/10 trên OfficeReader: `agent-kit init` để settings.json bẩn, một test có chuỗi
# "settings.json" bị chọn và lượt --scoped của PR chỉ đổi AGENTS.md chạy build Gradle (:feature:*:testDebugUnitTest).
#   a. AGENTS.md đổi đã commit + settings.json chỉ bẩn ⇒ changed không có settings.json, tests rỗng, head_pinned nêu nó;
#   b. settings.json đổi đã commit (merge-base..HEAD) và còn bẩn thêm ⇒ vẫn vào changed, test đọc nó được chọn;
#   c. settings.json đổi đã commit, cây sạch ⇒ vào changed như cũ;
#   d. settings.json mới chưa track (HEAD không có, như tree_fp bỏ khỏi vân tay) ⇒ không vào changed;
#   e. project là thư mục con của repo: <sub>/.claude/settings.json chỉ bẩn ⇒ bỏ (path tương đối project, như tree_fp);
#   f. base không phân giải được (changed truyền sẵn, merge-base lỗi) ⇒ giữ nguyên settings.json (fail closed: thừa test, không thiếu);
#   h. base "HEAD" (lượt không --diff) ⇒ settings.json chỉ bẩn vẫn bị bỏ;
#   e2. project thư mục con: settings.json đổi đã commit và còn bẩn ⇒ giữ (đường dẫn --relative khớp nhau);
#   i. HEAD đã commit settings.json, cây làm việc bị ghi đè về bản base (git diff <mb> -- không thấy) ⇒ vẫn vào changed (như tree_fp);
#   j. base là vế trái của `--diff A..B` và nhánh A sửa settings.json sau merge-base ⇒ giữ (đổi giữa base và HEAD);
#   k. HEAD giữ thư mục ở chỗ path ghim (tree_fp từ chối) ⇒ fail closed, không bỏ gì;
#   j2. cùng cây j, changed tự tính (CLI `decide --base <nhánh rẽ>`): commit của base sau điểm rẽ không phải đổi của nhánh ⇒ settings.json
#       chỉ bẩn vẫn bị bỏ; cây sạch thì không bị thêm vào; j3. caller truyền changed không có settings.json ⇒ không thêm vào;
#   g. post-fix-gate --run-tests --scoped --diff <base>: suite của luật ma trận phủ test đọc settings.json (vai suite Gradle) KHÔNG chạy khi
#      settings.json chỉ bẩn; CHẠY khi settings.json đổi đã commit.
# Python stdlib, tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_SLOT_PRIORITY CLAUDE_PROJECT_DIR TARGET_DIR

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SG="$DEVKIT_DIR/bin/scoped_gate.py"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"   # khoá slot riêng (không đụng gate thật của máy)
export DEVKIT_GATE_SLOTS=0 WORKTREE_TRUNK_MODE=0 VACUITY_REVERT=0
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Dựng repo: base có AGENTS.md, .claude/settings.json (đã track) và một test nhắc chuỗi "settings.json" (vai ReaderEditViewModelTest.kt).
# $1 = thư mục repo, $2 = tiền tố project trong repo ("" hoặc "sub/").
make_repo() {
  local r="$1" p="$2"
  rm -rf "$r" && mkdir -p "$r/${p}.claude" "$r/${p}tests/x" && cd "$r" || exit 2
  git init -q -b main . && git config user.email t@t && git config user.name t
  printf '.claude/*\n!.claude/settings.json\n' > "${p}.gitignore"
  printf '# hướng dẫn\n' > "${p}AGENTS.md"
  printf '{"hooks": {}}\n' > "${p}.claude/settings.json"
  printf '#!/usr/bin/env bash\n# đọc cấu hình của harness\ngrep -q hooks .claude/settings.json\n' > "${p}tests/x/test_reads_settings.sh"
  git add -A && git commit -qm base
  BASE="$(git rev-parse HEAD)"
}
# decide → một dòng "changed=…|tests=…|pinned=…"; $1 = project, $2 = base, $3 = changed truyền sẵn (tuỳ chọn, cách nhau dấu phẩy)
decide() {
  python3 - "$SG" "$1" "$2" "${3:-}" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sg_pinned", sys.argv[1]); m = importlib.util.module_from_spec(spec)
sys.modules["sg_pinned"] = m; spec.loader.exec_module(m)
changed = [c for c in sys.argv[4].split(",") if c] or None
r = m.decide(sys.argv[2], sys.argv[3], changed=changed)
print("changed=%s|tests=%s|pinned=%s" % (",".join(r["changed"]), ",".join(r["tests"]), ",".join(r.get("head_pinned") or [])))
PY
}
# đổi settings.json đã commit: khối hooks hợp lệ (gate kiểm schema hooks của Claude Code)
commit_settings() { printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "true"}]}]}}\n' > .claude/settings.json; }
dirty_settings() { printf '{"hooks": {"Stop": []}}\n' > "${1}.claude/settings.json"; }

# ── a. AGENTS.md đổi đã commit + settings.json chỉ bẩn
R="$TMP/a"; make_repo "$R" ""
printf '# hướng dẫn mới\n' > AGENTS.md && git commit -qam docs
dirty_settings ""
OUT="$(decide "$R" "$BASE")"
case "$OUT" in
  "changed=AGENTS.md|tests=|pinned=.claude/settings.json") ok "a. settings.json chỉ bẩn ⇒ không vào changed, tests rỗng, head_pinned nêu nó" ;;
  *) fail "a. settings.json chỉ bẩn: $OUT (mong changed=AGENTS.md|tests=|pinned=.claude/settings.json)" ;;
esac

# ── b. settings.json đổi đã commit và còn bẩn thêm
R="$TMP/b"; make_repo "$R" ""
commit_settings && git commit -qam settings
dirty_settings ""
OUT="$(decide "$R" "$BASE")"
case "$OUT" in
  "changed=.claude/settings.json|tests=tests/x/test_reads_settings.sh|pinned=") ok "b. settings.json đổi đã commit (còn bẩn thêm) ⇒ vẫn vào changed, chọn test đọc nó" ;;
  *) fail "b. settings.json đổi đã commit + bẩn: $OUT" ;;
esac

# ── c. settings.json đổi đã commit, cây sạch
R="$TMP/c"; make_repo "$R" ""
commit_settings && git commit -qam settings
OUT="$(decide "$R" "$BASE")"
case "$OUT" in
  "changed=.claude/settings.json|tests=tests/x/test_reads_settings.sh|pinned=") ok "c. settings.json đổi đã commit, cây sạch ⇒ vào changed như cũ" ;;
  *) fail "c. settings.json đổi đã commit: $OUT" ;;
esac

# ── d. settings.json mới chưa track (HEAD không có)
R="$TMP/d"; make_repo "$R" ""
git rm -q --cached .claude/settings.json && git commit -qm untrack
BASE="$(git rev-parse HEAD)"
printf '# hướng dẫn mới\n' > AGENTS.md && git commit -qam docs
dirty_settings ""
OUT="$(decide "$R" "$BASE")"
case "$OUT" in
  "changed=AGENTS.md|tests=|pinned=.claude/settings.json") ok "d. settings.json chưa track ⇒ không vào changed" ;;
  *) fail "d. settings.json chưa track: $OUT" ;;
esac

# ── e. project là thư mục con của repo
R="$TMP/e"; make_repo "$R" "sub/"
printf '# hướng dẫn mới\n' > sub/AGENTS.md && git commit -qam docs
dirty_settings "sub/"
OUT="$(decide "$R/sub" "$BASE")"
case "$OUT" in
  "changed=AGENTS.md|tests=|pinned=.claude/settings.json") ok "e. project thư mục con: settings.json của project chỉ bẩn ⇒ bỏ" ;;
  *) fail "e. project thư mục con: $OUT" ;;
esac

# ── f. base không phân giải được ⇒ fail closed (giữ settings.json)
R="$TMP/f"; make_repo "$R" ""
dirty_settings ""
OUT="$(decide "$R" "no-such-ref" ".claude/settings.json")"
case "$OUT" in
  "changed=.claude/settings.json|tests=tests/x/test_reads_settings.sh|pinned=") ok "f. base không phân giải được ⇒ giữ settings.json (fail closed)" ;;
  *) fail "f. base hỏng: $OUT" ;;
esac

# ── h. base "HEAD" (lượt không --diff: post-fix-gate đặt base_ref = "HEAD") ⇒ settings.json chỉ bẩn vẫn bị bỏ
R="$TMP/h"; make_repo "$R" ""
dirty_settings ""
OUT="$(decide "$R" "HEAD")"
case "$OUT" in
  "changed=|tests=|pinned=.claude/settings.json") ok "h. base HEAD: settings.json chỉ bẩn ⇒ bỏ, tests rỗng" ;;
  *) fail "h. base HEAD: $OUT (mong changed=|tests=|pinned=.claude/settings.json)" ;;
esac

# ── e2. project thư mục con: đổi đã commit + còn bẩn ⇒ giữ
R="$TMP/e2"; make_repo "$R" "sub/"
(cd sub && commit_settings) && git commit -qam settings
dirty_settings "sub/"
OUT="$(decide "$R/sub" "$BASE")"
case "$OUT" in
  "changed=.claude/settings.json|tests=tests/x/test_reads_settings.sh|pinned=") ok "e2. project thư mục con: đổi đã commit + bẩn ⇒ giữ, chọn test đọc nó" ;;
  *) fail "e2. project thư mục con, đổi đã commit: $OUT" ;;
esac

# ── i. HEAD đã commit settings.json, cây làm việc bị ghi đè về đúng bản base
R="$TMP/i"; make_repo "$R" ""
commit_settings && git commit -qam settings
git show "$BASE:.claude/settings.json" > .claude/settings.json
OUT="$(decide "$R" "$BASE")"
case "$OUT" in
  "changed=.claude/settings.json|tests=tests/x/test_reads_settings.sh|pinned=") ok "i. đổi đã commit, cây làm việc về bản base ⇒ vẫn vào changed như tree_fp" ;;
  *) fail "i. đổi đã commit, cây làm việc về bản base: $OUT" ;;
esac

# ── j. base = vế trái của dải, nhánh đó sửa settings.json sau merge-base; HEAD không sửa, cây làm việc bẩn
R="$TMP/j"; make_repo "$R" ""
git checkout -q -b other && commit_settings && git commit -qam other-settings && A="$(git rev-parse HEAD)" && git checkout -q main
printf '# hướng dẫn mới\n' > AGENTS.md && git commit -qam docs
dirty_settings ""
OUT="$(decide "$R" "$A" ".claude/settings.json,AGENTS.md")"
case "$OUT" in
  "changed=.claude/settings.json,AGENTS.md|tests=tests/x/test_reads_settings.sh|pinned=") ok "j. base nhánh rẽ đã sửa settings.json ⇒ giữ (đổi giữa base và HEAD)" ;;
  *) fail "j. base nhánh rẽ: $OUT" ;;
esac
OUT="$(decide "$R" "$A")"
case "$OUT" in
  "changed=AGENTS.md|tests=|pinned=.claude/settings.json") ok "j2. changed tự tính, base nhánh rẽ: commit của base không phải đổi của nhánh ⇒ settings.json chỉ bẩn bị bỏ" ;;
  *) fail "j2. changed tự tính, base nhánh rẽ (bẩn): $OUT (mong changed=AGENTS.md|tests=|pinned=.claude/settings.json)" ;;
esac
OUT="$(decide "$R" "$A" "AGENTS.md")"
case "$OUT" in
  "changed=AGENTS.md|tests=|pinned=") ok "j3. caller truyền changed không có settings.json ⇒ không thêm vào" ;;
  *) fail "j3. caller truyền changed: $OUT (mong changed=AGENTS.md|tests=|pinned=)" ;;
esac
git show "HEAD:.claude/settings.json" > .claude/settings.json
OUT="$(decide "$R" "$A")"
case "$OUT" in
  "changed=AGENTS.md|tests=|pinned=") ok "j2c. changed tự tính, base nhánh rẽ, cây sạch ⇒ không thêm settings.json" ;;
  *) fail "j2c. changed tự tính, base nhánh rẽ (sạch): $OUT (mong changed=AGENTS.md|tests=|pinned=)" ;;
esac

# ── k. HEAD giữ thư mục ở chỗ path ghim ⇒ fail closed
R="$TMP/k"; make_repo "$R" ""
git rm -q .claude/settings.json && mkdir -p .claude/settings.json && printf '1\n' > .claude/settings.json/a && git add -f .claude/settings.json/a && git commit -qm dir
BASE="$(git rev-parse HEAD)"
printf '2\n' > .claude/settings.json/a
OUT="$(decide "$R" "$BASE")"
case "$OUT" in
  "changed=.claude/settings.json/a|"*"|pinned=") ok "k. HEAD giữ thư mục ở path ghim ⇒ không bỏ gì (fail closed như tree_fp)" ;;
  *) fail "k. HEAD giữ thư mục ở path ghim: $OUT" ;;
esac

# ── g. end-to-end: suite của luật ma trận phủ test đọc settings.json (vai suite Gradle) theo bẩn / đã commit
gate_case() {   # $1 = nhãn, $2 = "dirty" | "committed"; in số lần suite nặng chạy
  local r="$TMP/g-$1"
  make_repo "$r" ""
  cat > matrix.json <<JSON
{"project": "t", "rules": [{"component": "Features", "watch_files": ["tests/x/*"],
  "mandatory_regression_tests": [{"id": "REG-FEAT", "name": "vai Gradle", "command": "echo ran >> '$TMP/heavy.$1'; true"}]}]}
JSON
  git add matrix.json && git commit -qm matrix
  BASE="$(git rev-parse HEAD)"
  if [ "$2" = committed ]; then
    commit_settings && git commit -qam settings
  else
    printf '# hướng dẫn mới\n' > AGENTS.md && git commit -qam docs
    dirty_settings ""
  fi
  CLAUDE_PROJECT_DIR="$r" python3 "$GATE" --matrix "$r/matrix.json" --run-tests --scoped --diff "$BASE" --no-checklist > "$TMP/g-$1.out" 2>&1
  echo "rc=$? heavy=$( [ -f "$TMP/heavy.$1" ] && wc -l < "$TMP/heavy.$1" | tr -d ' ' || echo 0)"
}
G1="$(gate_case dirty dirty)"
case "$G1" in
  "rc=0 heavy=0") ok "g. --scoped: settings.json chỉ bẩn ⇒ suite nặng của luật phủ test đọc nó không chạy ($G1)" ;;
  *) fail "g. --scoped: settings.json chỉ bẩn mà suite nặng vẫn chạy ($G1): $(grep -E 'REG-FEAT|KẾT LUẬN|VERDICT' "$TMP/g-dirty.out" | head -3 | tr '\n' ' ')" ;;
esac
G2="$(gate_case committed committed)"
case "$G2" in
  "rc=0 heavy=1") ok "g. --scoped: settings.json đổi đã commit ⇒ suite nặng chạy như cũ ($G2)" ;;
  *) fail "g. --scoped: settings.json đổi đã commit ($G2): $(tail -4 "$TMP/g-committed.out" | tr '\n' ' ')" ;;
esac

echo "─────"
[ "$FAILS" -eq 0 ] && { echo "PASS test_scoped_gate_head_pinned"; exit 0; }
echo "FAIL test_scoped_gate_head_pinned: $FAILS ca"; exit 1
