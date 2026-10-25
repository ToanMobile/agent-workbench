#!/usr/bin/env bash
# Test hồi quy cho .claude/bin/super-board-github-read.py với `gh` giả (offline).
# 2026-10-16: lệnh đọc gõ sai của một worker (sai số đối số, `--comments` đi cùng `--json`) bị thử lại 3 lần rồi
# ghi file halt (exit 79): cả board dừng vì lỗi của một lệnh. Lỗi cú pháp của người gọi phải trả exit 64 kèm
# dạng lệnh đúng, không halt, và không được âm thầm sửa lệnh (bỏ `--comments` làm agent tưởng "không có comment").
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-ghread-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
# gh giả: thông báo lỗi đúng như gh 2.100.0 in ra (đo 2026-10-16).
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
case " $* " in
  *" --comments "*" --json "*|*" --json "*" --comments "*) echo 'specify only one of `--comments` or `--json`' >&2; exit 1 ;;
  *" pr view 1 2 3 "*) echo 'accepts between 1 and 2 arg(s), received 3' >&2; exit 1 ;;
  *" pr view 1 2 "*) echo 'accepts at most 1 arg(s), received 2' >&2; exit 1 ;;
  *" --bogus "*) echo 'unknown flag: --bogus' >&2; exit 1 ;;
  *" issue view "*) echo '{"number":5,"title":"t","body":"b"}' ;;
  *" api rate_limit --jq "*) echo 'graphql=4979/5000 rest=4999/5000' ;;
  *" api rate_limit "*) echo '{"resources":{}}' ;;
  *) echo 'unexpected' >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 GH_CALLS="$TMP/calls"
unset SB_GITHUB_READ_STRICT

run() { python3 "$READ" "$@" >"$TMP/out" 2>"$TMP/err"; echo $?; }

rc=$(run --kind head -- pr view 1 2)
[ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ok "wrong arg count ('accepts at most 1 arg'): exit 64, board not halted" \
  || fail "wrong arg count: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
rm -f "$TMP/halt.json"

# Lệnh có khoảng số đối số (cobra RangeArgs) báo "accepts between N and M arg(s)": cũng là lỗi của người gọi.
rc=$(run --kind head -- pr view 1 2 3)
[ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ok "wrong arg count ('accepts between 1 and 2 arg(s)'): exit 64, board not halted" \
  || fail "'accepts between 1 and 2 arg(s)': rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
rm -f "$TMP/halt.json"

# Kind không có dạng mẫu trong FORMS (vd scalar): lỗi cú pháp vẫn là của người gọi, exit 64 không halt,
# không traceback, và không bịa gợi ý "Valid form" cho kind không có mẫu.
rc=$(run --kind scalar -- pr view 9 --bogus)
[ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ! grep -q Traceback "$TMP/err" && ! grep -q 'Valid form' "$TMP/err" \
  && ok "caller flag error on a kind outside FORMS: exit 64, not halted, no traceback, no invented form" \
  || fail "flag error on kind scalar: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
rm -f "$TMP/halt.json"

# Script có lệnh cố định (merge gate) đặt SB_GITHUB_READ_STRICT=1: lỗi cú pháp ở đó là lỗi của script, vẫn halt.
rc=$(SB_GITHUB_READ_STRICT=1 run --kind scalar -- pr view 9 --bogus)
[ "$rc" = 79 ] && [ -e "$TMP/halt.json" ] && ok "SB_GITHUB_READ_STRICT=1: a flag error still halts (fixed commands)" \
  || fail "SB_GITHUB_READ_STRICT=1 flag error: rc=$rc (want 79 + halt file)"
rm -f "$TMP/halt.json"

# Script do chính board chạy với lệnh cố định (super-board-deps.sh trong chuỗi sweep Blocked của runner): gh đổi flag
# (vd máy có gh chưa có --slurp) vẫn halt board kèm lý do, không thành exit 64 "lỗi của người gọi" lặp mỗi 300 s.
mkdir -p "$TMP/oldgh"
printf '#!/usr/bin/env bash\necho "unknown flag: --slurp" >&2\nexit 1\n' > "$TMP/oldgh/gh"; chmod +x "$TMP/oldgh/gh"
PATH="$TMP/oldgh:$PATH" bash "$ROOT/.claude/bin/super-board-deps.sh" --repo o/r >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 79 ] && [ -e "$TMP/halt.json" ] && ok "fixed-command board script (deps.sh) with a broken gh flag: board halted (79 + reason)" \
  || fail "deps.sh with a broken gh flag: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
rm -f "$TMP/halt.json"

# 2026-10-16 20:45 OfficeReader: một worker đọc quota bằng `--kind quota -- api rate_limit --jq "graphql=…"` (in chuỗi, không
# phải JSON). Payload sai dạng ở cả 3 lần thử là lỗi đọc của người gọi với MỌI kind, không chỉ kind trong FORMS: exit 64,
# không halt cả board, không bịa gợi ý "Valid form" cho kind không có mẫu. (quota + --jq nay bị chặn trước khi gọi gh,
# xem ca 17/10 bên dưới; ca này dùng kind object để vẫn phủ nhánh payload sai dạng chung.)
rc=$(run --kind object -- api rate_limit --jq '"graphql=\(.resources.graphql.remaining)"')
[ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ! grep -q 'Valid form' "$TMP/err" \
  && ok "malformed read on a kind outside FORMS (object + --jq string): exit 64, board not halted" \
  || fail "object read with --jq string: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
rm -f "$TMP/halt.json"
# Lệnh cố định của runner (STRICT) mà nhận payload sai dạng thì vẫn halt: có thể là GitHub trả thiếu dữ liệu thật.
rc=$(SB_GITHUB_READ_STRICT=1 run --kind quota -- api rate_limit)
[ "$rc" = 79 ] && [ -e "$TMP/halt.json" ] && ok "SB_GITHUB_READ_STRICT=1: a malformed payload still halts (fixed commands)" \
  || fail "SB_GITHUB_READ_STRICT=1 malformed payload: rc=$rc (want 79 + halt file)"
rm -f "$TMP/halt.json"

# 2026-10-17 00:22 OfficeReader: worker QA #84 tự viết dòng gh-quota-on-exit bằng `--kind quota api rate_limit --jq "…"`
# (không có `--`). kind quota cần JSON rate_limit thô, nên --jq/-q/--template là lỗi của người gọi biết trước khi gọi gh:
# từ chối ngay (exit 64, 0 lần gọi gh, không retry, không halt, kể cả STRICT — halt chỉ để --resume phát lại lệnh hỏng),
# và chỉ đường sb_gh_guard_summary.
for form in "api rate_limit --jq \"graphql=\\(.resources.graphql.remaining)\"" "-- api rate_limit -q .resources" \
            "-- api rate_limit --template {{.resources}}" "-- api rate_limit --jq=.resources.core"; do
  for strict in "" 1; do
    : > "$TMP/calls"
    eval "set -- $form"
    rc=$(SB_GITHUB_READ_STRICT=$strict run --kind quota "$@")
    [ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && [ ! -s "$TMP/calls" ] && ! grep -q 'retry 2/3' "$TMP/err" \
      && grep -q 'sb_gh_guard_summary' "$TMP/err" \
      && ok "quota + output filter rejected before any gh call (strict=${strict:-0}): $form" \
      || fail "quota + output filter (strict=${strict:-0}) $form: rc=$rc gh_calls=$(wc -l <"$TMP/calls" | tr -d ' ') halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) ($(tail -1 "$TMP/err"))"
    rm -f "$TMP/halt.json"
  done
done
unset SB_GITHUB_READ_STRICT

# deps.sh chuyển graph sang super-board-approval.py, script này đọc GitHub qua module github-read (kind comments/approval/
# permission) cũng bằng lệnh cố định: STRICT phải tới được nó, nếu không sự cố GitHub thật bị nuốt thành "approval evidence
# could not be verified" (audit T0041). Bản sao deps.sh với github-read/approval giả ghi lại STRICT mà approval nhận.
mkdir -p "$TMP/sbbin"
cp "$ROOT/.claude/bin/super-board-deps.sh" "$TMP/sbbin/"
cat > "$TMP/sbbin/super-board-github-read.py" <<'PYF'
import json
print(json.dumps([{"data": {"repository": {"issues": {"nodes": [
    {"number": 1, "title": "t", "body": "", "state": "OPEN", "labels": {"nodes": []}, "comments": {"nodes": []}}]}}}}]))
PYF
cat > "$TMP/sbbin/super-board-approval.py" <<'PYF'
import os, sys
open(os.environ["SB_TEST_STRICT_OUT"], "w").write(os.environ.get("SB_GITHUB_READ_STRICT", "unset"))
sys.stdout.write(sys.stdin.read())
PYF
SB_TEST_STRICT_OUT="$TMP/strict.out" bash "$TMP/sbbin/super-board-deps.sh" --repo o/r >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$TMP/strict.out" 2>/dev/null)" = 1 ] \
  && ok "deps.sh: approval reads (fixed commands) run with SB_GITHUB_READ_STRICT=1" \
  || fail "deps.sh: approval.py got SB_GITHUB_READ_STRICT=$(cat "$TMP/strict.out" 2>/dev/null) rc=$rc ($(tail -1 "$TMP/err"))"

rc=$(run --kind issue -- issue view 5 --json number,title,body --comments)
[ "$rc" = 64 ] && [ ! -e "$TMP/halt.json" ] && ok "--comments with --json: reported (exit 64), not silently dropped, not halted" \
  || fail "--comments with --json: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo yes || echo no) out=$(head -c 80 "$TMP/out")"
rm -f "$TMP/halt.json"

rc=$(run --kind issue -- issue view 5 --json number,title,body)
[ "$rc" = 0 ] && grep -q '"number"' "$TMP/out" && ok "valid read still works" || fail "valid read: rc=$rc"

# 2026-10-19 agent-workbench: một lệnh ghi (`gh issue edit`) hỏng để lại halt có operation null. --resume từ chối (đúng: không có
# lệnh đọc nào để phát lại) nhưng cũng không có đường khởi động lại nào ngoài sửa tay file halt, mà trunk mode cấm sửa tay ở
# main. `--resume --reconciled "<lý do>"`: người đã đối chiếu kết quả ghi trên GitHub ghi lý do; helper chỉ đọc quota (không
# phát lại lệnh ghi), rồi chuyển file halt sang github-halt-reconciled-<stamp>.json kèm lý do, không xoá bản ghi gốc.
mkdir -p "$TMP/okgh" "$TMP/downgh"
cat > "$TMP/okgh/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
case " $* " in
  *" api rate_limit "*) echo '{"resources":{"graphql":{"remaining":4000,"reset":1},"core":{"remaining":4000,"reset":1}}}' ;;
  *) echo 'unexpected' >&2; exit 1 ;;
esac
SH
printf '#!/usr/bin/env bash\necho "$*" >> "$GH_CALLS"\necho "HTTP 502" >&2\nexit 1\n' > "$TMP/downgh/gh"
chmod +x "$TMP/okgh/gh" "$TMP/downgh/gh"
NULL_HALT='{"reason": "GitHub issue edit response failed; reconcile the write before restarting", "attempts": 1, "at": 1792352832, "operation": null}'
archives() { ls "$TMP" | grep -c '^github-halt-reconciled-' | tr -d ' '; }
reset_halt() { rm -f "$TMP"/github-halt-reconciled-*; printf '%s' "$1" > "$TMP/halt.json"; : > "$TMP/calls"; }

reset_halt "$NULL_HALT"
rc=$(PATH="$TMP/okgh:$PATH" run --resume)
[ "$rc" = 79 ] && [ "$(cat "$TMP/halt.json")" = "$NULL_HALT" ] && ok "op-null halt: plain --resume still refuses (79), record untouched" \
  || fail "op-null plain --resume: rc=$rc"

reset_halt "$NULL_HALT"
rc=$(PATH="$TMP/okgh:$PATH" run --resume --reconciled '   ')
[ "$rc" = 64 ] && [ "$(cat "$TMP/halt.json")" = "$NULL_HALT" ] && [ "$(archives)" = 0 ] && [ ! -s "$TMP/calls" ] \
  && ok "--reconciled with a blank reason: refused (64), halt kept, no gh call" || fail "blank --reconciled: rc=$rc archives=$(archives)"

reset_halt "$NULL_HALT"
rc=$(PATH="$TMP/okgh:$PATH" run --reconciled 'issue #7 checked')
[ "$rc" = 64 ] && [ -e "$TMP/halt.json" ] && [ "$(archives)" = 0 ] && ok "--reconciled without --resume: refused (64), halt kept" \
  || fail "--reconciled without --resume: rc=$rc"

reset_halt "$NULL_HALT"
rc=$(PATH="$TMP/downgh:$PATH" run --resume --reconciled 'issue #7 checked')
[ "$rc" = 79 ] && [ "$(cat "$TMP/halt.json")" = "$NULL_HALT" ] && [ "$(archives)" = 0 ] \
  && ok "--resume --reconciled while GitHub is down: still halted (79), record untouched" || fail "reconciled + gh down: rc=$rc archives=$(archives)"

reset_halt "$NULL_HALT"
rc=$(PATH="$TMP/okgh:$PATH" run --resume --reconciled 'issues #7/#12 checked on GitHub: edit applied')
arch=$(ls "$TMP"/github-halt-reconciled-*.json 2>/dev/null | head -1)
[ "$rc" = 0 ] && [ ! -e "$TMP/halt.json" ] && [ "$(archives)" = 1 ] && [ "$(grep -vxc 'api rate_limit' "$TMP/calls" | tr -d ' ')" = 0 ] \
  && python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["reason"].startswith("GitHub issue edit response failed") and r["operation"] is None; assert r["reconciled"]["reason"]=="issues #7/#12 checked on GitHub: edit applied" and type(r["reconciled"]["at"]) is int' "$arch" \
  && ok "--resume --reconciled '<why>': only a quota read, halt moved to github-halt-reconciled-*.json with the original record + reason" \
  || fail "reconciled resume: rc=$rc halt=$([ -e "$TMP/halt.json" ] && echo kept || echo gone) archives=$(archives) calls=$(tr '\n' ';' <"$TMP/calls") ($(tail -1 "$TMP/err"))"

reset_halt '{"reason": "r", "attempts": 3, "at": 1, "operation": {"args": ["issue", "view", "5", "--json", "number,title,body"], "kind": "issue", "meta": null}}'
rc=$(PATH="$TMP/okgh:$PATH" run --resume --reconciled 'not needed')
[ "$rc" = 64 ] && [ -e "$TMP/halt.json" ] && [ "$(archives)" = 0 ] && [ ! -s "$TMP/calls" ] \
  && ok "--reconciled on a halt with a saved read: refused (64), the read replay stays the way out" || fail "reconciled on op-dict halt: rc=$rc"
rm -f "$TMP/halt.json"

reset_halt "$NULL_HALT"
rc=$(PATH="$TMP/okgh:$PATH" run --resume --reconciled 'checked' -- issue view 5 --json number,title,body)
[ "$rc" = 64 ] && [ "$(cat "$TMP/halt.json")" = "$NULL_HALT" ] && [ "$(archives)" = 0 ] && [ ! -s "$TMP/calls" ] \
  && ok "--reconciled with a read command: refused (64), halt kept, no gh call" || fail "reconciled + command: rc=$rc"

# Ghi bản lưu hỏng (thư mục không ghi được): board vẫn dừng, bản ghi gốc nguyên vẹn, không sót file tạm.
if [ "$(id -u)" = 0 ]; then ok "archive write fails: skipped (root ignores chmod 555)"; else
  mkdir -p "$TMP/ro"; printf '%s' "$NULL_HALT" > "$TMP/ro/halt.json"; chmod 555 "$TMP/ro"; : > "$TMP/calls"
  rc=$(SB_GITHUB_HALT_FILE="$TMP/ro/halt.json" PATH="$TMP/okgh:$PATH" run --resume --reconciled 'checked')
  chmod 755 "$TMP/ro"
  [ "$rc" = 64 ] && [ "$(cat "$TMP/ro/halt.json")" = "$NULL_HALT" ] && [ "$(ls "$TMP/ro" | tr '\n' ' ')" = "halt.json " ] \
    && ok "archive write fails: still halted, original record intact, no temp file left" || fail "archive write failure: rc=$rc files=$(ls "$TMP/ro" | tr '\n' ' ')"
fi
rm -f "$TMP/halt.json"

: > "$TMP/calls"
rc=$(PATH="$TMP/okgh:$PATH" run --resume --reconciled 'nothing halted')
[ "$rc" = 0 ] && [ "$(archives)" = 0 ] && [ ! -s "$TMP/calls" ] && ok "--resume --reconciled with no halt: nothing to do (0), no gh call" \
  || fail "reconciled without halt: rc=$rc"

# File halt là trạng thái chạy của board, không phải nội dung main: trunk mode chỉ cho động vào nó khi git bỏ qua nó.
for f in github-halt.json github-halt-reconciled-1.json github-halt-1792344209094738000.json; do
  git -C "$ROOT" check-ignore -q ".claude/super-board/$f" && ok "git ignores runtime state .claude/super-board/$f" \
    || fail ".claude/super-board/$f is not git-ignored (trunk mode treats it as main content)"
done

# PR hơn 100 file (OfficeReader #170: 103 file, 20/10): `gh pr view --json files` chỉ trả 100 file nên kiểm
# changedFiles == len(files) hỏng ở cả 3 lần, merge gate (STRICT) halt cả board vĩnh viễn (phát lại vẫn hỏng). Danh sách
# đủ lấy qua REST có phân trang; REST vẫn thiếu thì vẫn là bằng chứng thiếu.
mkdir -p "$TMP/bigpr"
cat > "$TMP/bigpr/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
case " $* " in
  *" pr view 170 "*) python3 -c 'import json; print(json.dumps({"labels": [], "body": "b", "additions": 206, "deletions": 0, "changedFiles": 103, "files": [{"path": "f%d" % i, "additions": 2, "deletions": 0} for i in range(100)]}))' ;;
  *" api repos/o/r/pulls/170/files "*) python3 -c 'import json, os; n = 101 if os.environ.get("BIGPR_SHORT") else 103; files = [{"filename": "f%d" % i, "additions": 2, "deletions": 0} for i in range(n)]; print(json.dumps([files[:100], files[100:]]))' ;;
  *" api rate_limit "*) echo '{"resources":{}}' ;;
  *) echo 'unexpected' >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bigpr/gh"; rm -f "$TMP/halt.json"
rc=$(SB_GITHUB_READ_STRICT=1 PATH="$TMP/bigpr:$PATH" run --kind metadata -- pr view 170 --repo o/r --json labels,files,additions,deletions,changedFiles,body)
n=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["files"]))' "$TMP/out" 2>/dev/null)
[ "$rc" = 0 ] && [ "$n" = 103 ] && [ ! -e "$TMP/halt.json" ] && ok "PR with 103 files: full list fetched via paginated REST, no halt" \
  || fail "big PR: rc=$rc files=$n halt=$( [ -e "$TMP/halt.json" ] && echo yes || echo no) err=$(head -c 200 "$TMP/err")"
rm -f "$TMP/halt.json"
rc=$(BIGPR_SHORT=1 SB_GITHUB_READ_STRICT=1 PATH="$TMP/bigpr:$PATH" run --kind metadata -- pr view 170 --repo o/r --json labels,files,additions,deletions,changedFiles,body)
[ "$rc" = 79 ] && [ -e "$TMP/halt.json" ] && ok "REST list still short of changedFiles → still incomplete evidence (halt in strict mode)" || fail "short REST list accepted: rc=$rc"
rm -f "$TMP/halt.json"

# #425 (PR #424 của DevKit, 156 file, 26/10): REST liệt kê một file đổi loại (symlink thành file thường) thành HAI mục cùng
# filename, còn changedFiles đếm một: 157 mục cho 156 file. So số mục thô thì halt cả board dù danh sách đủ. Đếm theo path duy
# nhất; thiếu path thật vẫn halt (ca BIGPR_SHORT ở trên).
cat > "$TMP/bigpr/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
case " $* " in
  *" pr view 171 "*) python3 -c 'import json; print(json.dumps({"labels": [], "body": "b", "additions": 206, "deletions": 0, "changedFiles": 103, "files": [{"path": "f%d" % i, "additions": 2, "deletions": 0} for i in range(100)]}))' ;;
  *" api repos/o/r/pulls/171/files "*) python3 -c 'import json; files = [{"filename": "f%d" % i, "additions": 2, "deletions": 0} for i in range(103)]; files.insert(6, {"filename": "f5", "additions": 0, "deletions": 2}); print(json.dumps([files[:100], files[100:]]))' ;;
  *" api rate_limit "*) echo '{"resources":{}}' ;;
  *) echo 'unexpected' >&2; exit 1 ;;
esac
SH
rc=$(SB_GITHUB_READ_STRICT=1 PATH="$TMP/bigpr:$PATH" run --kind metadata -- pr view 171 --repo o/r --json labels,files,additions,deletions,changedFiles,body)
n=$(python3 -c 'import json,sys; print(len({f["path"] for f in json.load(open(sys.argv[1]))["files"]}))' "$TMP/out" 2>/dev/null)
[ "$rc" = 0 ] && [ "$n" = 103 ] && [ ! -e "$TMP/halt.json" ] && ok "PR whose REST list repeats a path (type change): 103 unique paths, no halt" \
  || fail "REST path repeated: rc=$rc paths=$n halt=$( [ -e "$TMP/halt.json" ] && echo yes || echo no) err=$(head -c 200 "$TMP/err")"
rm -f "$TMP/halt.json"

[ "$FAILS" -eq 0 ] && echo "✅ test_github_read: all passed" || { echo "❌ test_github_read: $FAILS failed"; exit 1; }
