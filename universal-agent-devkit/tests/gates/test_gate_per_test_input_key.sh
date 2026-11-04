#!/usr/bin/env bash
# Test hồi quy (chủ repo 04/11: "lỗi 1 chỗ thì chạy lại 1 chỗ thôi"): lượt --scoped đỏ 1/117 test, sửa một commit nhỏ rồi chạy lại thì MỌI
# test chạy lại — sổ PASS từng test (tests/lib/per_test_cache.py) khoá CẢ CÂY. Nay ở lượt không --all, test thường khoá theo INPUT RIÊNG của
# nó: SuiteCache.selection_inputs(runner, [test]) — cùng đồ thị bin/scoped_gate.py mà khoá chính xác của shard run_impacted.sh đã dùng (#851).
# Test quét cả kit (devkit-selection-tree của runner), test không phải nút đồ thị, và lượt --all giữ khoá cả cây.
# Kit giả: run_impacted.sh THẬT + helper THẬT; gọi runner trực tiếp với DEVKIT_PER_TEST_CACHE=1 + DEVKIT_SCOPED_TESTS như gate --scoped đặt.
#   test_a đọc lib/alpha.txt (F); test_b đọc "$D/lib/beta.txt" và `import gammamod` trong heredoc python, KHÔNG đọc F;
#   tests/verification/test_repo_consistency.sh (C) là test quét cả kit; tests/build/test_d.sh nằm ngoài đồ thị (thư mục build bị bỏ qua).
#   K1. lượt đầu: a b c d chạy.  K2. commit chỉ đổi F: a, c, d chạy lại; b DÙNG LẠI (↺) — code cũ (khoá cả cây) chạy lại b ⇒ ĐỎ.
#   K3. đổi lib/beta.txt (đọc qua "$D/lib/x"): b PHẢI chạy lại.  K4. đổi lib/gammamod.py (import trong heredoc): b PHẢI chạy lại.
#   K5. b FAIL ở lượt --all (khoá cả cây) trên cây mới: lượt scoped cùng cây không được dùng lại PASS cũ theo input của b.
#   K6. lượt --all: khoá cả cây — đổi F thì b chạy lại.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_SUITE_CACHE_MAX_S DEVKIT_SUITE_CACHE DEVKIT_SENTINEL_MAX_S CI FLAKY_RETRY \
      DEVKIT_GATE_PARALLEL DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE DEVKIT_IMPACTED_DIRS DEVKIT_SCOPED_TESTS \
      DEVKIT_TEST_JOBS DEVKIT_PER_TEST_CACHE DEVKIT_PTC_INPUT_KEY DEVKIT_TEST_TIMEOUT_S DEVKIT_FLAKY_QUARANTINE_S
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1
mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
n()    { [ -f "$TMP/count.$1" ] && wc -l < "$TMP/count.$1" | tr -d ' ' || echo 0; }
counts() { echo "$(n a) $(n b) $(n c) $(n d)"; }
delta()  { set -- $1; echo "$(( $(n a) - $1 )) $(( $(n b) - $2 )) $(( $(n c) - $3 )) $(( $(n d) - $4 ))"; }   # delta "<counts trước>"

R="$TMP/repo"; KIT="$R/universal-agent-devkit"
mkdir -p "$KIT/tests/gates" "$KIT/tests/verification" "$KIT/tests/build" "$KIT/tests/lib" "$KIT/lib"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; echo '# trống' > "$KIT/tests/impact_map.txt"
cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
ln -s "$DEVKIT_DIR/bin" "$KIT/bin"   # post-fix-gate.py + suite_cache.py + scoped_gate.py của checkout đang kiểm
echo v1 > "$KIT/lib/alpha.txt"; echo v1 > "$KIT/lib/beta.txt"; echo 'OK = True' > "$KIT/lib/gammamod.py"
printf 'DK="$(cd "$(dirname "$0")/../.." && pwd)"\ngrep -q v "$DK/lib/alpha.txt" || exit 1\necho a >> %s/count.a\n' "$TMP" > "$KIT/tests/gates/test_a.sh"
printf 'D="$(cd "$(dirname "$0")/../.." && pwd)"\ngrep -q v "$D/lib/beta.txt" || exit 1\nPYTHONPATH="$D/lib" python3 - <<%sEOF%s || exit 1\nimport gammamod\nassert gammamod.OK\nEOF\n[ -f %s/fail_b ] && exit 1\necho b >> %s/count.b\n' \
  "'" "'" "$TMP" "$TMP" > "$KIT/tests/gates/test_b.sh"
printf 'echo c >> %s/count.c\n' "$TMP" > "$KIT/tests/verification/test_repo_consistency.sh"
printf 'echo d >> %s/count.d\n' "$TMP" > "$KIT/tests/build/test_d.sh"
printf '.claude/\n' > "$R/.gitignore"
git -C "$R" add -A && git -C "$R" commit -qm init
SCOPED="tests/gates/test_a.sh tests/gates/test_b.sh tests/build/test_d.sh"

# run <out> [--all]: runner như gate đặt (--scoped: DEVKIT_SCOPED_TESTS; runner tự thêm test_repo_consistency.sh)
run() {
  local o="$1"; shift
  if [ "${1:-}" = "--all" ]; then ( cd "$R" && DEVKIT_PER_TEST_CACHE=1 bash universal-agent-devkit/tests/run_impacted.sh --all >"$TMP/$o" 2>&1 ); RC=$?
  else ( cd "$R" && DEVKIT_PER_TEST_CACHE=1 DEVKIT_SCOPED_TESTS="$SCOPED" bash universal-agent-devkit/tests/run_impacted.sh >"$TMP/$o" 2>&1 ); RC=$?; fi
}
commit() { echo "$2" > "$KIT/$1" && git -C "$R" commit -qam "đổi $1"; }

# K1. lượt đầu: bốn test chạy thật
B="$(counts)"; run out1; d="$(delta "$B")"
if [ "$RC" = 0 ] && [ "$d" = "1 1 1 1" ]; then ok "K1. lượt đầu: a b c d chạy"
else fail "K1. exit $RC, chạy thêm a b c d = $d (mong 0, 1 1 1 1)"; cat "$TMP/out1"; fi

# K2. commit chỉ đổi F (lib/alpha.txt, b không đọc): a chạy lại; c (quét cả kit) và d (ngoài đồ thị) giữ khoá cả cây nên chạy lại; b dùng lại
commit lib/alpha.txt v2
B="$(counts)"; run out2; d="$(delta "$B")"
if [ "$RC" = 0 ] && [ "$d" = "1 0 1 1" ] && grep -q "^↺ tests/gates/test_b.sh" "$TMP/out2" && grep -q "^✔ tests/gates/test_a.sh" "$TMP/out2"; then
  ok "K2. đổi F: a, c (quét cả kit), d (không tính được input) chạy lại; b không đọc F dùng lại PASS (↺)"
else fail "K2. exit $RC, chạy thêm a b c d = $d (mong 0, 1 0 1 1: b không đọc F phải dùng lại)"; grep -E "^[↺✔✖]|per_test" "$TMP/out2"; fi

# K3. b đọc "$D/lib/beta.txt": đổi nó ⇒ b chạy lại (a dùng lại)
commit lib/beta.txt v2
B="$(counts)"; run out3; d="$(delta "$B")"
if [ "$RC" = 0 ] && [ "$(echo "$d" | cut -d' ' -f2)" = 1 ] && ! grep -q "^↺ tests/gates/test_b.sh" "$TMP/out3"; then
  ok "K3. đổi file b đọc qua \"\$D/lib/x\": b chạy lại"
else fail "K3. exit $RC, chạy thêm a b c d = $d (mong b = 1)"; grep -E "^[↺✔✖]" "$TMP/out3"; fi

# K4. b import gammamod trong heredoc python: đổi gammamod.py ⇒ b chạy lại
commit lib/gammamod.py 'OK = True  # v2'
B="$(counts)"; run out4; d="$(delta "$B")"
if [ "$RC" = 0 ] && [ "$(echo "$d" | cut -d' ' -f2)" = 1 ] && ! grep -q "^↺ tests/gates/test_b.sh" "$TMP/out4"; then
  ok "K4. đổi module b import trong heredoc python: b chạy lại"
else fail "K4. exit $RC, chạy thêm a b c d = $d (mong b = 1)"; grep -E "^[↺✔✖]" "$TMP/out4"; fi

# K5. cây mới chỉ đổi F (b có PASS theo input từ K4); b FAIL ở lượt --all (khoá cả cây) trên cây này; hết cờ, lượt scoped cùng cây: b chạy
commit lib/alpha.txt v3
: > "$TMP/fail_b"; run out5a --all; r5a=$RC; rm -f "$TMP/fail_b"
B="$(counts)"; run out5b; d="$(delta "$B")"
if [ "$r5a" != 0 ] && grep -q "^✖ tests/gates/test_b.sh" "$TMP/out5a" && [ "$RC" = 0 ] && [ "$(echo "$d" | cut -d' ' -f2)" = 1 ] \
   && ! grep -q "^↺ tests/gates/test_b.sh" "$TMP/out5b"; then
  ok "K5. b FAIL ở lượt --all trên cây này: lượt scoped cùng cây không dùng lại PASS cũ của b"
else fail "K5. exit $r5a rồi $RC (mong ≠0 rồi 0), chạy thêm a b c d = $d (mong b = 1)"; grep -E "^[↺✔✖]" "$TMP/out5a" "$TMP/out5b"; fi

# K6. lượt --all giữ khoá cả cây: một lượt --all PASS, đổi F, lượt --all nữa ⇒ b chạy lại
run out6a --all; r6a=$RC
commit lib/alpha.txt v4
B="$(counts)"; run out6b --all; d="$(delta "$B")"
if [ "$r6a $RC" = "0 0" ] && [ "$(echo "$d" | cut -d' ' -f2)" = 1 ] && ! grep -q "^↺ tests/gates/test_b.sh" "$TMP/out6b"; then
  ok "K6. lượt --all: khoá cả cây, đổi F thì b chạy lại"
else fail "K6. exit $r6a $RC (mong 0 0), chạy thêm a b c d = $d (mong b = 1)"; grep -E "^[↺✔✖]" "$TMP/out6b"; fi

# K7. selection_inputs không được phụ thuộc thứ tự duyệt set (PYTHONHASHSEED): hub lõi hub.sh nhắc n1.sh (lõi) và n2.sh (không lõi), n2.sh
#     nhắc n1.sh, n1.sh chạy test_x.sh. Vòng mở hub từng bỏ qua n1 khi n2 đã chạm tới nó trước (n1 chỉ được VÀO, không mở) ⇒ test_x.sh có
#     hay không tuỳ seed (đo 04/11 trên bản sao agent-workbench, 117 test cùng cây: lượt plan thứ hai chỉ dùng lại 2/117) và một lượt rút
#     tập nhỏ có thể trùng khoá cũ sau khi test_x.sh đổi (PASS sai). Mọi seed phải cho cùng một tập, có test_x.sh.
R2="$TMP/repo2"; K2="$R2/universal-agent-devkit"
mkdir -p "$K2/tests/gates" "$K2/bin" "$R2/.agents"
git -C "$R2" init -q -b main . && git -C "$R2" config user.email t@t && git -C "$R2" config user.name t
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$K2/tests/run_impacted.sh"; echo '# trống' > "$K2/tests/impact_map.txt"
printf '[core]\nuniversal-agent-devkit/bin/hub.sh\nuniversal-agent-devkit/bin/n1.sh\n' > "$R2/.agents/gate-core.txt"
printf 'DK="$(cd "$(dirname "$0")/../.." && pwd)"\nbash "$DK/bin/hub.sh"\n' > "$K2/tests/gates/test_t.sh"
printf 'DK="$(cd "$(dirname "$0")/.." && pwd)"\nbash "$DK/bin/n1.sh"\nbash "$DK/bin/n2.sh"\n' > "$K2/bin/hub.sh"
printf 'DK="$(cd "$(dirname "$0")/.." && pwd)"\nbash "$DK/bin/n1.sh"\n' > "$K2/bin/n2.sh"
printf 'DK="$(cd "$(dirname "$0")/.." && pwd)"\nbash "$DK/tests/gates/test_x.sh"\n' > "$K2/bin/n1.sh"
printf 'echo x\n' > "$K2/tests/gates/test_x.sh"
git -C "$R2" add -A && git -C "$R2" commit -qm init
sets=""; miss=0
for seed in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  s="$(cd "$R2" && PYTHONHASHSEED=$seed python3 - "$DEVKIT_DIR/bin" "$R2" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import suite_cache
sc = suite_cache.SuiteCache(sys.argv[2], [], None, {}, "x", 0, {})
got = sc.selection_inputs("universal-agent-devkit/tests/run_impacted.sh", ["tests/gates/test_t.sh"])
print(",".join(sorted(got)) if got is not None else "NONE")
PY
)"
  case ",$s," in *,universal-agent-devkit/tests/gates/test_x.sh,*) ;; *) miss=$((miss + 1)) ;; esac
  sets="$sets$s
"
done
nd="$(printf '%s' "$sets" | sort -u | grep -c .)"
if [ "$nd" = 1 ] && [ "$miss" = 0 ]; then ok "K7. selection_inputs như nhau ở 16 seed, có test_x.sh (n1 lõi luôn được mở)"
else fail "K7. selection_inputs: $nd tập khác nhau qua 16 seed, $miss seed thiếu test_x.sh (mong 1 tập, 0 thiếu)"; fi

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_per_test_input_key: all passed" || { echo "❌ test_gate_per_test_input_key: $FAILS failed"; exit 1; }
