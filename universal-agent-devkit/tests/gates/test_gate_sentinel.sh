#!/usr/bin/env bash
# Test hồi quy (P3, 20/10): sentinel + tự chữa input của cache suite theo khoá (bin/suite_cache.py, bin/post-fix-gate.py).
#   1. Lần chạy THẬT đủ suite gần nhất của repo quá DEVKIT_SENTINEL_MAX_S ⇒ lượt --full bỏ cache (suite chạy thật), rồi đóng mốc mới.
#   2. Cache nói PASS mà chạy thật FAIL lặp lại ⇒ thiếu input: file đổi từ lần PASS được học thêm vào khoá của suite (chỉ thêm, không
#      sửa ma trận) ⇒ lần sau file đó đổi là suite chạy lại, không cần sentinel.
#   3. Cache nói PASS mà chạy thật FAIL rồi PASS khi chạy lại (FLAKY) ⇒ cách ly: suite không bao giờ được dùng lại theo khoá.
#   4. stale_rerun.run_one (nightly, chạy lại STALE) ghi kết quả chạy thật vào cùng sổ khoá ⇒ gate sau đó dùng lại.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_FLAKY_QUARANTINE_S CI

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n() { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }
NEVER=999999999

R="$TMP/repo"
mkdir -p "$R/src" "$R/tests"
cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo 'a = 1' > src/a.py
echo 'good' > src/data.txt
# đọc src/data.txt qua đường dẫn dựng lúc chạy: quét tĩnh không thấy nó là input (đúng ca "watch_files viết tay thiếu")
printf 'd=src; f=da; f="${f}ta.txt"; grep -qx good "$d/$f"\n' > tests/l.sh
python3 - "$R/matrix.json" "$TMP" <<'PY'
import json, sys
path, tmp = sys.argv[1:]
c = lambda name: f"echo run >> '{tmp}/count.{name}'"
# lần chạy thứ hai (c = 1) FAIL có dấu hiệu test fail (AssertionError): gate coi là test FAIL rồi PASS khi chạy lại = FLAKY,
# không phải lỗi hạ tầng (infra_retry)
flaky = (f"c=$(cat '{tmp}/f.n' 2>/dev/null || echo 0); echo $((c+1)) > '{tmp}/f.n'; "
         f"if [ \"$c\" = 1 ] && [ -f '{tmp}/flaky.on' ]; then echo 'AssertionError: flaky'; exit 1; fi")
json.dump({"project": "t", "rules": [
    {"component": "A", "watch_files": ["src/a.py"], "mandatory_regression_tests": [
        {"id": "REG-A", "name": "a", "command": c("A")},
        {"id": "REG-L", "name": "reads data", "command": c("L") + "; bash tests/l.sh"},
        {"id": "REG-F", "name": "flaky", "command": c("F") + "; " + flaky},
        # cặp covered_by: REG-C2 không bao giờ tự chạy (REG-C1 chạy lệnh đầy đủ và PASS là phủ nó) — mốc sentinel vẫn phải được đóng
        {"id": "REG-C1", "name": "cover", "command": c("C1")},
        {"id": "REG-C2", "name": "covered", "command": c("C2") + "; true", "covered_by": "REG-C1"}]}]}, open(path, "w"))
PY
git add -A && git commit -qm init
echo 'a = 2' > src/a.py && git commit -qam change
COMMON="$(git rev-parse --path-format=absolute --git-common-dir)"
STORE="$COMMON/postfix-gate/suite_cache"

gate() { local d="$1"; shift; OUT="$( cd "$d" && CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --run-tests --full \
  --diff HEAD~1 --no-checklist "$@" 2>&1 )"; RC=$?; }
wt() { git -C "$R" worktree add -q --detach "$TMP/$1" HEAD || { echo "✖ setup: worktree $1"; exit 1; }
       mkdir -p "$TMP/$1/.claude/audit-gate" && : > "$TMP/$1/.claude/audit-gate/test_run.lock"; }
snap() { BA=$(n A); BL=$(n L); BF=$(n F); }
d() { case "$1" in A) echo $(( $(n A) - BA ));; L) echo $(( $(n L) - BL ));; F) echo $(( $(n F) - BF ));; esac; }

# 0. Cache ấm: mọi suite PASS và được ghi (sentinel tắt bằng mốc rất xa).
snap; DEVKIT_SENTINEL_MAX_S=$NEVER gate "$R"
[ "$RC" = 0 ] && [ "$(d A)$(d L)$(d F)" = "111" ] && ok "0. cache ấm: mọi suite chạy và PASS" || { fail "0. setup (exit $RC, A/L/F $(d A)$(d L)$(d F))"; printf '%s\n' "$OUT" | tail -5; }

# 1. Ca này kiểm: mốc lần chạy thật đặt về epoch 1 và DEVKIT_SENTINEL_MAX_S=1 ⇒ REG-A phải chạy thật dù khoá có PASS.
python3 -c "import json,sys; json.dump({'last_real_full_at': 1}, open(sys.argv[1], 'w'))" "$STORE/sentinel.json"
wt w1; snap; DEVKIT_SENTINEL_MAX_S=1 gate "$TMP/w1"
[ "$(d A)" = 1 ] && printf '%s\n' "$OUT" | grep -q "sentinel" && ok "1a. sentinel quá hạn: suite chạy thật dù khoá có PASS" \
  || { fail "1a. sentinel (REG-A chạy $(d A), mong 1)"; printf '%s\n' "$OUT" | grep -E "REG-|sentinel|KẾT LUẬN" | tail -5; }
wt w1b; snap; DEVKIT_SENTINEL_MAX_S=3600 gate "$TMP/w1b"
[ "$(d A)" = 0 ] && ok "1b. sau lượt sentinel: mốc mới, lượt kế dùng lại cache" || fail "1b. sau sentinel REG-A vẫn chạy $(d A) lần (mốc không được đóng)"

# 2. Thiếu input: src/data.txt (không ai khai, quét tĩnh không thấy) đổi thành 'bad' ⇒ lượt thường vẫn HIT (đúng điểm mù); lượt sentinel
#    chạy thật ⇒ FAIL lặp lại ⇒ học src/data.txt vào khoá REG-L; sau đó data.txt đổi là REG-L chạy lại không cần sentinel.
echo 'bad' > "$R/src/data.txt"; git -C "$R" commit -qam bad
wt w2; snap; DEVKIT_SENTINEL_MAX_S=$NEVER gate "$TMP/w2"
[ "$(d L)" = 0 ] && ok "2a. trước khi học: data.txt đổi mà REG-L vẫn HIT (điểm mù được tái hiện)" || fail "2a. REG-L chạy $(d L), mong 0 (tiền đề)"
python3 -c "import json,sys; json.dump({'last_real_full_at': 1}, open(sys.argv[1], 'w'))" "$STORE/sentinel.json"
wt w2b; snap; DEVKIT_SENTINEL_MAX_S=1 gate "$TMP/w2b"
grep -q '"REG-L": \[[^]]*"src/data.txt"' "$STORE/learned_inputs.json" 2>/dev/null \
  && printf '%s\n' "$OUT" | grep -q "thiếu input" && ok "2b. sentinel: REG-L FAIL trên khoá từng PASS ⇒ học src/data.txt, có báo" \
  || { fail "2b. không học được input (learned: $(cat "$STORE/learned_inputs.json" 2>/dev/null))"; printf '%s\n' "$OUT" | grep -E "REG-L|suite cache|KẾT LUẬN" | tail -5; }
echo 'good' > "$R/src/data.txt"; git -C "$R" commit -qam good
wt w2c; snap; DEVKIT_SENTINEL_MAX_S=$NEVER gate "$TMP/w2c"
wt w2d; echo 'bad' > "$TMP/w2d/src/data.txt"; snap; DEVKIT_SENTINEL_MAX_S=$NEVER gate "$TMP/w2d"
[ "$(d L)" -ge 1 ] && [ "$RC" = 1 ] && ok "2c. sau khi học: data.txt đổi ⇒ REG-L chạy lại và FAIL (không còn HIT sai)" \
  || fail "2c. REG-L chạy $(d L) lần, exit $RC (mong ≥1 lần — FAIL được chạy lại một lần —, exit 1)"

# 3. Flaky: REG-F có PASS theo khoá; lượt sentinel: lần chạy đầu FAIL, chạy lại PASS ⇒ FLAKY ⇒ cách ly ⇒ không bao giờ HIT nữa.
python3 -c "import json,sys; json.dump({'last_real_full_at': 1}, open(sys.argv[1], 'w'))" "$STORE/sentinel.json"
grep -q '"REG-F"' "$STORE/quarantine.json" 2>/dev/null && fail "3. tiền đề: REG-F đã bị cách ly trước ca 3 (ca 3a sẽ không kiểm gì)"
: > "$TMP/flaky.on"
wt w3; echo 1 > "$TMP/f.n"; snap; DEVKIT_SENTINEL_MAX_S=1 gate "$TMP/w3"
rm -f "$TMP/flaky.on"
grep -q '"REG-F"' "$STORE/quarantine.json" 2>/dev/null && ok "3a. FAIL rồi PASS trên khoá từng PASS ⇒ REG-F bị cách ly" \
  || { fail "3a. REG-F không bị cách ly (quarantine: $(cat "$STORE/quarantine.json" 2>/dev/null))"; printf '%s\n' "$OUT" | grep -E "REG-F|suite cache" | tail -4; }
echo 5 > "$TMP/f.n"
wt w3b; snap; DEVKIT_SENTINEL_MAX_S=$NEVER gate "$TMP/w3b"
[ "$(d F)" -ge 1 ] && ok "3b. suite bị cách ly luôn chạy (không HIT)" || fail "3b. REG-F bị cách ly mà vẫn HIT"

# 4. run_one (nightly / chạy lại STALE) ghi kết quả chạy thật vào sổ khoá: gate sau đó trên cùng nội dung dùng lại REG-A.
wt w4; echo 'a = 4' > "$TMP/w4/src/a.py"
( cd "$TMP/w4" && CLAUDE_PROJECT_DIR="$TMP/w4" python3 - "$DEVKIT_DIR/scripts/testing" "$TMP/w4" "$TMP/w4/matrix.json" <<'PY'
import sys
from pathlib import Path
here, proj, matrix = sys.argv[1:]
sys.path.insert(0, here)
import stale_rerun as sr
cmd = next(t["command"] for r in __import__("json").load(open(matrix))["rules"] for t in r["mandatory_regression_tests"] if t["id"] == "REG-A")
print("   ", sr.run_one(Path(proj), "REG-A", cmd, ["src/a.py"], 60, mode="nightly", matrix=matrix))
PY
) >"$TMP/out4" 2>&1
wt w4b; echo 'a = 4' > "$TMP/w4b/src/a.py"; snap; DEVKIT_SENTINEL_MAX_S=$NEVER gate "$TMP/w4b"
[ "$(d A)" = 0 ] && ok "4. run_one ghi PASS theo khoá: gate sau dùng lại REG-A" \
  || { fail "4. REG-A chạy $(d A) lần sau run_one (mong 0)"; tail -3 "$TMP/out4"; }

# 5. Merge gate / worktree finish (DEVKIT_SLOT_PRIORITY=merge) không gánh lần chạy thật hằng ngày: sentinel quá hạn vẫn dùng cache.
python3 -c "import json,sys; json.dump({'last_real_full_at': 1}, open(sys.argv[1], 'w'))" "$STORE/sentinel.json"
wt w5; snap; DEVKIT_SLOT_PRIORITY=merge DEVKIT_SENTINEL_MAX_S=1 gate "$TMP/w5"
[ "$(d A)" = 0 ] && ! printf '%s\n' "$OUT" | grep -q "sentinel:" && ok "5. ưu tiên merge: không chạy sentinel, dùng lại cache" \
  || fail "5. merge gate chạy sentinel (REG-A chạy $(d A), mong 0)"

# 6. M3 (Antigravity 20/10): lượt sentinel có suite QUÁ GIỜ (không kiểm được gì) không đóng mốc lần chạy thật: lượt sau vẫn là sentinel.
R6="$TMP/r6"; mkdir -p "$R6/src"
git -C "$R6" init -q -b main . && git -C "$R6" config user.email t@t && git -C "$R6" config user.name t
echo 'a = 1' > "$R6/src/a.py"
printf '{"project":"t","rules":[{"component":"A","watch_files":["src/a.py"],"mandatory_regression_tests":[{"id":"REG-A6","name":"a","command":"true"},{"id":"REG-T6","name":"t","command":"sleep 4"}]}]}\n' > "$R6/matrix.json"
git -C "$R6" add -A && git -C "$R6" commit -qm init; echo 'a = 2' > "$R6/src/a.py"
ST6="$(git -C "$R6" rev-parse --path-format=absolute --git-common-dir)/postfix-gate/suite_cache"
mkdir -p "$ST6"; python3 -c "import json,sys; json.dump({'last_real_full_at': 1}, open(sys.argv[1], 'w'))" "$ST6/sentinel.json"
( cd "$R6" && FLAKY_RETRY=0 VACUITY_REVERT=0 DEVKIT_SENTINEL_MAX_S=1 CLAUDE_PROJECT_DIR="$R6" python3 "$GATE" --matrix "$R6/matrix.json" \
  --run-tests --full --no-checklist --timeout 2 >"$TMP/out6" 2>&1 )
rc6=$?
at6=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('last_real_full_at'))" "$ST6/sentinel.json" 2>/dev/null)
[ "$at6" = 1 ] && [ "$rc6" = 1 ] && grep -q "REG-T6" "$TMP/out6" && ! grep -q Traceback "$TMP/out6" \
  && ok "6. lượt sentinel có suite quá giờ (exit 1): không đóng mốc lần chạy thật" \
  || fail "6. mốc $at6 (mong 1), exit $rc6 (mong 1), REG-T6 trong output: $(grep -c REG-T6 "$TMP/out6"), traceback: $(grep -c Traceback "$TMP/out6")"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_sentinel: all passed" || { echo "❌ test_gate_sentinel: $FAILS failed"; exit 1; }
