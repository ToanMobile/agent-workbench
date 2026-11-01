#!/usr/bin/env bash
# #731 (1): super-board-ac-check.py tính foreign_closes trên tập số đã bỏ tiền tố repo. PR Closes #32 (thành viên đợt) và
# Closes other/repo#32: hai Closes cùng thành số 32, 32 là thành viên nên bị trừ ⇒ issue #32 của repo KHÁC đóng mà merge gate
# không chặn exit 11. Cùng lớp: Closes other/repo#31 trên nhánh issue-31 bị trừ như thẻ của nhánh.
# Luật mới: `owner/repo#N` của repo khác luôn là thẻ lạ; `<repo của chính checkout>#N` (origin, không phân biệt hoa thường) là #N ở
# đây; không đọc được origin ⇒ mọi `owner/repo#N` là repo khác (fail-closed). --rewrite-closes --foreign cùng luật (X9–X11).
# origin đọc ở SB_REPO_PATH khi có (merge gate export repo.path của board), không thì cwd (X12). Offline, bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AC="${SB_AC:-$ROOT/.claude/bin/super-board-ac-check.py}"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
field() { python3 -c 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print(json.dumps(v) if isinstance(v,(list,bool)) or v is None else v)' "$1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-ac-cross.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_CEILING_DIRECTORIES="$TMP"   # $TMP/nogit không được thấy repo git nào bọc ngoài $TMP
unset SB_REPO_PATH   # merge gate export biến này cho verify; chỉ X12 đặt nó

# Hai checkout giả: origin là repo này (ToanMobile/agent-workbench) và origin là repo khác; một thư mục không phải git.
git init -q "$TMP/own" && git -C "$TMP/own" remote add origin https://github.com/ToanMobile/agent-workbench.git
git init -q "$TMP/else" && git -C "$TMP/else" remote add origin git@github.com:someone/else.git
mkdir -p "$TMP/nogit"
ac() { local dir="$1"; shift; (cd "$TMP/$dir" && python3 "$AC" "$@" 2>"$TMP/err"); }

# Thân thẻ thành viên #32 của đợt #31, như create_task.py ghi.
printf '## Acceptance Criteria\n- [ ] M32\n\n## Blocked by\n- #31 — đợt\n<!-- sb:batch-of #31 -->\n' > "$TMP/m32.md"

# X1 — ca của thẻ: Closes #32 (thành viên) + Closes other/repo#32 ⇒ 32 vẫn là thẻ lạ (issue repo khác), batch vẫn [32].
printf 'Closes #31\nCloses #32\nCloses other/repo#32\n' > "$TMP/x1.md"
out=$(ac own --pr-body "$TMP/x1.md" --branch issue-31-dot --batch-member-body "32=$TMP/m32.md")
[ "$(printf '%s' "$out" | field foreign_closes)" = "[32]" ] && [ "$(printf '%s' "$out" | field batch)" = "[32]" ] \
  && ok "X1 Closes #32 (thành viên) + Closes other/repo#32 → foreign_closes [32], batch [32]" || fail "X1 $out $(cat "$TMP/err")"

# X2 — repo khác trùng số với thẻ của nhánh: Closes other/repo#31 trên issue-31 là thẻ lạ, Closes #31 vẫn là thẻ của nhánh.
printf 'Closes #31\nCloses other/repo#31\n' > "$TMP/x2.md"
out=$(ac own --pr-body "$TMP/x2.md" --branch issue-31-dot)
[ "$(printf '%s' "$out" | field foreign_closes)" = "[31]" ] && [ "$(printf '%s' "$out" | field closes_own)" = true ] \
  && ok "X2 Closes other/repo#31 trên nhánh issue-31 → foreign_closes [31]" || fail "X2 $out $(cat "$TMP/err")"

# X3 — message squash cũng vậy (văn bản thô): PR Closes #32 thành viên, commit Fixes other/repo#32.
printf 'Closes #31\nCloses #32\n' > "$TMP/x3.md"; printf 'x\n\nFixes: other/repo#32\n' > "$TMP/x3msg.md"
out=$(ac own --pr-body "$TMP/x3.md" --msg "$TMP/x3msg.md" --branch issue-31-dot --batch-member-body "32=$TMP/m32.md")
[ "$(printf '%s' "$out" | field foreign_closes)" = "[32]" ] && ok "X3 Fixes: other/repo#32 trong message squash → foreign_closes [32]" || fail "X3 $out"

# X4 — repo của chính checkout viết đầy đủ (hoa thường tuỳ ý) KHÔNG phải repo khác: thẻ nhánh vẫn là của nó, không exit 11.
printf 'Closes toanmobile/Agent-Workbench#31\n' > "$TMP/x4.md"
out=$(ac own --pr-body "$TMP/x4.md" --branch issue-31-dot)
[ "$(printf '%s' "$out" | field foreign_closes)" = "[]" ] && [ "$(printf '%s' "$out" | field closes_own)" = true ] \
  && ok "X4 Closes <repo này>#31 trên issue-31 → không foreign, closes_own" || fail "X4 $out $(cat "$TMP/err")"

# X5 — thành viên đợt viết đầy đủ repo của chính checkout: vẫn là thành viên (cùng thẻ #32 ở đây).
printf 'Closes #31\nCloses ToanMobile/agent-workbench#32\n' > "$TMP/x5.md"
out=$(ac own --pr-body "$TMP/x5.md" --branch issue-31-dot --batch-member-body "32=$TMP/m32.md")
[ "$(printf '%s' "$out" | field foreign_closes)" = "[]" ] && [ "$(printf '%s' "$out" | field batch)" = "[32]" ] \
  && ok "X5 Closes <repo này>#32 có marker đợt #31 → thành viên, không foreign" || fail "X5 $out $(cat "$TMP/err")"

# X6 — cùng PR chạy trong checkout của repo KHÁC: ToanMobile/agent-workbench#32 là repo khác ⇒ thẻ lạ.
out=$(ac else --pr-body "$TMP/x5.md" --branch issue-31-dot --batch-member-body "32=$TMP/m32.md")
[ "$(printf '%s' "$out" | field foreign_closes)" = "[32]" ] && [ "$(printf '%s' "$out" | field batch)" = "[]" ] \
  && ok "X6 origin là repo khác → ToanMobile/agent-workbench#32 là thẻ lạ" || fail "X6 $out $(cat "$TMP/err")"

# X7 — không đọc được origin (không phải git): mọi owner/repo#N là repo khác (fail-closed), ac-check vẫn chạy (exit 0).
out=$(ac nogit --pr-body "$TMP/x4.md" --branch issue-31-dot); rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s' "$out" | field foreign_closes)" = "[31]" ] \
  && ok "X7 không đọc được origin → owner/repo#31 tính là repo khác (fail-closed)" || fail "X7 rc=$rc $out $(cat "$TMP/err")"

# X8 — không có owner/repo nào: hành vi cũ giữ nguyên (thành viên không foreign, thẻ lạ vẫn foreign).
printf 'Closes #31\nCloses #32\nCloses #40\n' > "$TMP/x8.md"
out=$(ac nogit --pr-body "$TMP/x8.md" --branch issue-31-dot --batch-member-body "32=$TMP/m32.md")
[ "$(printf '%s' "$out" | field foreign_closes)" = "[40]" ] && [ "$(printf '%s' "$out" | field batch)" = "[32]" ] \
  && ok "X8 chỉ Closes #N: thành viên [32], thẻ lạ [40] như cũ" || fail "X8 $out $(cat "$TMP/err")"

# X9 — đường log của merge gate (không --body-file): `--rewrite-closes --foreign` phải đổi cả Closes repo khác trùng số thẻ của
# nhánh; đọc lại thì không còn thẻ lạ (không thì gate exit 11 sau verify, hay đóng issue của repo khác).
printf '* fix\n\nFixes other/repo#31\nCloses #31\nCloses #40\n' > "$TMP/x9.md"
r=$(ac own --rewrite-closes "$TMP/x9.md" --card 31 --foreign)
out=$(ac own --pr-body /dev/null --msg "$TMP/x9.md" --branch issue-31-dot)
[ "$r" = rewritten ] && grep -q '^Refs other/repo#31$' "$TMP/x9.md" && grep -q '^Closes #31$' "$TMP/x9.md" && grep -q '^Refs #40$' "$TMP/x9.md" \
  && [ "$(printf '%s' "$out" | field foreign_closes)" = "[]" ] \
  && ok "X9 --rewrite-closes --foreign: Fixes other/repo#31 → Refs, Closes #31 giữ, đọc lại foreign_closes []" \
  || fail "X9 r=$r out=$out file=$(tr '\n' '|' < "$TMP/x9.md") $(cat "$TMP/err")"

# X10 — chỉ `Closes other/repo#31` trên nhánh issue-31: không phải PR đóng thẻ của nhánh (closes_own false).
printf 'Closes other/repo#31\n' > "$TMP/x10.md"
out=$(ac own --pr-body "$TMP/x10.md" --branch issue-31-dot)
[ "$(printf '%s' "$out" | field closes_own)" = false ] && [ "$(printf '%s' "$out" | field foreign_closes)" = "[31]" ] \
  && ok "X10 chỉ Closes other/repo#31 → closes_own false, foreign_closes [31]" || fail "X10 $out $(cat "$TMP/err")"

# X11 — `<repo này>#31` (origin) vẫn là thẻ của nhánh: --foreign giữ nguyên.
printf 'Fixes ToanMobile/agent-workbench#31\n' > "$TMP/x11.md"
r=$(ac own --rewrite-closes "$TMP/x11.md" --card 31 --foreign)
[ "$r" = unchanged ] && grep -q '^Fixes ToanMobile/agent-workbench#31$' "$TMP/x11.md" \
  && ok "X11 --foreign giữ Fixes <repo này>#31" || fail "X11 r=$r file=$(cat "$TMP/x11.md") $(cat "$TMP/err")"

# X12 — merge gate export SB_REPO_PATH (repo.path của board): own_repo đọc origin ở đó, không theo cwd (cwd không phải git).
printf 'Closes ToanMobile/agent-workbench#31\n' > "$TMP/x12.md"
out=$(SB_REPO_PATH="$TMP/own" ac nogit --pr-body "$TMP/x12.md" --branch issue-31-dot)
[ "$(printf '%s' "$out" | field foreign_closes)" = "[]" ] && [ "$(printf '%s' "$out" | field closes_own)" = true ] \
  && ok "X12 SB_REPO_PATH = checkout của repo này: <repo này>#31 là thẻ của nhánh dù cwd không phải git" || fail "X12 $out $(cat "$TMP/err")"

[ "$FAILS" -eq 0 ] && { echo "ac-check cross-repo: all checks passed"; exit 0; }
echo "ac-check cross-repo: $FAILS FAILED"; exit 1
