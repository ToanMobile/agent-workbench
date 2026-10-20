#!/usr/bin/env bash
# Test hồi quy (P2, 20/10): cache PASS theo KHOÁ NỘI DUNG của từng suite (bin/suite_cache.py), dùng chung mọi worktree của repo.
# Khoá = id + lệnh + nội dung mọi input của suite (watch_files, script lệnh chạy và những gì script source/nhắc tên, đích symlink
# ra ngoài cây, danger list) + trạng thái cục bộ + môi trường. Một suite có PASS cho đúng khoá của nó thì không chạy lại; khoá đổi
# (input đổi) thì chạy. FAIL trên một khoá là vĩnh viễn: khoá đó không bao giờ HIT nữa. Chất lượng không thấp hơn --full cũ:
# không chắc thì chạy.
# Mỗi ca chạy trong một worktree riêng ĐÃ từng chạy gate (biên nhận anh em không cho mượn: _ever_gated) — chỉ cache theo khoá mới
# giải thích được một suite không chạy. Số lần chạy đo bằng file đếm của từng suite.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SENTINEL_MAX_S CI

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"
mkdir -p "$SB_HEAVY_SLOT_DIR"
# sentinel P3: mọi ca ở đây coi lần chạy thật gần nhất là vừa xong (ca sentinel nằm ở test_gate_sentinel.sh)
export DEVKIT_SENTINEL_MAX_S=999999999
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n() { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }

R="$TMP/repo"
mkdir -p "$R/src" "$R/tests/lib" "$R/ext-in"
mkdir -p "$TMP/extdir"
cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo 'a = 1' > src/a.py
echo 'b = 1' > src/b.py
echo 'c = 1' > src/c.py
echo 'echo helper' > tests/helper1.sh
printf '. "$(dirname "$0")/helper1.sh" >/dev/null\n. ext/conf.sh\n' > tests/t1.sh
echo '# lib dùng chung' > tests/lib/common.sh
echo 'X=1' > "$TMP/extdir/conf.sh"
ln -s "$TMP/extdir" ext   # symlink trong cây trỏ ra ngoài: nội dung đích là input của REG-1
python3 - "$R/matrix.json" "$TMP" <<'PY'
import json, sys
path, tmp = sys.argv[1:]
c = lambda name: f"echo run >> '{tmp}/count.{name}'"
json.dump({"project": "t", "rules": [
    {"component": "A", "watch_files": ["src/a.py"],
     "mandatory_regression_tests": [{"id": "REG-1", "name": "a", "command": c("1") + "; bash tests/t1.sh"}]},
    {"component": "B", "watch_files": ["src/b.py"],
     "mandatory_regression_tests": [{"id": "REG-2", "name": "b", "command": c("2")}]},
    {"component": "C", "watch_files": ["src/c.py"],
     "mandatory_regression_tests": [{"id": "REG-3", "name": "c", "command": c("3") + f"; test ! -f '{tmp}/flag3'"},
                                    {"id": "REG-N", "name": "no cache", "command": c("N"), "cache": False}]},
]}, open(path, "w"))
PY
git add -A && git commit -qm init
echo 'a = 2' > src/a.py && echo 'b = 2' > src/b.py && echo 'c = 2' > src/c.py
git commit -qam change
COMMON="$(git rev-parse --path-format=absolute --git-common-dir)"

# gate --full ở thư mục $1 trên HEAD~1..cây (như merge gate: --diff tường minh); output vào $OUT, exit vào $RC
gate() { local d="$1"; shift; OUT="$( cd "$d" && CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --run-tests --full \
  --diff HEAD~1 --no-checklist "$@" 2>&1 )"; RC=$?; }
# gate --full không --diff: chỉ file đang đổi so với HEAD được tính là thay đổi (luật chọn cũ hẹp hơn)
gate_nodiff() { local d="$1"; shift; OUT="$( cd "$d" && CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --run-tests \
  --full --no-checklist "$@" 2>&1 )"; RC=$?; }
# worktree mới đã "từng chạy gate" (có test_run.lock của gate): biên nhận anh em không được mượn
wt() { git -C "$R" worktree add -q --detach "$TMP/$1" HEAD || { echo "✖ setup: worktree $1"; exit 1; }
       [ -L "$TMP/$1/ext" ] || ln -s "$TMP/extdir" "$TMP/$1/ext"   # link đã commit thì worktree có sẵn (ln vào link thư mục tạo extdir/extdir)
       mkdir -p "$TMP/$1/.claude/audit-gate" && : > "$TMP/$1/.claude/audit-gate/test_run.lock"; }
# expect <tên> <suite: số lần chạy THÊM mong đợi>... dùng mảng trước/sau
snap() { B1=$(n 1); B2=$(n 2); B3=$(n 3); BN=$(n N); }
expect() {   # expect <tên> <thêm REG-1> <thêm REG-2> <thêm REG-3> <thêm REG-N> <exit mong đợi>
  local d1=$(( $(n 1) - B1 )) d2=$(( $(n 2) - B2 )) d3=$(( $(n 3) - B3 )) dn=$(( $(n N) - BN ))
  if [ "$d1 $d2 $d3 $dn" = "$2 $3 $4 $5" ] && [ "$RC" = "$6" ]; then ok "$1"
  else fail "$1 (chạy thêm REG-1/2/3/N = $d1 $d2 $d3 $dn, mong $2 $3 $4 $5; exit $RC, mong $6)"; printf '%s\n' "$OUT" | grep -E "REG-|KẾT LUẬN" | tail -8; fi
}

# 0. Main checkout: mọi suite chạy thật một lần (cache lạnh) và ghi PASS theo khoá.
snap; gate "$R"; expect "0. cache lạnh: mọi suite chạy" 1 1 1 1 0

# 1a. Suite mà luật chọn cũ vẫn chạy (file đổi khớp watch) chỉ được dùng lại khi CẢ CÂY trùng: cây khác ở src/b.py ⇒ REG-1, REG-3
#     vẫn chạy dù input riêng của chúng không đổi — build ngầm (Gradle includeBuild…) có thể đọc file ngoài khoá chính xác (review
#     20/10, P0-2). REG-N ("cache": false) luôn chạy.
wt w1; echo 'b = 3' > "$TMP/w1/src/b.py"
snap; gate "$TMP/w1"; expect "1a. cây khác: suite được chọn vẫn chạy hết (không dùng khoá chính xác cho suite được chọn)" 1 1 1 1 0

# 1b. Worktree khác, ĐÃ từng chạy gate (biên nhận anh em không cho mượn), cây TRÙNG cây của lượt 0: mọi suite được chọn dùng lại
#     theo khoá cả cây; REG-N vẫn chạy. Trước P2: biên nhận chỉ của git dir mình ⇒ chạy lại hết.
wt w1b
snap; gate "$TMP/w1b"; expect "1b. cây trùng ở worktree khác: dùng lại theo khoá cả cây" 0 0 0 1 0

# 1c. Không --diff, chỉ src/b.py đổi: REG-2 được chọn và chạy; REG-1, REG-3 là phần cached-full thêm vào (luật cũ không chạy chúng):
#     khoá chính xác của chúng có PASS ⇒ không chạy; REG-N không được chọn, không cache được ⇒ không chạy.
wt w1c; echo 'b = 4' > "$TMP/w1c/src/b.py"
snap; gate_nodiff "$TMP/w1c"; expect "1c. phần cached-full thêm vào dùng lại theo khoá chính xác" 0 1 0 0 0

# 2. File mà script của REG-1 source nhưng watch_files không nêu (tests/helper1.sh) đổi: luật cũ không chọn suite nào; cached-full
#    thêm REG-1 (khoá chính xác của nó có helper qua bao đóng tĩnh) ⇒ REG-1 chạy (điểm mù watch_files); REG-2, REG-3 dùng lại.
wt w2; echo 'echo helper v2' > "$TMP/w2/tests/helper1.sh"
snap; gate_nodiff "$TMP/w2" --auto-approve-tests --allow-no-tests; expect "2. file được source (ngoài watch_files) đổi ⇒ suite đó chạy" 1 0 0 0 0

# 3. Đích symlink ngoài cây đổi ⇒ khoá REG-1 đổi ⇒ chạy lại.
wt w3; echo 'X=2' > "$TMP/extdir/conf.sh"
snap; gate "$TMP/w3"; expect "3. nội dung đích symlink ngoài cây đổi ⇒ suite đọc nó chạy lại" 1 0 0 1 0

# 4. File danger list (tests/lib/**) đổi ⇒ mọi khoá đổi ⇒ mọi suite chạy lại.
wt w4; echo '# đổi' >> "$TMP/w4/tests/lib/common.sh"
snap; gate "$TMP/w4"; expect "4. file danger đổi ⇒ mọi suite chạy lại" 1 1 1 1 0

# 5. FAIL dính khoá: REG-3 FAIL trên một khoá (cờ ngoài cây), sau đó PASS trên CÙNG khoá ⇒ khoá đó không bao giờ HIT nữa.
wt w5; echo 'c = 5' > "$TMP/w5/src/c.py"; : > "$TMP/flag3"
snap; gate "$TMP/w5"; d=$(( $(n 3) - B3 ))
[ "$RC" = 1 ] && [ "$d" -ge 1 ] && ok "5a. REG-3 FAIL trên khoá mới" || fail "5a. REG-3 phải FAIL (exit $RC, chạy $d)"
rm -f "$TMP/flag3"
wt w5b; echo 'c = 5' > "$TMP/w5b/src/c.py"
snap; gate "$TMP/w5b"; expect "5b. cùng khoá từng FAIL: chạy lại (không HIT)" 0 0 1 1 0
wt w5c; echo 'c = 5' > "$TMP/w5c/src/c.py"
snap; gate "$TMP/w5c"; expect "5c. khoá từng FAIL rồi PASS vẫn không bao giờ HIT" 0 0 1 1 0

# 6. --no-cache (lần chạy thật): mọi suite chạy dù khoá có PASS.
wt w6
snap; gate "$TMP/w6" --no-cache; expect "6. --no-cache: mọi suite chạy" 1 1 1 1 0

# 7. Cached-full: thay đổi chỉ chạm watch của REG-1 (diff HEAD), suite KHÔNG bị chọn mà chưa có PASS cho khoá hiện tại vẫn chạy;
#    worktree sau cùng nội dung: 0 suite cacheable chạy.
wt w7; echo 'b = 7' > "$TMP/w7/src/b.py"; git -C "$TMP/w7" commit -qam b7
echo 'a = 7' > "$TMP/w7/src/a.py"
snap; ( cd "$TMP/w7" && CLAUDE_PROJECT_DIR="$TMP/w7" python3 "$GATE" --matrix "$TMP/w7/matrix.json" --run-tests --full --no-checklist >"$TMP/out7" 2>&1 ); RC=$?
d1=$(( $(n 1) - B1 )); d2=$(( $(n 2) - B2 ))
[ "$d1" = 1 ] && [ "$d2" = 1 ] && [ "$RC" = 0 ] && ok "7a. --full: REG-2 (không bị chọn, chưa có PASS cho b = 7) cũng chạy, exit 0" \
  || { fail "7a. cached-full (REG-1 chạy $d1, REG-2 chạy $d2, mong 1 1; exit $RC, mong 0)"; grep -E "REG-|KẾT LUẬN" "$TMP/out7" | tail -6; }
wt w7b; echo 'b = 7' > "$TMP/w7b/src/b.py"; git -C "$TMP/w7b" commit -qam b7; echo 'a = 7' > "$TMP/w7b/src/a.py"
snap; ( cd "$TMP/w7b" && CLAUDE_PROJECT_DIR="$TMP/w7b" python3 "$GATE" --matrix "$TMP/w7b/matrix.json" --run-tests --full --no-checklist >"$TMP/out7b" 2>&1 )
d1=$(( $(n 1) - B1 )); d2=$(( $(n 2) - B2 )); d3=$(( $(n 3) - B3 ))
[ "$d1 $d2 $d3" = "0 0 0" ] && ok "7b. worktree cùng nội dung: 0 suite cacheable chạy" \
  || { fail "7b. (REG-1/2/3 chạy $d1 $d2 $d3, mong 0 0 0)"; grep -E "REG-|KẾT LUẬN" "$TMP/out7b" | tail -6; }

# 8. Hai gate cùng lúc trên cùng khoá: suite chạy MỘT lần, lượt kia chờ rồi dùng lại (coalescing).
python3 - "$R/matrix.json" "$TMP" <<'PY'
import json, sys
path, tmp = sys.argv[1:]
m = json.load(open(path))
m["rules"].append({"component": "S", "watch_files": ["src/s.py"], "mandatory_regression_tests": [
    {"id": "REG-S", "name": "slow", "command": f"echo run >> '{tmp}/count.S'; sleep 3"}]})
json.dump(m, open(path, "w"))
PY
echo 's = 1' > src/s.py && git add -A && git commit -qm slow
wt w8a; wt w8b
echo 's = 8' > "$TMP/w8a/src/s.py"; echo 's = 8' > "$TMP/w8b/src/s.py"
BS=$(n S)
( cd "$TMP/w8a" && CLAUDE_PROJECT_DIR="$TMP/w8a" python3 "$GATE" --matrix "$TMP/w8a/matrix.json" --run-tests --full --no-checklist >"$TMP/out8a" 2>&1 ) &
P8=$!
( cd "$TMP/w8b" && CLAUDE_PROJECT_DIR="$TMP/w8b" python3 "$GATE" --matrix "$TMP/w8b/matrix.json" --run-tests --full --no-checklist >"$TMP/out8b" 2>&1 )
wait "$P8"
[ $(( $(n S) - BS )) = 1 ] && ok "8. hai gate cùng khoá cùng lúc: suite chạy đúng 1 lần" \
  || fail "8. coalescing: REG-S chạy $(( $(n S) - BS )) lần, mong 1"

# 9. Suite tự sửa input của nó trong lúc chạy ⇒ khoá sau khi chạy khác khoá trước ⇒ KHÔNG ghi PASS (worktree sau cùng nội dung ban
#    đầu vẫn phải chạy nó).
python3 - "$R/matrix.json" "$TMP" <<'PY'
import json, sys
path, tmp = sys.argv[1:]
m = json.load(open(path))
m["rules"].append({"component": "M", "watch_files": ["src/m.py"], "mandatory_regression_tests": [
    {"id": "REG-M", "name": "mutates", "command": f"echo run >> '{tmp}/count.M'; echo '# t' >> src/m.py"}]})
json.dump(m, open(path, "w"))
PY
echo 'm = 1' > src/m.py && git add -A && git commit -qm mut
wt w9a; echo 'm = 9' > "$TMP/w9a/src/m.py"
( cd "$TMP/w9a" && CLAUDE_PROJECT_DIR="$TMP/w9a" python3 "$GATE" --matrix "$TMP/w9a/matrix.json" --run-tests --full --no-checklist >"$TMP/out9a" 2>&1 )
wt w9b; echo 'm = 9' > "$TMP/w9b/src/m.py"
BM=$(n M)
( cd "$TMP/w9b" && CLAUDE_PROJECT_DIR="$TMP/w9b" python3 "$GATE" --matrix "$TMP/w9b/matrix.json" --run-tests --full --no-checklist >"$TMP/out9b" 2>&1 )
[ $(( $(n M) - BM )) = 1 ] && ok "9. suite sửa input của nó trong lúc chạy: không ghi PASS, lượt sau cùng nội dung chạy lại" \
  || fail "9. REG-M chạy $(( $(n M) - BM )) lần ở lượt sau, mong 1 (PASS bị ghi dưới khoá cũ)"

# 10. Tắt cache (DEVKIT_SUITE_CACHE=0): --full về đúng luật chọn cũ — không mở rộng cached-full (REG-2 không bị chọn thì không chạy).
wt w10; echo 'a = 10' > "$TMP/w10/src/a.py"; B2=$(n 2)
( cd "$TMP/w10" && DEVKIT_SUITE_CACHE=0 CLAUDE_PROJECT_DIR="$TMP/w10" python3 "$GATE" --matrix "$TMP/w10/matrix.json" --run-tests --full --no-checklist >"$TMP/out10" 2>&1 )
[ $(( $(n 2) - B2 )) = 0 ] && ok "10. DEVKIT_SUITE_CACHE=0: không mở rộng cached-full (luật chọn cũ)" \
  || fail "10. DEVKIT_SUITE_CACHE=0 mà REG-2 (không bị chọn) vẫn chạy $(( $(n 2) - B2 )) lần"

# 11. Dọn kho: bản ghi có FAIL không bị dọn theo số lượng (FAIL là vĩnh viễn với khoá đó); bản ghi PASS cũ thì bị dọn.
python3 - "$DEVKIT_DIR/bin" "$TMP/w10" <<'PY' || FAILS=$((FAILS + 1))
import json, os, sys, time
sys.path.insert(0, sys.argv[1])
import suite_cache as sc
c = sc.SuiteCache.__new__(sc.SuiteCache)
c.store = os.path.join(sys.argv[2], ".sc-prune-test")
os.makedirs(c.store, exist_ok=True)
old = time.time() - 3600
for i, fail in enumerate((1, 0, 0)):
    key = f"{i:064x}"
    p = os.path.join(c.store, key + ".json")
    json.dump({"id": "R", "command": "x", "pass_n": 1, "fail_n": fail}, open(p, "w"))
    os.utime(p, (old - i, old - i))
sc.STORE_MAX = 1
c.prune()
left = sorted(n for n in os.listdir(c.store) if n.endswith(".json"))
ok = f"{0:064x}.json" in left and len(left) == 2
print(("✔" if ok else "✖") + f" 11. prune giữ bản ghi FAIL, bỏ PASS thừa (còn {len(left)} bản ghi)")
sys.exit(0 if ok else 1)
PY

# 12. covered_by: suite được phủ chỉ COVERED khi cover chạy lệnh đầy đủ trên đúng nội dung này (chạy thật hoặc dùng lại theo khoá CẢ
#     CÂY); cover dùng lại theo khoá CHÍNH XÁC (phần cached-full thêm) không phủ được — khoá đó không thấy input của suite được phủ
#     (review 20/10, P0-1: GeelyEx2 REG-SHARED-01 covered_by REG-CAR-01). Bỏ rule REG-M của ca 9 (suite sửa cây trong lúc chạy làm
#     PASS cả cây của lượt bị đánh FAIL — đúng, nhưng không phải điều ca này kiểm).
python3 - "$R/matrix.json" "$TMP" <<'PY'
import json, sys
path, tmp = sys.argv[1:]
m = json.load(open(path))
m["rules"] = [r for r in m["rules"] if r.get("component") != "M"]
m["rules"].append({"component": "X", "watch_files": ["src/x.py"], "mandatory_regression_tests": [
    {"id": "REG-CV", "name": "cover", "command": f"echo run >> '{tmp}/count.CV'"}]})
m["rules"].append({"component": "Y", "watch_files": ["src/y.py"], "mandatory_regression_tests": [
    {"id": "REG-CD", "name": "covered", "command": f"echo run >> '{tmp}/count.CD'", "covered_by": "REG-CV"}]})
json.dump(m, open(path, "w"))
PY
echo 'x = 1' > src/x.py && echo 'y = 1' > src/y.py && git add -A && git commit -qm cover
run12() { ( cd "$TMP/$1" && CLAUDE_PROJECT_DIR="$TMP/$1" python3 "$GATE" --matrix "$TMP/$1/matrix.json" --run-tests --full --no-checklist >"$TMP/out$1" 2>&1 ); }
d12() { echo "$(( $(n CV) - BCV )) $(( $(n CD) - BCD ))"; }
wt w12a; echo 'x = 2' > "$TMP/w12a/src/x.py"; echo 'y = 2' > "$TMP/w12a/src/y.py"
BCV=$(n CV); BCD=$(n CD); run12 w12a
[ "$(d12)" = "1 0" ] && ok "12a. cover chạy thật: suite được phủ COVERED" || fail "12a. (CV/CD chạy $(d12), mong 1 0)"
wt w12b; echo 'x = 2' > "$TMP/w12b/src/x.py"; echo 'y = 2' > "$TMP/w12b/src/y.py"
BCV=$(n CV); BCD=$(n CD); run12 w12b
[ "$(d12)" = "0 0" ] && ok "12b. cây trùng: cover dùng lại theo khoá cả cây vẫn phủ được" || fail "12b. (CV/CD chạy $(d12), mong 0 0)"
# cover có PASS theo khoá CHÍNH XÁC cho x = 1 (một lượt mà nó là phần cached-full thêm vào)
wt w12p; echo 'b = 12' > "$TMP/w12p/src/b.py"; run12 w12p
wt w12c; echo 'y = 3' > "$TMP/w12c/src/y.py"
BCV=$(n CV); BCD=$(n CD); run12 w12c
[ "$(( $(n CD) - BCD ))" = 1 ] && ok "12c. cover chỉ dùng lại theo khoá chính xác: suite được phủ tự chạy" \
  || { fail "12c. REG-CD chạy $(( $(n CD) - BCD )) lần, mong 1 (cover theo khoá chính xác đã phủ nó)"; grep -E "REG-C" "$TMP/outw12c" | tail -4; }

# 13. F1 của khoá: lượt A dùng lại REG-CV theo khoá; một lượt khác ghi FAIL lên đúng khoá đó SAU lần tra của A, trước kết luận của A
#     (launcher: lần hit() đầu tiên trả PASS rồi ghi FAIL lên khoá, như một B chạy thật vừa FAIL). PASS của A không còn đứng vững:
#     UNTESTED, exit 4 — không bao giờ exit 0 (recheck_keyed). Lượt --full sau đó chạy thật REG-CV (khoá đã FAIL không HIT nữa).
cat > "$TMP/l13.py" <<'PY'
import importlib.util, os, sys
gate = sys.argv[1]
sys.path.insert(0, os.path.dirname(gate))
import suite_cache
real_hit, fired = suite_cache.SuiteCache.hit, []
def hit(self, key, test, now=None):
    rec = real_hit(self, key, test, now)
    if rec and test.get("id") == "REG-CV" and not fired:
        fired.append(1)
        self.record(key, test, "FAIL", {"why": "test 13: B FAILED this key"})
    return rec
suite_cache.SuiteCache.hit = hit
sys.argv = [gate] + sys.argv[2:]
spec = importlib.util.spec_from_file_location("pfg13", gate)
m = importlib.util.module_from_spec(spec)
sys.modules["pfg13"] = m
spec.loader.exec_module(m)
sys.exit(m.main())
PY
wt w13; echo 'x = 13' > "$TMP/w13/src/x.py"; run12 w13
wt w13b; echo 'x = 13' > "$TMP/w13b/src/x.py"
BCV=$(n CV)
( cd "$TMP/w13b" && CLAUDE_PROJECT_DIR="$TMP/w13b" python3 "$TMP/l13.py" "$GATE" --matrix "$TMP/w13b/matrix.json" --run-tests --full \
  --no-checklist >"$TMP/out13" 2>&1 ); RC=$?
if [ "$RC" = 4 ] && [ "$(( $(n CV) - BCV ))" = 0 ] && grep -q "REG-CV" "$TMP/out13"; then
  ok "13. FAIL ghi lên khoá sau lần tra: PASS theo khoá thành UNTESTED (exit 4)"
else fail "13. exit $RC (mong 4), REG-CV chạy $(( $(n CV) - BCV )) lần (mong 0)"; grep -E "REG-CV|VERDICT|KẾT LUẬN" "$TMP/out13" | tail -4; fi
BCV=$(n CV); run12 w13b
[ "$(( $(n CV) - BCV ))" = 1 ] && ok "13. lượt sau: khoá đã FAIL không HIT, REG-CV chạy thật" \
  || fail "13. lượt sau: REG-CV chạy $(( $(n CV) - BCV )) lần, mong 1"

# 14. FAIL của lượt KHÔNG cưỡng bức (Stop hook) cũng vào sổ khoá: (1) --full, REG-E PASS (khoá được ghi); (2) lượt kiểu Stop, biên nhận
#     quá tuổi (DEVKIT_GATE_CACHE_MAX_S=0, như Stop sau 6 h), FAILE=1: REG-E chạy và FAIL; (3) --full, FAILE=1 vẫn đặt: REG-E phải chạy
#     lại và FAIL (exit 1) như --full trước P2 — dùng lại PASS cũ theo khoá thì exit 0 (review 20/10). Repo riêng, một suite.
R14="$TMP/r14"; mkdir -p "$R14/src"
git -C "$R14" init -q -b main . && git -C "$R14" config user.email t@t && git -C "$R14" config user.name t || fail "14. setup"
echo 'e = 1' > "$R14/src/e.py"
printf '{"project":"t","rules":[{"component":"E","watch_files":["src/e.py"],"mandatory_regression_tests":[{"id":"REG-E","name":"e","command":"echo run >> %s/count.E; test -z \\"${FAILE:-}\\""}]}]}\n' "$TMP" > "$R14/matrix.json"
git -C "$R14" add -A && git -C "$R14" commit -qm init || fail "14. setup commit"
echo 'e = 2' > "$R14/src/e.py"
g14() { ( cd "$R14" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R14" python3 "$GATE" --matrix "$R14/matrix.json" --run-tests --no-checklist "$@" >"$TMP/out14" 2>&1 ); }
g14 --full; r1=$?; c1=$(n E)
FAILE=1 DEVKIT_GATE_CACHE_MAX_S=0 g14; r2=$?; c2=$(n E)
FAILE=1 g14 --full; r3=$?; c3=$(n E)
if [ "$r1 $c1 $r2 $c2 $r3 $c3" = "0 1 1 2 1 3" ]; then ok "14. FAIL của lượt kiểu Stop chặn PASS cũ theo khoá: --full sau đó chạy REG-E và FAIL"
else fail "14. (exit/lần chạy: $r1/$c1 $r2/$c2 $r3/$c3, mong 0/1 1/2 1/3)"; grep -E "REG-E|KẾT LUẬN|VERDICT" "$TMP/out14" | tail -3; fi

# 15. Suite cached-full thêm vào (keyed_full) mà QUÁ GIỜ: --full trước P2 không chạy nó, quá giờ dưới tải không chứng minh lỗi của thay
#     đổi (REG-DK-ALL-01 quá 900 s ở merge gate dưới tải, 19/10) ⇒ UNTESTED ngoài kết luận, được nêu tên, exit 0. Đối chứng: cùng suite
#     được CHỌN (file nó theo dõi đổi) mà quá giờ ⇒ exit 1 như trước. Repo riêng: REG-S nhanh (src/s.py), REG-T ngủ 6 s (src/t.py), --timeout 2.
R15="$TMP/r15"; mkdir -p "$R15/src"
git -C "$R15" init -q -b main . && git -C "$R15" config user.email t@t && git -C "$R15" config user.name t || fail "15. setup"
echo 's = 1' > "$R15/src/s.py"; echo 't = 1' > "$R15/src/t.py"
printf '{"project":"t","rules":[{"component":"S","watch_files":["src/s.py"],"mandatory_regression_tests":[{"id":"REG-S","name":"s","command":"true"}]},{"component":"T","watch_files":["src/t.py"],"mandatory_regression_tests":[{"id":"REG-T","name":"t","command":"sleep 6"}]}]}\n' > "$R15/matrix.json"
git -C "$R15" add -A && git -C "$R15" commit -qm init || fail "15. setup commit"
g15() { ( cd "$R15" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R15" python3 "$GATE" --matrix "$R15/matrix.json" --run-tests --full \
  --no-checklist --timeout 2 "$@" >"$TMP/out15" 2>&1 ); }
echo 's = 2' > "$R15/src/s.py"; g15; r=$?
if [ "$r" = 0 ] && grep -q "REG-T" "$TMP/out15"; then ok "15. suite cached-full quá giờ: ngoài kết luận, được nêu tên (exit 0)"
else fail "15. suite cached-full quá giờ: exit $r (mong 0)"; grep -E "REG-T|KẾT LUẬN|VERDICT" "$TMP/out15" | tail -3; fi
echo 't = 2' > "$R15/src/t.py"; g15; r=$?
[ "$r" = 1 ] && ok "15. đối chứng: suite được chọn mà quá giờ vẫn exit 1" \
  || { fail "15. đối chứng: suite được chọn quá giờ, exit $r (mong 1)"; grep -E "REG-T|KẾT LUẬN|VERDICT" "$TMP/out15" | tail -3; }

# ── Ca 16–19: review principal 20/10. Mỗi ca một repo riêng; input ngầm (đường dẫn ghép lúc chạy) mà quét tĩnh không thấy.
newrepo() { # <thư mục>: repo có src/x.py, src/y.py, src/hidden.txt=good, tests/x.sh đọc hidden.txt qua đường dẫn ghép
  local r="$1"; mkdir -p "$r/src" "$r/tests"
  git -C "$r" init -q -b main . && git -C "$r" config user.email t@t && git -C "$r" config user.name t
  echo 'x = 1' > "$r/src/x.py"; echo 'y = 1' > "$r/src/y.py"; echo good > "$r/src/hidden.txt"
  printf 'd=src; f=hid; f="${f}den.txt"; grep -qx good "$d/$f"\n' > "$r/tests/x.sh"
}
gq() { local d="$1"; shift; ( cd "$d" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" \
  --run-tests --full --no-checklist "$@" >"$TMP/outq" 2>&1 ); }
wtq() { git -C "$1" worktree add -q --detach "$2" HEAD || fail "setup: worktree $2"; mkdir -p "$2/.claude/audit-gate"; : > "$2/.claude/audit-gate/test_run.lock"; }

# 16. P0-A: PASS theo khoá CHÍNH XÁC (REG-X cached-full, input ngầm hidden.txt đã đổi) không vào biên nhận như PASS thật. Lượt sau trên
#     cùng cây CHỌN REG-X (--diff HEAD~1) phải chạy nó và FAIL (exit 1) — như --full trước P2 (biên nhận không có REG-X).
R16="$TMP/r16"; newrepo "$R16"
printf '{"project":"t","rules":[{"component":"X","watch_files":["src/x.py"],"mandatory_regression_tests":[{"id":"REG-X","name":"x","command":"echo run >> %s/count.16; bash tests/x.sh"}]},{"component":"Y","watch_files":["src/y.py"],"mandatory_regression_tests":[{"id":"REG-Y","name":"y","command":"true"}]}]}\n' "$TMP" > "$R16/matrix.json"
git -C "$R16" add -A && git -C "$R16" commit -qm init
wtq "$R16" "$TMP/w16a"; echo 'x = 2' > "$TMP/w16a/src/x.py"; gq "$TMP/w16a"
wtq "$R16" "$TMP/w16b"; echo 'x = 2' > "$TMP/w16b/src/x.py"; git -C "$TMP/w16b" commit -qam x2
echo bad > "$TMP/w16b/src/hidden.txt"; echo 'y = 2' > "$TMP/w16b/src/y.py"
gq "$TMP/w16b"   # REG-X không được chọn (cached-full, khoá chính xác trúng)
B=$(n 16); gq "$TMP/w16b" --diff HEAD~1; rc=$?
if [ "$rc" = 1 ] && [ "$(( $(n 16) - B ))" -ge 1 ]; then ok "16. PASS theo khoá chính xác không vào biên nhận như PASS thật: lượt chọn REG-X chạy nó và FAIL"
else fail "16. lượt chọn REG-X: exit $rc (mong 1), REG-X chạy $(( $(n 16) - B )) lần (mong ≥1) — biên nhận mang PASS theo khoá chính xác"; fi

# 17. P0-B: PASS theo khoá chính xác không vào DEVKIT_GATE_DONE: suite run_impacted.sh được chọn vẫn chạy tests/x.sh (FAIL, exit 1).
R17="$TMP/r17"; newrepo "$R17"
cat > "$R17/tests/run_impacted.sh" <<'SH'
for t in tests/x.sh; do
  printf '%s\n' "${DEVKIT_GATE_DONE:-}" | grep -qxF "$(pwd -P)/$t" && { echo "skip $t (gate done)"; continue; }
  bash "$t" || { echo "FAIL $t"; exit 1; }
done
SH
printf '{"project":"t","rules":[{"component":"X","watch_files":["src/x.py"],"mandatory_regression_tests":[{"id":"REG-X","name":"x","command":"bash tests/x.sh"}]},{"component":"Y","watch_files":["src/y.py"],"mandatory_regression_tests":[{"id":"REG-IMP","name":"pool","command":"bash tests/run_impacted.sh"}]}]}\n' > "$R17/matrix.json"
git -C "$R17" add -A && git -C "$R17" commit -qm init
wtq "$R17" "$TMP/w17a"; echo 'x = 2' > "$TMP/w17a/src/x.py"; gq "$TMP/w17a"
wtq "$R17" "$TMP/w17b"; echo 'x = 2' > "$TMP/w17b/src/x.py"; git -C "$TMP/w17b" commit -qam x2
echo bad > "$TMP/w17b/src/hidden.txt"; echo 'y = 2' > "$TMP/w17b/src/y.py"
gq "$TMP/w17b"; rc=$?
if [ "$rc" = 1 ] && ! grep -q "skip tests/x.sh" "$TMP/outq"; then ok "17. PASS theo khoá chính xác không vào DEVKIT_GATE_DONE: run_impacted.sh chạy tests/x.sh"
else fail "17. exit $rc (mong 1), run_impacted.sh bỏ tests/x.sh: $(grep -c 'skip tests/x.sh' "$TMP/outq")"; fi

# 18. Không-PASS của lần chạy thật (TIMEOUT) vô hiệu PASS cũ theo khoá: (1) --full PASS; (2) cùng cây, suite treo, --no-cache: TIMEOUT;
#     (3) --full, cùng cây, suite vẫn treo: phải CHẠY và TIMEOUT (exit 1), không dùng lại PASS của (1) theo khoá cả cây.
R18="$TMP/r18"; mkdir -p "$R18/src"
git -C "$R18" init -q -b main . && git -C "$R18" config user.email t@t && git -C "$R18" config user.name t
echo 'x = 1' > "$R18/src/x.py"
printf '{"project":"t","rules":[{"component":"X","watch_files":["src/x.py"],"mandatory_regression_tests":[{"id":"REG-X","name":"x","command":"echo run >> %s/count.18; if [ -f %s/hang18 ]; then sleep 4; fi"}]}]}\n' "$TMP" "$TMP" > "$R18/matrix.json"
git -C "$R18" add -A && git -C "$R18" commit -qm init; echo 'x = 2' > "$R18/src/x.py"
gq "$R18" --timeout 2; r1=$?
: > "$TMP/hang18"; gq "$R18" --timeout 2 --no-cache; r2=$?
B=$(n 18); gq "$R18" --timeout 2; r3=$?
if [ "$r1 $r2 $r3" = "0 1 1" ] && [ "$(( $(n 18) - B ))" = 1 ]; then ok "18. TIMEOUT của lần chạy thật vô hiệu PASS cũ theo khoá: lượt sau chạy lại (exit 1)"
else fail "18. (exit $r1 $r2 $r3, mong 0 1 1; lượt 3 chạy $(( $(n 18) - B )) lần, mong 1)"; grep -E "REG-X|Traceback" "$TMP/outq" | head -3; fi

# 19. Suite cached-full tự sửa input CHÍNH XÁC của nó trong lúc chạy ⇒ không ghi PASS theo khoá chính xác: worktree khác cùng nội dung
#     ban đầu vẫn chạy nó (bắt mutant inputs_unchanged → True mà ca 9 — suite được chọn — không bắt).
R19="$TMP/r19"; mkdir -p "$R19/src"
git -C "$R19" init -q -b main . && git -C "$R19" config user.email t@t && git -C "$R19" config user.name t
echo 'a = 1' > "$R19/src/a.py"; echo 'm = 1' > "$R19/src/m.py"
printf '{"project":"t","rules":[{"component":"A","watch_files":["src/a.py"],"mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"true"}]},{"component":"M","watch_files":["src/m.py"],"mandatory_regression_tests":[{"id":"REG-M","name":"m","command":"echo run >> %s/count.19; echo t >> src/m.py"}]}]}\n' "$TMP" > "$R19/matrix.json"
git -C "$R19" add -A && git -C "$R19" commit -qm init
wtq "$R19" "$TMP/w19a"; echo 'a = 2' > "$TMP/w19a/src/a.py"; gq "$TMP/w19a"
wtq "$R19" "$TMP/w19b"; echo 'a = 2' > "$TMP/w19b/src/a.py"
B=$(n 19); gq "$TMP/w19b"
[ "$(( $(n 19) - B ))" = 1 ] && ok "19. suite cached-full sửa input chính xác của nó: không ghi PASS, worktree sau chạy lại" \
  || fail "19. REG-M chạy $(( $(n 19) - B )) lần ở worktree sau, mong 1 (PASS bị ghi dưới khoá chính xác cũ)"

# 20. B1 (Antigravity 20/10): suite cached-full dùng lại theo khoá chính xác, rồi một lượt khác ghi FAIL lên đúng khoá đó trước kết luận:
#     recheck lật nó thành UNTESTED/STALE — phải vào kết luận (exit 4), không đứng ngoài như suite "không chạy được ở máy này".
R20="$TMP/r20"; mkdir -p "$R20/src"
git -C "$R20" init -q -b main . && git -C "$R20" config user.email t@t && git -C "$R20" config user.name t
echo 'a = 1' > "$R20/src/a.py"; echo 'k = 1' > "$R20/src/k.py"
printf '{"project":"t","rules":[{"component":"A","watch_files":["src/a.py"],"mandatory_regression_tests":[{"id":"REG-A","name":"a","command":"true"}]},{"component":"K","watch_files":["src/k.py"],"mandatory_regression_tests":[{"id":"REG-K","name":"k","command":"echo run >> %s/count.20"}]}]}\n' "$TMP" > "$R20/matrix.json"
git -C "$R20" add -A && git -C "$R20" commit -qm init
wtq "$R20" "$TMP/w20a"; echo 'a = 2' > "$TMP/w20a/src/a.py"; gq "$TMP/w20a"   # REG-K cached-full chạy, PASS theo khoá chính xác
sed 's/"REG-CV"/"REG-K"/' "$TMP/l13.py" > "$TMP/l20.py"
wtq "$R20" "$TMP/w20b"; echo 'a = 3' > "$TMP/w20b/src/a.py"
( cd "$TMP/w20b" && FLAKY_RETRY=0 CLAUDE_PROJECT_DIR="$TMP/w20b" python3 "$TMP/l20.py" "$GATE" --matrix "$TMP/w20b/matrix.json" --run-tests \
  --full --no-checklist >"$TMP/out20" 2>&1 ); rc=$?
[ "$rc" = 4 ] && ok "20. suite cached-full bị lật STALE trước kết luận: exit 4 (vào kết luận)" \
  || { fail "20. exit $rc (mong 4): STALE của suite cached-full đứng ngoài kết luận"; grep -E "REG-K|KẾT LUẬN" "$TMP/out20" | tail -3; }

# 21. B2 (Antigravity 20/10): FAIL của lượt Stop chạy lệnh THU HẸP (impacted/package/module) ghi lên khoá của LỆNH ĐẦY ĐỦ của ma trận (khoá
#     lượt --full tra), không lên khoá của lệnh thu hẹp. Launcher ép plan_test_run trả lệnh thu hẹp; kiểm lệnh của bản ghi FAIL trong kho.
R21="$TMP/r21"; mkdir -p "$R21/src"
git -C "$R21" init -q -b main . && git -C "$R21" config user.email t@t && git -C "$R21" config user.name t
echo 'a = 1' > "$R21/src/a.py"
printf '{"project":"t","rules":[{"component":"A","watch_files":["src/a.py"],"mandatory_regression_tests":[{"id":"REG-I","name":"i","command":"echo full","impacted_command":"echo {tests}"}]}]}\n' > "$R21/matrix.json"
git -C "$R21" add -A && git -C "$R21" commit -qm init; echo 'a = 2' > "$R21/src/a.py"
cat > "$TMP/l21.py" <<'PY'
import importlib.util, sys
gate = sys.argv[1]
sys.argv = [gate] + sys.argv[2:]
spec = importlib.util.spec_from_file_location("pfg21", gate)
m = importlib.util.module_from_spec(spec)
sys.modules["pfg21"] = m
spec.loader.exec_module(m)
m.plan_test_run = lambda project_dir, test, force_reason, cache: ("exit 1", "impacted", "", {"count": 1, "tests": {}, "why": {}})
sys.exit(m.main())
PY
( cd "$R21" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R21" python3 "$TMP/l21.py" "$GATE" --matrix "$R21/matrix.json" --run-tests \
  --no-checklist >"$TMP/out21" 2>&1 )
# bản ghi FAIL của REG-I trong kho: lệnh của nó phải là lệnh đầy đủ (khoá tính từ cùng dict với lệnh ghi vào bản ghi)
ST21="$(git -C "$R21" rev-parse --path-format=absolute --git-common-dir)/postfix-gate/suite_cache"
res21="$(python3 - "$ST21" <<'PY'
import glob, json, os, sys
cmds = []
for f in glob.glob(os.path.join(sys.argv[1], "*.json")):
    try:
        r = json.load(open(f))
    except ValueError:
        continue
    if isinstance(r, dict) and r.get("id") == "REG-I" and (r.get("fail_n") or 0) > 0:
        cmds.append(r.get("command"))
print("fail_cmds=%s" % sorted(set(cmds)))
PY
)"
[ "$res21" = "fail_cmds=['echo full']" ] && ok "21. FAIL của lượt Stop chạy lệnh thu hẹp ghi lên khoá của lệnh đầy đủ" \
  || { fail "21. FAIL thu hẹp ghi sai khoá ($res21, mong ['echo full'])"; grep -E "REG-I|suite_cache" "$TMP/out21" | tail -3; }

# 22. M2 (Antigravity 20/10): token "./.claude/bin/x.sh" (dotdir sau tiền tố ./) là input của suite: đổi file đó thì khoá chính xác đổi.
R22="$TMP/r22"; mkdir -p "$R22/.claude/bin"
git -C "$R22" init -q -b main . && git -C "$R22" config user.email t@t && git -C "$R22" config user.name t
echo 'echo one' > "$R22/.claude/bin/x.sh"
printf '{"project":"t","rules":[{"component":"A","watch_files":["nothing/*"],"mandatory_regression_tests":[{"id":"REG-D","name":"d","command":"bash ./.claude/bin/x.sh"}]}]}\n' > "$R22/matrix.json"
git -C "$R22" add -A && git -C "$R22" commit -qm init
key22() { ( cd "$R22" && CLAUDE_PROJECT_DIR="$R22" python3 - "$GATE" "$R22" <<'PY'
import importlib.util, json, os, sys
gate, repo = sys.argv[1:]
spec = importlib.util.spec_from_file_location("pfg22", gate)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
mp = os.path.join(repo, "matrix.json")
rules = json.load(open(mp))["rules"]
print(m.suite_cache_for(repo, rules, mp, {}).keys(dict(rules[0]["mandatory_regression_tests"][0]))[0])
PY
) ; }
k1=$(key22); echo 'echo two' > "$R22/.claude/bin/x.sh"; k2=$(key22)
[ -n "$k1" ] && [ "$k1" != "$k2" ] && ok "22. './.claude/bin/x.sh' là input: đổi file thì khoá chính xác đổi" \
  || fail "22. khoá chính xác không đổi khi ./.claude/bin/x.sh đổi (dotdir mất dấu chấm)"

# 23–25. Đơn vị bin/suite_cache.py (OCR 20/10).
python3 - "$DEVKIT_DIR/bin" "$TMP/u23" <<'PY' || FAILS=$((FAILS + 1))
import os, sys, time
sys.path.insert(0, sys.argv[1])
import suite_cache as sc
d = sys.argv[2]
os.makedirs(os.path.join(d, "lib"), exist_ok=True)
ok = True
def check(name, cond):
    global ok
    print(("✔ " if cond else "✖ ") + name)
    ok = ok and cond
# 23. `import helpers as h` (bí danh) vẫn đưa helpers.py vào bao đóng (từng thành "helpersash.py")
open(os.path.join(d, "t.py"), "w").write("import helpers as h, os\nfrom pkg.mod import x as y\n")
open(os.path.join(d, "helpers.py"), "w").write("X = 1\n")
toks, _ = sc._file_tokens(os.path.join(d, "t.py"), "t.py")
check("23. import có bí danh: helpers.py là token, không có 'helpersash.py'", "helpers.py" in toks and not any("as" in t and t.endswith("ash.py") for t in toks))
# 24. ca này ép id() của mọi Index trùng nhau (CPython cấp lại id sau GC): refs của Index thứ hai phải tính trên content map của nó
real_id = id
sc.id = lambda o: 7   # mọi Index cùng "id"
try:
    open(os.path.join(d, "lib", "a.sh"), "w").write("bash lib/b.sh\n")
    i1 = sc.Index({"lib/a.sh": "x"})
    r1 = sc._file_refs(d, i1, os.path.join(d, "lib", "a.sh"), "lib/a.sh", "lib")
    i2 = sc.Index({"lib/a.sh": "x", "lib/b.sh": "y"})
    r2 = sc._file_refs(d, i2, os.path.join(d, "lib", "a.sh"), "lib/a.sh", "lib")
    check("24. Index mới (file lib/b.sh mới) không nhận refs cũ của Index khác dù id() trùng", "lib/b.sh" in r2[0])
finally:
    del sc.id
# 26. PASS mang giờ suite CHẠY XONG (at=), không phải giờ ghi: một void xảy ra sau lúc suite xong mà trước lúc ghi vẫn chặn PASS đó
#     (review principal vòng 2, P1: PASS cả cây ghi trễ mang mốc sau lần void)
store = os.path.join(d, "store26"); os.makedirs(store, exist_ok=True)
c = sc.SuiteCache.__new__(sc.SuiteCache); c.store = store
t26 = {"id": "REG-26", "command": "true"}
k26 = "b" * 64
ended = time.time() - 5     # suite chạy xong 5 s trước
c.void("REG-26")            # một lần chạy thật không-PASS ở nơi khác, SAU lúc suite này xong
try:
    c.record(k26, t26, "PASS", {"duration": "1s"}, at=ended)
    check("26. void sau lúc suite xong: PASS ghi sau đó (at = giờ chạy xong) không được dùng lại", c.hit(k26, t26) is None)
except TypeError as e:
    check(f"26. record không nhận at= ({e})", False)
# 27. Ghi FAIL / void thất bại (đĩa đầy): PASS cũ của suite đó bị gỡ khỏi kho (unlink không cần chỗ trống) — không bao giờ dùng lại được
store = os.path.join(d, "store27"); os.makedirs(store, exist_ok=True)
c = sc.SuiteCache.__new__(sc.SuiteCache); c.store = store
t27 = {"id": "REG-27", "command": "true"}
k27 = "c" * 64
c.record(k27, t27, "PASS", {"duration": "1s"})
real_mkstemp = sc.tempfile.mkstemp
def full_disk(*a, **k):
    raise OSError(28, "No space left on device")
sc.tempfile.mkstemp = full_disk
try:
    c.record(k27, t27, "FAIL", {"why": "test 27"})
    c.void("REG-27")
finally:
    sc.tempfile.mkstemp = real_mkstemp
check("27. ghi FAIL / void thất bại (ENOSPC): PASS cũ của REG-27 không còn dùng lại được", c.hit(k27, t27) is None)
sys.exit(0 if ok else 1)
PY

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_suite_cache: all passed" || { echo "❌ test_gate_suite_cache: $FAILS failed"; exit 1; }
