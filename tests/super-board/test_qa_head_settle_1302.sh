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
SYNC="$ROOT/.claude/bin/super-board-qa-sync.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qa-head.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

G() { git -c user.name=t -c user.email=t@t "$@"; }
G init -q --bare "$TMP/origin.git"
G clone -q "$TMP/origin.git" "$TMP/w" 2>/dev/null
cd "$TMP/w" || exit 1
G checkout -q -b pr
commit() { echo "$1" > f; G add f; G commit -q -m "$1"; G push -q origin pr 2>/dev/null; G rev-parse HEAD; }
C1=$(commit one)
G push -q origin pr:main 2>/dev/null
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

# 6. ls-remote lỗi (origin biến mất): không coi là đứng yên (không rerun giả), exit 11.
commit six >/dev/null
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
if printf '%s' "$step5b" | grep -q "super-board-qa-sync.sh"; then ok "run.md 5b đưa nhánh cục bộ lên <sha> trước lượt K+1 (qa-sync)"; else fail "run.md 5b không cập nhật nhánh cục bộ"; fi

# 11. Major audit T0003: chạy git thật vòng push non-ff → 5b → K+1. Bằng chứng QA E1 đã commit vào nhánh
# cục bộ, push bị từ chối vì phiên khác đẩy S: `merge --ff-only S` lỗi (phân kỳ), 5b phải đặt lại nhánh về S
# (worktree sạch, chỉ khác S ở commit QA bị hủy) để lượt K+1 ff được bằng chứng mới.
G clone -q "$ORIG" "$TMP/qa" 2>/dev/null
( cd "$TMP/qa" && G checkout -q -B pr origin/pr && mkdir -p docs/super-board/runs && echo e1 > docs/super-board/runs/ev && G add -A && G commit -q -m "qa evidence v1" )
S0=$(cd "$TMP/qa" && G rev-parse origin/pr)
( cd "$TMP/w" && G pull -q --ff-only origin pr 2>/dev/null; echo other > g && G add g && G commit -q -m "other session" && G push -q origin pr 2>/dev/null )
S=$(cd "$TMP/w" && G rev-parse HEAD)
if ( cd "$TMP/qa" && G push -q origin pr >/dev/null 2>&1 ); then fail "11: push non-ff đáng ra bị từ chối"; else ok "11: push non-ff bị từ chối khi đầu đổi"; fi
out=$(cd "$TMP/qa" && SB_QA_HEAD_REMOTE="$ORIG" bash "$HEADCHK" --branch pr --sha "$S0" --settle 1 --poll 1 --attempt 1 --max-tries 3 2>&1); rc=$?
[ "$rc" = 10 ] && printf '%s' "$out" | grep -q "rerun $S" && ok "11: helper báo rerun trên $S" || fail "11: helper: rc=$rc out=$out"
cd "$TMP/qa" && G fetch -q origin
if G merge --ff-only "$S" >/dev/null 2>&1; then fail "11: ff-only đáng ra phải lỗi (nhánh cục bộ phân kỳ)"; else ok "11: ff-only lỗi vì nhánh cục bộ mang commit QA cũ"; fi
# 5b gọi helper qa-sync (worker không gõ lệnh git bị hook chặn): worktree sạch, chỉ khác S ở commit QA → về S.
out=$(SB_QA_HEAD_REMOTE="$ORIG" bash "$SYNC" --branch pr --sha "$S" --worktree "$TMP/qa" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "11: qa-sync rc=0 ($out)" || fail "11: qa-sync rc=$rc out=$out"
[ "$(G rev-parse HEAD)" = "$S" ] && ok "11: 5b đặt lại nhánh về $S" || fail "11: nhánh chưa về S"
mkdir -p docs/super-board/runs && echo e2 > docs/super-board/runs/ev2
G add -A && G commit -q -m "qa evidence v2"
if G push -q origin pr >/dev/null 2>&1 && [ "$(G ls-remote origin refs/heads/pr | cut -f1)" = "$(G rev-parse HEAD)" ]; then ok "11: lượt K+1 đẩy bằng chứng ff được"; else fail "11: lượt K+1 không đẩy được"; fi
cd "$TMP/w" || exit 1
# run.md 5b phải gọi helper qa-sync, không còn lệnh git bị hook chặn.
if printf '%s' "$step5b" | grep -q "super-board-qa-sync.sh" && ! printf '%s' "$step5b" | grep -Eq "reset --hard|branch -f"; then ok "11: run.md 5b gọi qa-sync, không reset --hard / branch -f"; else fail "11: run.md 5b chưa dùng qa-sync hoặc còn lệnh bị chặn"; fi

# 12. Nit: --attempt 08 không bị hiểu là bát phân.
out=$(run --branch pr --sha "$C1" --settle 1 --poll 1 --attempt 08 --max-tries 10); rc=$?
if [ "$rc" = 10 ] && ! printf '%s' "$out" | grep -qi "value too great"; then ok "12: --attempt 08 hiểu là thập phân"; else fail "12: --attempt 08: rc=$rc out=$out"; fi

# 13. Lệnh worker gõ (gọi helper qua bash) đi qua hook block-dangerous-git.sh mà không bị chặn; lệnh thô thì bị chặn.
HOOK="$ROOT/.claude/hooks/block-dangerous-git.sh"
hook_rc() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" | bash "$HOOK" >/dev/null 2>&1; echo $?; }
[ "$(hook_rc "bash .claude/bin/super-board-qa-sync.sh --branch pr --sha $S --worktree /tmp/w")" = 0 ] && ok "13: hook cho qa-sync chạy" || fail "13: hook chặn qa-sync"
[ "$(hook_rc "git -C /tmp/w reset --hard $S")" = 2 ] && ok "13: hook vẫn chặn reset --hard thô" || fail "13: hook không chặn reset --hard thô"

# 14. qa-sync từ chối: nhánh mang thay đổi ngoài docs/super-board/runs/; worktree bẩn; thiếu cờ. Không đụng nhánh.
G clone -q "$ORIG" "$TMP/qb" 2>/dev/null
( cd "$TMP/qb" && G checkout -q -B pr origin/pr && echo code > code.txt && G add -A && G commit -q -m "code commit" )
( cd "$TMP/w" && G pull -q --ff-only origin pr 2>/dev/null; echo more > h && G add h && G commit -q -m "other 2" && G push -q origin pr 2>/dev/null )
S2=$(cd "$TMP/w" && G rev-parse HEAD); B0=$(cd "$TMP/qb" && G rev-parse HEAD)
out=$(SB_QA_HEAD_REMOTE="$ORIG" bash "$SYNC" --branch pr --sha "$S2" --worktree "$TMP/qb" 2>&1); rc=$?
[ "$rc" = 11 ] && printf '%s' "$out" | grep -q "ngoài docs/super-board/runs" && [ "$(cd "$TMP/qb" && G rev-parse HEAD)" = "$B0" ] && ok "14: nhánh mang code ngoài runs/ bị từ chối, giữ nguyên" || fail "14: rc=$rc out=$out"
( cd "$TMP/qb" && echo dirty > untracked.txt )
out=$(SB_QA_HEAD_REMOTE="$ORIG" bash "$SYNC" --branch pr --sha "$S2" --worktree "$TMP/qb" 2>&1); rc=$?
[ "$rc" = 11 ] && printf '%s' "$out" | grep -q "chưa commit" && ok "14: worktree bẩn bị từ chối" || fail "14: dirty rc=$rc out=$out"
out=$(bash "$SYNC" --branch pr 2>&1); rc=$?
[ "$rc" = 11 ] && ok "14: thiếu --sha exit 11" || fail "14: thiếu cờ rc=$rc"

# 15. Major 2 (review rebuild-7): bước 4c merge origin/<base> vào nhánh QA; file của main không tính là "extra".
#     Chỉ commit không-merge ngoài base mà đụng ngoài docs/super-board/runs/ mới bị từ chối.
G clone -q "$ORIG" "$TMP/qc" 2>/dev/null
( cd "$TMP/w" && G checkout -q -B main origin/main 2>/dev/null || G checkout -q -b main; echo m1 > main1 && G add main1 && G commit -q -m "main 1" && G push -q origin main 2>/dev/null )
( cd "$TMP/qc" && G checkout -q -B pr origin/pr && G fetch -q origin main && G merge -q --no-edit origin/main >/dev/null 2>&1 && mkdir -p docs/super-board/runs && echo e > docs/super-board/runs/ev3 && G add -A && G commit -q -m "qa evidence v3" )
( cd "$TMP/w" && G checkout -q pr && G pull -q --ff-only origin pr 2>/dev/null; echo o3 > o3 && G add o3 && G commit -q -m "other 3" && G push -q origin pr 2>/dev/null )
S3=$(cd "$TMP/w" && G rev-parse HEAD)
out=$(SB_QA_HEAD_REMOTE="$ORIG" bash "$SYNC" --branch pr --sha "$S3" --base main --worktree "$TMP/qc" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(cd "$TMP/qc" && G rev-parse HEAD)" = "$S3" ] && ok "15: nhánh có merge main + bằng chứng QA → synced, không Block oan" || fail "15: rc=$rc out=$out"

# 16. Major 1: git diff/log lỗi không được nuốt rồi đặt lại nhánh. Giả lỗi bằng shim git trả exit 1 cho log.
G clone -q "$ORIG" "$TMP/qd" 2>/dev/null
( cd "$TMP/qd" && G checkout -q -B pr origin/pr && mkdir -p docs/super-board/runs && echo e > docs/super-board/runs/ev4 && G add -A && G commit -q -m "qa evidence v4" )
( cd "$TMP/w" && echo o4 > o4 && G add o4 && G commit -q -m "other 4" && G push -q origin pr 2>/dev/null )
S4=$(cd "$TMP/w" && G rev-parse HEAD); D0=$(cd "$TMP/qd" && G rev-parse HEAD)
mkdir -p "$TMP/shim"; REALGIT=$(command -v git)
printf '#!/bin/sh\ncase " $* " in *" log "*|*" diff "*) echo boom >&2; exit 1;; esac\nexec %s "$@"\n' "$REALGIT" > "$TMP/shim/git"; chmod +x "$TMP/shim/git"
out=$(PATH="$TMP/shim:$PATH" SB_QA_HEAD_REMOTE="$ORIG" bash "$SYNC" --branch pr --sha "$S4" --base main --worktree "$TMP/qd" 2>&1); rc=$?
[ "$rc" = 11 ] && [ "$(cd "$TMP/qd" && G rev-parse HEAD)" = "$D0" ] && ok "16: lỗi git lúc so sánh → exit 11, không đặt lại nhánh" || fail "16: rc=$rc out=$out"

# 17. Major 3: không --worktree và chưa có nhánh cục bộ → tạo nhánh tại <sha>, in synced.
G clone -q "$ORIG" "$TMP/qe" 2>/dev/null
( cd "$TMP/qe" && G checkout -q --detach origin/pr )
out=$(cd "$TMP/qe" && SB_QA_HEAD_REMOTE="$ORIG" bash "$SYNC" --branch newbr --sha "$S4" --base main 2>&1); rc=$?
( cd "$TMP/w" && G push -q origin "$S4:refs/heads/newbr" 2>/dev/null )
out=$(cd "$TMP/qe" && SB_QA_HEAD_REMOTE="$ORIG" bash "$SYNC" --branch newbr --sha "$S4" --base main 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(cd "$TMP/qe" && G rev-parse refs/heads/newbr)" = "$S4" ] && ok "17: chưa có nhánh cục bộ → tạo tại sha, synced" || fail "17: rc=$rc out=$out"

# 18. Should fix (Historian): mọi chỗ còn viết "ls-remote ≠ sha → Block" phải nhắc 5b / qa-sync.
for f in "$ROOT/.claude/skills/super-board/references/run.md" "$ROOT/.claude/skills/super-qa/SKILL.md" "$ROOT/.claude/skills/super-qa/references/tester-verifiers-evidence.md" "$ROOT/.claude/workflows/super-board-wave.js"; do
  if grep -n 'is not <sha>, do not retry or force: Block the card' "$f" | grep -v '5b' | grep -q .; then fail "18: $f còn 'ls-remote ≠ sha → Block' không nhắc 5b"; else ok "18: $(basename "$f") không còn Block thẳng"; fi
done

echo "---"
[ "$FAILS" = 0 ] && echo "PASS" || { echo "FAIL: $FAILS"; exit 1; }
