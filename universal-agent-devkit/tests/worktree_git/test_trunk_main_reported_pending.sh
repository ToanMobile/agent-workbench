#!/usr/bin/env bash
# Hồi quy (agent-workbench 24-25/10, trunk mode): prompt hook (hooks/prompt_context.sh -> scripts/context/enrich_context.py capture_bug)
# ghi dòng REPORTED của một prompt tả bug thẳng vào .agents/regression_status.json + CHECKLIST.md ĐƯỢC TRACK của MAIN checkout:
# CLAUDE_PROJECT_DIR vẫn là main sau EnterWorktree (hooks/session_worktree.py), main không phải worktree liên kết nên
# regression_checklist.skip_bookkeeping() cho ghi. Main luôn bẩn đúng hai file mà gần như mọi lần gộp đều chạm: `git pull --ff-only` và
# `agent-kit worktree finish` (merge --ff-only) bị từ chối (main có 52-53 dòng bug origin không có).
# Merge driver không sửa được chuyện đó: git từ chối fast-forward đè lên sửa đổi chưa commit trước khi chạy driver nào.
# Giờ main ở trunk mode không ghi checklist track của nó: dòng chờ trong <git common dir>/postfix-gate/pending_rows.json (không bao giờ
# track, KHÔNG hạn tuổi, khác overlay 6 h của worktree), regression_checklist.load_view đọc nó ở main và ở mọi worktree, và nó chỉ vào
# checklist khi người xử lý nó (`agent-kit bugs link|add --id|drop` trong worktree: đúng dòng đó, commit cùng việc). Nó rời sổ khi HEAD
# của main đã có nó, hoặc người đã drop - không bao giờ vì tuổi: không mất bug nào đã báo.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"; PROMPT_HOOK="$DEVKIT_DIR/hooks/prompt_context.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset PROMPT_CONTEXT BUG_CAPTURE DEVKIT_WORKTREE_CHECKLIST WORKTREE_TRUNK_MODE CLAUDE_PROJECT_DIR DEVKIT_GATE_CACHE_MAX_S
export HOME="$TMP/home"; mkdir -p "$HOME"

# mk <dir>: repo track checklist (rỗng) và ma trận; không có khoá devkit.trunkMode = trunk mode BẬT, mặc định
mk() {
  mkdir -p "$1/src" "$1/.agents" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  echo 'def add(a, b): return a + b' > src/calc.py
  cat > .agents/regression_matrix.active.json <<'JSON'
{"adopted": true, "rules":[{"component":"Calc","watch_files":["src/*.py"],"mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"true"}]}]}
JSON
  printf '.claude/\n.agents/regression_journal/\n' > .gitignore
  python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r; r.save(pathlib.Path(sys.argv[2]), {'version': 1, 'items': {}}, stale=False)" \
    "$DEVKIT_DIR/bin" "$1" || fail "dựng $1: save hỏng"
  git add -A && git commit -qm init
}
dirty() { git -C "$1" status --porcelain --untracked-files=all -- .agents; }   # sổ sách checklist mà main phải giữ sạch
prompt() {  # prompt <checkout> <phiên> <text>: ngữ cảnh hook in ra, payload như Claude Code gửi (có transcript_path: không phải probe)
  python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": sys.argv[2], "transcript_path": sys.argv[3]}))' "$3" "$2" "$TMP/tr.jsonl" \
    | CLAUDE_PROJECT_DIR="$1" bash "$PROMPT_HOOK" 2>/dev/null; }
bug_id() { printf '%s' "$1" | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1; }
view() {  # view <checkout> <id> <khoá>: một trường của dòng như hook ở checkout đó đọc (load_view)
  python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
v = r.load_view(pathlib.Path(sys.argv[2]))['items'].get(sys.argv[3]); print('MISSING' if v is None else v.get(sys.argv[4]))" \
    "$DEVKIT_DIR/bin" "$1" "$2" "$3" 2>/dev/null; }
nbugs() { python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
print(len([1 for v in r.load_view(pathlib.Path(sys.argv[2]))['items'].values() if v.get('kind') == 'bug']))" "$DEVKIT_DIR/bin" "$1" 2>/dev/null; }
tracked() {  # tracked <checkout> <id>: dòng trong file track trên đĩa của checkout đó ("MISSING", "no-test" hoặc test đã link)
  python3 -c "import json, sys; v = json.load(open(sys.argv[1] + '/.agents/regression_status.json'))['items'].get(sys.argv[2])
print('MISSING' if v is None else ','.join(v.get('tests') or []) or 'no-test')" "$1" "$2" 2>/dev/null; }
pending() { python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
print(' '.join(sorted(r.read_pending(pathlib.Path(sys.argv[2])))))" "$DEVKIT_DIR/bin" "$1" 2>/dev/null; }

P="$TMP/main"; W="$TMP/main-wt"; mk "$P"
git -C "$P" worktree add -q --detach "$W" >/dev/null 2>&1 || fail "dựng: worktree add"

# 1. chính lỗi: prompt tả bug ở main trunk mode làm checklist track của main bẩn
out="$(prompt "$P" s1 "App bị crash khi cộng hai số")"; B1="$(bug_id "$out")"
[ -n "$B1" ] && printf '%s' "$out" | grep -q "Bug đã ghi vào checklist: $B1" || fail "1: prompt tả bug không được ghi nhận: $out"
[ -z "$(dirty "$P")" ] && ok "1: main trunk mode: prompt tả bug để checklist track của main sạch" \
  || fail "1: main trunk mode bẩn sau prompt tả bug (pull --ff-only / worktree finish bị từ chối): $(dirty "$P" | tr '\n' ' ')"

# 2. dòng không mất: main và worktree đều đọc được, cùng prompt lần nữa không thêm trùng
[ "$(view "$P" "$B1" state)" = reported ] && [ "$(view "$W" "$B1" state)" = reported ] \
  && ok "2: load_view ở main và ở worktree liên kết đều thấy dòng REPORTED" || fail "2: main='$(view "$P" "$B1" state)' worktree='$(view "$W" "$B1" state)'"
out="$(prompt "$P" s2 "App bị crash khi cộng hai số")"
[ "$(bug_id "$out")" = "$B1" ] && [ "$(nbugs "$P")" = 1 ] && [ -z "$(dirty "$P")" ] \
  && ok "2b: cùng prompt tả bug lần nữa: đúng dòng cũ, không trùng, main vẫn sạch" || fail "2b: id=$(bug_id "$out") (cần $B1) rows=$(nbugs "$P") dirty=$(dirty "$P")"

# 3. không hạn tuổi: overlay của worktree chỉ tin dòng trong DEVKIT_GATE_CACHE_MAX_S; bug đã báo phải sống lâu hơn thế
sleep 2
[ "$(DEVKIT_GATE_CACHE_MAX_S=1 view "$P" "$B1" state)" = reported ] && [ "$(DEVKIT_GATE_CACHE_MAX_S=1 view "$W" "$B1" state)" = reported ] \
  && ok "3: dòng chờ không hạn tuổi (DEVKIT_GATE_CACHE_MAX_S=1, sau 2 s vẫn đọc được)" || fail "3: dòng hết hạn như dòng overlay"

# 4. người xử lý nó trong worktree: đúng dòng đó vào checklist của worktree (commit cùng việc), main vẫn sạch
out="$(prompt "$P" s1 "Lỗi tràn số khi nhân số rất lớn bị crash")"; B2="$(bug_id "$out")"
[ -n "$B2" ] && [ "$B2" != "$B1" ] || fail "4: prompt tả bug thứ hai không thành dòng riêng: $out"
( cd "$W" && bash "$KIT" bugs link "$B1" REG-A >/dev/null 2>&1 ) || fail "4: agent-kit bugs link $B1 trong worktree hỏng"
[ "$(tracked "$W" "$B1")" = REG-A ] && [ "$(tracked "$W" "$B2")" = MISSING ] && [ -z "$(dirty "$P")" ] \
  && ok "4: bugs link trong worktree ghi đúng dòng đó (đã link) vào checklist của worktree, không kéo dòng chờ khác; main sạch" \
  || fail "4: worktree B1='$(tracked "$W" "$B1")' B2='$(tracked "$W" "$B2")' main dirty='$(dirty "$P")'"
[ "$(view "$W" "$B1" fixed)" = True ] && [ "$(view "$P" "$B1" state)" = reported ] \
  && ok "4b: worktree đọc dòng (đã link) của chính nó, main vẫn đọc dòng chờ" || fail "4b: worktree fixed='$(view "$W" "$B1" fixed)' main='$(view "$P" "$B1" state)'"

# 5. việc về main (fast-forward: main sạch nên không bị từ chối); dòng đó rời sổ, dòng khác ở lại
git -C "$W" add -A .agents >/dev/null 2>&1 && git -C "$W" commit -qm "link $B1" >/dev/null 2>&1 || fail "5: worktree không có gì để commit"
WH="$(git -C "$W" rev-parse HEAD)"
git -C "$P" merge -q --ff-only "$WH" >/dev/null 2>&1 && [ "$(git -C "$P" rev-parse HEAD)" = "$WH" ] \
  && ok "5: main fast-forward tới commit của worktree (không có sửa checklist cục bộ cản đường)" || fail "5: merge --ff-only bị từ chối: $(dirty "$P")"
prompt "$P" s3 "Màn hình kết quả bị trắng khi chia cho 0" >/dev/null
p="$(pending "$P")"
case " $p " in *" $B1 "*) fail "5b: $B1 đã ở HEAD của main mà vẫn trong sổ chờ ($p)" ;; *" $B2 "*) ok "5b: dòng HEAD của main đã có rời sổ, dòng khác ở lại ($p)" ;;
  *) fail "5b: $B2 mất khỏi sổ chờ ($p)" ;; esac
[ "$(view "$P" "$B1" fixed)" = True ] && [ -z "$(dirty "$P")" ] && ok "5c: main đọc dòng đã gộp từ checklist track của nó, vẫn sạch" \
  || fail "5c: main B1 fixed='$(view "$P" "$B1" fixed)' dirty='$(dirty "$P")'"

# 6. người drop một dòng chờ: mất khỏi sổ và mọi view, không ghi vào đâu
( cd "$W" && bash "$KIT" bugs drop "$B2" >/dev/null 2>&1 ) || fail "6: agent-kit bugs drop $B2 trong worktree hỏng"
[ "$(view "$P" "$B2" state)" = MISSING ] && [ "$(view "$W" "$B2" state)" = MISSING ] && [ "$(tracked "$W" "$B2")" = MISSING ] \
  && ok "6: bugs drop một dòng chờ xoá nó khỏi sổ và mọi view" || fail "6: main='$(view "$P" "$B2" state)' worktree='$(view "$W" "$B2" state)'"

# 8. HEAD của main đã giữ dòng REPORTED cũ (💤 auto_closed): báo lại cùng bug mở lại nó trong view, sổ giữ bản mới tới khi HEAD có bản
#    mới bằng hoặc hơn (không bị prune ngay vì "HEAD đã có id")
D="$TMP/reopen"; mk "$D"
python3 -c "import sys, pathlib; sys.path.insert(0, sys.argv[1]); import regression_checklist as r
p = pathlib.Path(sys.argv[2]); d = r.load(p)
d['items']['BUG-20260101-old'] = {'id': 'BUG-20260101-old', 'kind': 'bug', 'title': 'App bị crash khi mở ảnh lớn', 'component': '-', 'tests': [],
  'state': 'auto_closed', 'created_at': '2026-01-01 00:00:00', 'touched_at': '2026-01-01 00:00:00', 'sessions': ['s0'], 'last': None, 'history': []}
r.save(p, d, stale=False)" "$DEVKIT_DIR/bin" "$D" && git -C "$D" add -A .agents && git -C "$D" commit -qm "old reported row" || fail "8: dựng dòng cũ"
out="$(prompt "$D" s9 "App bị crash khi mở ảnh lớn")"
[ "$(bug_id "$out")" = BUG-20260101-old ] && [ "$(view "$D" BUG-20260101-old state)" = reported ] && [ -z "$(dirty "$D")" ] \
  && case " $(pending "$D") " in *" BUG-20260101-old "*) true ;; *) false ;; esac \
  && ok "8: báo lại một bug HEAD đã giữ (💤): view mở lại nó (REPORTED), sổ giữ bản mới, main sạch" \
  || fail "8: id='$(bug_id "$out")' state='$(view "$D" BUG-20260101-old state)' pending='$(pending "$D")' dirty='$(dirty "$D")'"
# 8b. một lệnh `bugs` về bug KHÁC trong worktree không ghi bản chờ, và dòng track bị nó che vẫn nguyên (không bị xoá khi lọc dòng chờ)
DW="$TMP/reopen-wt"; git -C "$D" worktree add -q --detach "$DW" >/dev/null 2>&1 || fail "8b: worktree add"
( cd "$DW" && bash "$KIT" bugs add "Nút lưu không phản hồi" --module ui >/dev/null 2>&1 ) || fail "8b: bugs add trong worktree hỏng"
st8="$(python3 -c "import json, sys; print(json.load(open(sys.argv[1] + '/.agents/regression_status.json'))['items'].get('BUG-20260101-old', {}).get('state'))" "$DW" 2>/dev/null)"
[ "$st8" = auto_closed ] && ok "8b: bugs add một bug khác: dòng track bị bản chờ che vẫn nguyên trong file của worktree (auto_closed)" \
  || fail "8b: dòng track BUG-20260101-old trong worktree thành '$st8'"

# 7. đối chứng: main checkout kiểu cũ (trunk mode tắt) vẫn ghi dòng vào checklist track, không có sổ chờ
C="$TMP/classic"; mk "$C"; git -C "$C" config devkit.trunkMode false
out="$(prompt "$C" s1 "App bị crash khi cộng hai số")"; BC="$(bug_id "$out")"
[ -n "$BC" ] && [ "$(tracked "$C" "$BC")" = no-test ] && [ -n "$(dirty "$C")" ] && [ -z "$(pending "$C")" ] \
  && ok "7: đối chứng: trunk mode tắt, prompt tả bug ghi checklist track như trước" || fail "7: đối chứng: id='$BC' tracked='$(tracked "$C" "${BC:-x}")' pending='$(pending "$C")'"

echo
[ "$FAILS" = 0 ] && { echo "test_trunk_main_reported_pending: PASS"; exit 0; }
echo "test_trunk_main_reported_pending: $FAILS FAIL"; exit 1
