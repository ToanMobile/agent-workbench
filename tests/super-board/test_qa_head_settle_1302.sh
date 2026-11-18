#!/usr/bin/env bash
# #1302: đầu PR đổi trong lúc QA thì QA bỏ kết quả cũ, đợi head đứng yên rồi chạy lại trên head mới;
# chỉ Blocked khi head vẫn đổi sau N lần thử. Chạy offline với origin là repo bare cục bộ. Bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

HEADCHK="$ROOT/.claude/bin/super-board-qa-head.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qa-head.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

G() { git -c user.name=t -c user.email=t@t "$@"; }
G init -q --bare "$TMP/origin.git"
G clone -q "$TMP/origin.git" "$TMP/w" 2>/dev/null
cd "$TMP/w" || exit 1
G checkout -q -b pr
commit() { echo "$1" > f; G add f; G commit -q -m "$1"; G push -q origin pr 2>/dev/null; G rev-parse HEAD; }
C1=$(commit one)
ORIG="$TMP/origin.git"
run() { (cd "$TMP/w" && SB_QA_HEAD_REMOTE="$ORIG" bash "$HEADCHK" "$@" 2>&1); }

# 1. Head khớp sha QA đang chạy: giữ kết quả, exit 0.
out=$(run --branch pr --sha "$C1" --settle 1 --poll 1); rc=$?
[ "$rc" = 0 ] && ok "head khớp → exit 0 (current)" || fail "head khớp: rc=$rc out=$out"

# 2. Head đã đổi trước khi kiểm: bỏ kết quả cũ, đợi đứng yên, trả head mới, exit 10 (chạy lại).
C2=$(commit two)
out=$(run --branch pr --sha "$C1" --settle 1 --poll 1 --attempt 1 --max-tries 3); rc=$?
if [ "$rc" = 10 ] && printf '%s' "$out" | grep -q "rerun $C2"; then ok "head đổi → exit 10 rerun trên head mới"; else fail "head đổi: rc=$rc out=$out"; fi

# 3. Head còn đổi trong lúc đợi: đợi tới khi đứng yên rồi báo head cuối.
( sleep 1; cd "$TMP/w" && echo three > f && G add f && G commit -q -m three && G push -q origin pr 2>/dev/null ) &
BG=$!
out=$(run --branch pr --sha "$C1" --settle 3 --poll 1 --attempt 1 --max-tries 3); rc=$?
wait "$BG"
C3=$(cd "$TMP/w" && G rev-parse HEAD)
if [ "$rc" = 10 ] && printf '%s' "$out" | grep -q "rerun $C3"; then ok "head đổi giữa lúc đợi → báo head cuối"; else fail "head đổi giữa lúc đợi: rc=$rc out=$out"; fi

# 4. Quá N lần thử mà head vẫn đổi: exit 11 kèm lý do và số lần.
out=$(run --branch pr --sha "$C1" --settle 1 --poll 1 --attempt 3 --max-tries 3); rc=$?
if [ "$rc" = 11 ] && printf '%s' "$out" | grep -q "3" && printf '%s' "$out" | grep -qi "head"; then ok "quá N lần → exit 11 kèm lý do và số lần"; else fail "quá N lần: rc=$rc out=$out"; fi

# 5. Head không bao giờ đứng yên trong --max-wait: exit 11.
( for i in 1 2 3 4 5 6; do sleep 1; cd "$TMP/w" && echo "x$i" > f && G add f && G commit -q -m "x$i" && G push -q origin pr 2>/dev/null; done ) &
BG=$!
out=$(run --branch pr --sha "$C1" --settle 3 --poll 1 --max-wait 4 --attempt 1 --max-tries 3); rc=$?
wait "$BG"
[ "$rc" = 11 ] && ok "head không đứng yên trong max-wait → exit 11" || fail "không đứng yên: rc=$rc out=$out"

# 6. ls-remote lỗi giữa lúc đợi: không coi là đứng yên (không rerun giả), exit 11.
C6=$(commit six)
mv "$ORIG" "$ORIG.gone"
out=$(run --branch pr --sha "$C1" --settle 1 --poll 1 --attempt 1 --max-tries 3); rc=$?
mv "$ORIG.gone" "$ORIG"
[ "$rc" = 11 ] && ok "ls-remote lỗi → exit 11, không rerun giả" || fail "ls-remote lỗi: rc=$rc out=$out"
# 6b. Lỗi ls-remote xuất hiện sau lần đọc đầu (head đã khác sha QA): vẫn exit 11.
( sleep 0.5; mv "$ORIG" "$ORIG.gone"; sleep 2; mv "$ORIG.gone" "$ORIG" ) &
BG=$!
out=$(run --branch pr --sha "$C1" --settle 2 --poll 1 --attempt 1 --max-tries 3); rc=$?
wait "$BG"
[ "$rc" = 11 ] && ok "ls-remote lỗi giữa lúc đợi → exit 11" || fail "ls-remote lỗi giữa lúc đợi: rc=$rc out=$out"

# 7. Cờ thiếu giá trị (--sha cuối dòng): báo blocked rõ ràng, không lỗi shift.
out=$(run --branch pr --sha); rc=$?
if [ "$rc" = 11 ] && ! printf '%s' "$out" | grep -qi "shift"; then ok "cờ thiếu giá trị → exit 11 gọn"; else fail "cờ thiếu giá trị: rc=$rc out=$out"; fi

# 8. Cờ số không phải số (R5): exit 11 gọn, không lỗi bash, không rơi vào vòng đợi.
for flag in --attempt --max-tries --settle --poll --max-wait; do
  out=$(run --branch pr --sha "$C1" "$flag" abc); rc=$?
  if [ "$rc" = 11 ] && ! printf '%s' "$out" | grep -qi "integer expression"; then ok "cờ số $flag=abc → exit 11"; else fail "cờ số $flag=abc: rc=$rc out=$out"; fi
done

# 9. run.md bước 6 (R4): đầu đổi sau 5b thì quay lại 5b, không Block thẻ.
RUNMD="${RUNMD_OVERRIDE:-$ROOT/.claude/skills/super-board/references/run.md}"
step6=$(grep -n '^6\. \*\*Pass\*\*' "$RUNMD" | head -1 | cut -d: -f2-)
if printf '%s' "$step6" | grep -q "5b" && ! printf '%s' "$step6" | grep -q "is not <sha>, do not retry or force: Block the card"; then ok "run.md bước 6 chuyển về 5b khi đầu đổi"; else fail "run.md bước 6 vẫn Block khi đầu đổi"; fi

# 10. Major audit T0002: (1) bước 6 không Block vô điều kiện trước nhánh 5b — push non-ff do đầu đổi
# phải quay về 5b; (2) 5b đưa nhánh cục bộ lên <sha> để lượt K+1 ff được.
step5b=$(grep -n '^5b\. ' "$RUNMD" | head -1 | cut -d: -f2-)
if printf '%s' "$step6" | grep -q "non-fast-forward" && ! printf '%s' "$step6" | grep -q "any command exits non-zero, do not retry or force: Block"; then ok "run.md bước 6: push non-ff do đầu đổi → 5b, không Block"; else fail "run.md bước 6 còn Block vô điều kiện khi lệnh thoát khác 0"; fi
if printf '%s' "$step5b" | grep -q "merge --ff-only" && printf '%s' "$step5b" | grep -q "branch -f"; then ok "run.md 5b đưa nhánh cục bộ lên <sha> trước lượt K+1"; else fail "run.md 5b không cập nhật nhánh cục bộ"; fi

echo "---"
[ "$FAILS" = 0 ] && echo "PASS" || { echo "FAIL: $FAILS"; exit 1; }
