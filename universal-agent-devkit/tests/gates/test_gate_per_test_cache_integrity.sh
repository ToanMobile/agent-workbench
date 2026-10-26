#!/usr/bin/env bash
# Test hồi quy (#427) cho sổ PASS theo từng test (tests/lib/per_test_cache.py, kho per_test của bin/suite_cache.py) — ba đường chưa có ca:
#  A. ABA: input bị sửa rồi hoàn tác (cùng bytes, cùng inode, trả lại cả mtime) trong lúc test chạy. record từng chỉ so nội dung cây lúc
#     kết thúc nên vẫn ghi PASS cho nội dung test không thấy trọn vẹn; nay so thêm dấu stat (ino, size, mtime_ns, ctime_ns) lấy lúc plan.
#  C. mâu thuẫn: khoá đang PASS mà một lần chạy thật trên CÙNG khoá FAIL ⇒ cách ly id (quarantine.json + sentinel_report.jsonl của kho per_test).
#  D. dọn kho per_test: PASS cũ hơn 7 ngày bị xoá, FAIL giữ tới 30 ngày; kho suite (thư mục cha) không bị đụng.
# Repo tạm riêng (kho riêng trong .git của nó, không ghi vào kho dùng chung của repo thật): run_impacted.sh THẬT + helper THẬT, ba test:
# t_ctl không làm gì, t_aba sửa rồi hoàn tác lib/in.txt (đã commit) khi có cờ aba ngoài cây, t_flip FAIL khi có cờ flip. run_impacted.sh
# gọi trực tiếp với DEVKIT_PER_TEST_CACHE như gate đặt (như tests/gates/test_gate_per_test_cache.sh; các ca ở đây cần repo riêng: một lần
# ABA chặn PASS của mọi test xong sau nó, và t3 của file kia đã bị cách ly). Mỗi test ghi một dòng vào count.<tên> khi CHẠY XONG.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SENTINEL_MAX_S CI FLAKY_RETRY DEVKIT_GATE_PARALLEL \
  DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE DEVKIT_TEST_JOBS DEVKIT_PER_TEST_CACHE DEVKIT_SUITE_CACHE \
  DEVKIT_TEST_TIMEOUT_S DEVKIT_FLAKY_QUARANTINE_S
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n() { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }
reused() { grep -q "^↺ tests/v/test_$1.sh" "$TMP/$2"; }   # reused <tên> <file output>

R="$TMP/repo"; KIT="$R/universal-agent-devkit"
mkdir -p "$KIT/tests/v" "$KIT/tests/lib" "$KIT/lib"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; : > "$KIT/tests/impact_map.txt"
cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
ln -s "$DEVKIT_DIR/bin" "$KIT/bin"   # post-fix-gate.py + suite_cache.py mà helper nạp
echo A > "$KIT/lib/in.txt"; echo 0 > "$KIT/notes.txt"
printf 'echo c >> %s/count.ctl\n' "$TMP" > "$KIT/tests/v/test_ctl.sh"
# t_aba: A→B→A TẠI CHỖ (cùng inode), trả lại đúng bytes và atime/mtime_ns — chỉ ctime còn khác (sửa chỉ theo mtime hay nội dung vẫn đỏ)
cat > "$KIT/tests/v/test_aba.sh" <<EOF
F="\$(cd "\$(dirname "\$0")/../.." && pwd)/lib/in.txt"
if [ -f "$TMP/aba" ]; then
  m="\$(python3 -c 'import os, sys; s = os.stat(sys.argv[1]); print(s.st_atime_ns, s.st_mtime_ns)' "\$F")"
  cp "\$F" "$TMP/in.save"
  echo B > "\$F"
  cat "$TMP/in.save" > "\$F"
  python3 -c 'import os, sys; os.utime(sys.argv[1], ns=(int(sys.argv[2]), int(sys.argv[3])))' "\$F" \$m
fi
echo a >> "$TMP/count.aba"
EOF
printf '[ -f %s/flip ] && exit 1\necho f >> %s/count.flip\n' "$TMP" "$TMP" > "$KIT/tests/v/test_flip.sh"
git -C "$R" add -A && git -C "$R" commit -qm init
STORE="$R/.git/postfix-gate/suite_cache"; PT="$STORE/per_test"
FLIP_ID="per-test:universal-agent-devkit/tests/v/test_flip.sh"
# direct <DEVKIT_PER_TEST_CACHE> <file output>: run_impacted.sh --all gọi thẳng, trên cây đang có
direct() { ( cd "$R" && DEVKIT_PER_TEST_CACHE="$1" bash universal-agent-devkit/tests/run_impacted.sh --all >"$TMP/$2" 2>&1 ); RC=$?; }
# sig: "ino mtime_ns bytes" của lib/in.txt — ca A2 chỉ hợp lệ khi ABA trả lại đúng ba thứ này
sig() { python3 -c 'import os, sys; s = os.stat(sys.argv[1]); print(s.st_ino, s.st_mtime_ns, open(sys.argv[1]).read().strip())' "$KIT/lib/in.txt"; }

# A1. Đối chứng: lượt không ai đụng cây ghi PASS; lượt sau cùng cây dùng lại cả ba (↺), không test nào chạy thêm.
direct 1 a1; r1=$RC
a=$(n aba); c=$(n ctl); direct 1 a1b
if [ "$r1 $RC" = "0 0" ] && reused aba a1b && reused ctl a1b && [ "$(n aba) $(n ctl)" = "$a $c" ]; then
  ok "A1. lượt không ai đụng cây: PASS được ghi, lượt sau cùng cây dùng lại (↺)"
else fail "A1. exit $r1 $RC (mong 0 0), aba/ctl chạy $a/$c → $(n aba)/$(n ctl) (mong không đổi)"; cat "$TMP/a1b"; fi

# A2. ABA trong lúc t_aba chạy (cây mới): nội dung, inode, mtime của lib/in.txt y nguyên sau lượt — PASS của t_aba vẫn KHÔNG được ghi:
#     lượt sau cùng cây chạy t_aba lại.
echo 1 > "$KIT/notes.txt"; s0="$(sig)"
: > "$TMP/aba"; direct 1 a2; r2=$RC; rm -f "$TMP/aba"; s1="$(sig)"
a=$(n aba); direct 1 a2b
if [ "$s0" != "$s1" ]; then fail "A2. ca thử hỏng: ABA không trả lại đúng ino/mtime/bytes ('$s0' → '$s1')"
elif [ "$r2 $RC" = "0 0" ] && [ "$(n aba)" = $((a + 1)) ] && ! reused aba a2b; then
  ok "A2. sửa rồi hoàn tác input (cùng bytes, inode, mtime) trong lúc test chạy: không ghi PASS, lượt sau chạy lại"
else fail "A2. exit $r2 $RC (mong 0 0), t_aba chạy $a → $(n aba) (mong +1); $(grep 'test_aba' "$TMP/a2" "$TMP/a2b")"; fi

# A3. Chặn không dính: lượt A2b không ai đụng cây đã ghi PASS — lượt sau cùng cây dùng lại t_aba.
direct 1 a3
if [ "$RC" = 0 ] && reused aba a3; then ok "A3. sau một lượt sạch trên cùng cây, t_aba lại được dùng lại (↺)"
else fail "A3. exit $RC, t_aba: $(grep 'test_aba' "$TMP/a3")"; fi

# C1. Mâu thuẫn: cây mới, t_flip PASS (chưa bị cách ly); lượt chỉ-ghi (như sentinel / --no-cache) cùng cây, t_flip FAIL trên khoá đang
#     PASS ⇒ cách ly id, ghi sentinel_report.jsonl (không file nào đổi: learned rỗng).
echo 2 > "$KIT/notes.txt"; direct 1 c1; r1=$RC
q0=no; grep -qF "$FLIP_ID" "$PT/quarantine.json" 2>/dev/null && q0=yes
: > "$TMP/flip"; direct record c1b; r2=$RC; rm -f "$TMP/flip"
rep="$(python3 - "$PT/sentinel_report.jsonl" "$FLIP_ID" <<'PY' 2>/dev/null
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print(any(r.get("id") == sys.argv[2] and r.get("learned") == [] and not r.get("flaky") for r in rows))
PY
)"
if [ "$r1" = 0 ] && [ "$q0" = no ] && [ "$r2" != 0 ] && grep -qF "$FLIP_ID" "$PT/quarantine.json" 2>/dev/null && [ "$rep" = True ] \
   && grep -q "cách ly" "$TMP/c1b"; then
  ok "C1. PASS rồi FAIL trên cùng khoá: id bị cách ly, sentinel_report ghi mâu thuẫn"
else fail "C1. exit $r1 $r2 (mong 0, ≠0), cách ly trước: $q0 (mong no), sau: $(cat "$PT/quarantine.json" 2>/dev/null), report: $rep"
  grep -E "test_flip|per_test_cache" "$TMP/c1b"; fi

# C2. Cách ly giữ trên cây mới: hai lượt cùng cây, lượt sau t_flip vẫn chạy thật (t_ctl dùng lại).
echo 3 > "$KIT/notes.txt"; direct 1 c2
f=$(n flip); direct 1 c2b
if [ "$RC" = 0 ] && [ "$(n flip)" = $((f + 1)) ] && ! reused flip c2b && reused ctl c2b; then
  ok "C2. id bị cách ly: PASS sạch trên cây mới cũng không được dùng lại (t_ctl thì có)"
else fail "C2. exit $RC, t_flip chạy $f → $(n flip) (mong +1); $(grep -E 'test_(flip|ctl)' "$TMP/c2b")"; fi

# D1. Dọn kho per_test (mốc prune.stamp quá 1 h): PASS 8 ngày bị xoá, FAIL 8 ngày giữ, FAIL 31 ngày bị xoá, PASS mới giữ; một PASS 8 ngày
#     trong kho suite (thư mục cha) không bị đụng — mỗi kho tự dọn.
python3 - "$PT" "$STORE" <<'PY'
import json, os, sys, time
pt, store = sys.argv[1], sys.argv[2]
now, day = time.time(), 86400
def put(d, name, rec, age):
    p = os.path.join(d, name * 64 + ".json")
    json.dump(dict({"v": 1, "command": "bash x", "last_pass_at": now - age}, **rec), open(p, "w"))
    os.utime(p, (now - age, now - age))
put(pt, "a", {"id": "per-test:old_pass", "pass_n": 1, "fail_n": 0}, 8 * day)
put(pt, "b", {"id": "per-test:fail_8d", "pass_n": 0, "fail_n": 1}, 8 * day)
put(pt, "c", {"id": "per-test:fail_31d", "pass_n": 0, "fail_n": 1}, 31 * day)
put(store, "d", {"id": "REG-SUITE-OLD", "pass_n": 1, "fail_n": 0}, 8 * day)
stamp = os.path.join(pt, "prune.stamp")
open(stamp, "a").close()
os.utime(stamp, (now - 7200, now - 7200))
PY
echo 4 > "$KIT/notes.txt"; direct 1 d1
has() { [ -f "$1/$(printf "%064d" 0 | tr 0 "$2").json" ] && echo 1 || echo 0; }
fresh="$(grep -l "test_ctl.sh" "$PT"/*.json 2>/dev/null | wc -l | tr -d ' ')"
got="$(has "$PT" a) $(has "$PT" b) $(has "$PT" c) $(has "$STORE" d)"
if [ "$RC" = 0 ] && [ "$got" = "0 1 0 1" ] && [ "$fresh" -ge 1 ]; then
  ok "D1. dọn kho per_test: PASS 8 ngày xoá, FAIL 8 ngày giữ, FAIL 31 ngày xoá, PASS mới giữ; kho suite không bị đụng"
else fail "D1. exit $RC, còn PASS-8d FAIL-8d FAIL-31d suite-PASS-8d = $got (mong 0 1 0 1), bản ghi mới của t_ctl: $fresh (mong ≥1)"; fi

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_per_test_cache_integrity: all passed" || { echo "❌ test_gate_per_test_cache_integrity: $FAILS failed"; exit 1; }
