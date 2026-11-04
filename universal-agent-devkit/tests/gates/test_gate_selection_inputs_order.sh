#!/usr/bin/env bash
# Test hồi quy (05/11): SuiteCache.selection_inputs (#851, khoá chính xác shard run_impacted.sh) không phụ thuộc thứ tự duyệt set
# (PYTHONHASHSEED) — K7; và sổ PASS từng test giữ khoá CẢ CÂY nên test liệt kê file lúc chạy (glob ngoài đồ thị) chạy lại khi file đó
# đổi — K8 (review PR #993: khoá theo input từng test bị rút vì đồ thị không thấy file liệt kê lúc chạy ⇒ PASS sai).
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

# K8 (review P1, 05/11). Ca: test glob .claude/skills/*/SKILL.md ngoài kit trong heredoc python (dạng của test_skill_size.sh).
# Mong: SKILL.md đổi quá giới hạn thì lượt sau chạy lại test đó và ĐỎ (không có dòng reuse=1).
R8="$TMP/k8"; K8="$R8/universal-agent-devkit"
mkdir -p "$K8/tests/verification" "$K8/tests/lib" "$R8/.claude/skills/foo"
git -C "$R8" init -q -b main . && git -C "$R8" config user.email t@t && git -C "$R8" config user.name t
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$K8/tests/run_impacted.sh"; echo '# trống' > "$K8/tests/impact_map.txt"
cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$K8/tests/lib/"
ln -s "$DEVKIT_DIR/bin" "$K8/bin"
printf -- '---\nname: foo\n---\nshort\n' > "$R8/.claude/skills/foo/SKILL.md"
cat > "$K8/tests/verification/test_size.sh" <<'T'
DK="$(cd "$(dirname "$0")/../.." && pwd)"; ROOT="$(cd "$DK/.." && pwd)"
python3 -I - "$ROOT/.claude/skills" <<'PY'
import glob, os, sys
bad = [p for p in glob.glob(os.path.join(sys.argv[1], "*", "SKILL.md")) if len(open(p).read()) > 50]
sys.exit(1 if bad else 0)
PY
T
printf '.claude/settings*\n' > "$R8/.gitignore"
git -C "$R8" add -A && git -C "$R8" commit -qm init
run8() { ( cd "$R8" && SB_HEAVY_SLOT_DIR="$TMP/k8slots" DEVKIT_PER_TEST_CACHE=1 DEVKIT_SCOPED_TESTS="tests/verification/test_size.sh" \
  bash universal-agent-devkit/tests/run_impacted.sh > "$TMP/out8" 2>&1 ); }
mkdir -p "$TMP/k8slots"
run8; r8a=$?
python3 -c "print('x'*200)" >> "$R8/.claude/skills/foo/SKILL.md"; git -C "$R8" commit -qam "foo SKILL.md quá giới hạn"
run8; RC=$?
if [ "$r8a" = 0 ] && [ "$RC" != 0 ] && ! grep -q "reuse=1" "$TMP/out8"; then ok "K8. test glob file ngoài đồ thị giữ khoá cả cây: SKILL.md đổi ⇒ chạy lại và ĐỎ"
else fail "K8. exit $r8a rồi $RC (mong 0 rồi ≠0): test liệt kê file lúc chạy dùng lại PASS cũ"; grep -E "test_size|per_test" "$TMP/out8"; fi

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_selection_inputs_order: all passed" || { echo "❌ test_gate_selection_inputs_order: $FAILS failed"; exit 1; }
