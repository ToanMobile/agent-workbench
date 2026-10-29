#!/usr/bin/env bash
# Test hồi quy #616 B: DEVKIT_IMPACTED_DIRS chia REG-DK-ALL-01 theo thư mục (shard). run_impacted.sh --all --list chỉ in test trong thư mục
# được nêu (`gates`), hay trừ thư mục (`!gates,!worktree_git`); không đặt biến thì in tất cả. suite_cache.SELECTION_CMD vẫn nhận lệnh có
# tiền tố DEVKIT_IMPACTED_DIRS=… (giữ cache theo khoá) và selection_list hỏi `--list` kèm đúng biến đó.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE DEVKIT_TEST_JOBS DEVKIT_IMPACTED_DIRS
DK="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; KIT="$R/kit"
mkdir -p "$KIT/tests/gates" "$KIT/tests/worktree_git" "$KIT/tests/verification" "$KIT/hooks/tests" "$KIT/tests/lib"
git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
cp "$DK/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; : > "$KIT/tests/impact_map.txt"
for f in tests/gates/test_g.sh tests/worktree_git/test_w.sh tests/verification/test_repo_consistency.sh tests/verification/test_v.sh hooks/tests/test_h.sh; do echo true > "$KIT/$f"; done
git -C "$R" add -A && git -C "$R" commit -qm init
# every test script edited since HEAD: the impacted selection (--list, no --all: it reads $1) then names all five
for f in tests/gates/test_g.sh tests/worktree_git/test_w.sh tests/verification/test_repo_consistency.sh tests/verification/test_v.sh hooks/tests/test_h.sh; do echo '# edited' >> "$KIT/$f"; done
list() { ( cd "$KIT" && DEVKIT_IMPACTED_DIRS="${1-}" bash tests/run_impacted.sh --list 2>&1 | tr '\n' ' ' ); }

all="$(list)"
[ "$all" = "hooks/tests/test_h.sh tests/gates/test_g.sh tests/verification/test_repo_consistency.sh tests/verification/test_v.sh tests/worktree_git/test_w.sh " ] \
  && ok "không đặt biến: --list in đủ 5 test" || fail "không đặt biến: '$all'"
g="$(list gates)"
[ "$g" = "tests/gates/test_g.sh " ] && ok "DEVKIT_IMPACTED_DIRS=gates: chỉ tests/gates" || fail "gates: '$g'"
w="$(list worktree_git)"
[ "$w" = "tests/worktree_git/test_w.sh " ] && ok "worktree_git: chỉ tests/worktree_git" || fail "worktree_git: '$w'"
rest="$(list '!gates,!worktree_git')"
[ "$rest" = "hooks/tests/test_h.sh tests/verification/test_repo_consistency.sh tests/verification/test_v.sh " ] \
  && ok "!gates,!worktree_git: phần còn lại (kể cả hooks/tests)" || fail "REST: '$rest'"
u="$(printf '%s\n%s\n%s\n' "$g" "$w" "$rest" | tr ' ' '\n' | grep . | sort | tr '\n' ' ')"
[ "$u" = "$(printf '%s' "$all" | tr ' ' '\n' | grep . | sort | tr '\n' ' ')" ] && ok "3 shard hợp lại đúng tập đủ, không trùng" || fail "hợp 3 shard khác tập đủ: '$u'"

# suite_cache: SELECTION_CMD + selection_list
res="$(cd "$DK" && python3 -I - "$KIT" <<'PY'
import sys
sys.path.insert(0, "bin")
import suite_cache as sc
kit = sys.argv[1]
c0 = "bash kit/tests/run_impacted.sh"
c1 = "DEVKIT_IMPACTED_DIRS=gates bash kit/tests/run_impacted.sh"
c2 = "DEVKIT_IMPACTED_DIRS=!gates,!worktree_git bash kit/tests/run_impacted.sh"
bad = "DEVKIT_IMPACTED_DIRS=gates; echo injected bash kit/tests/run_impacted.sh"
print(bool(sc.SELECTION_CMD.match(c0)), bool(sc.SELECTION_CMD.match(c1)), bool(sc.SELECTION_CMD.match(c2)), bool(sc.SELECTION_CMD.match(bad)))
root = kit.rsplit("/", 1)[0]
print(sc.selection_list(root, c1), sc.selection_list(root, c2))
PY
)"
echo "$res" | sed -n 1p | grep -qx 'True True True False' && ok "SELECTION_CMD nhận lệnh có/không tiền tố biến, từ chối chuỗi lạ" || fail "SELECTION_CMD: $res"
echo "$res" | sed -n 2p | grep -qx "\['tests/gates/test_g.sh'\] \['hooks/tests/test_h.sh', 'tests/verification/test_repo_consistency.sh', 'tests/verification/test_v.sh'\]" \
  && ok "selection_list trả đúng tập theo shard" || fail "selection_list: $res"
# Biến shard không rò vào test con: test_gate_friction / per_test_cache / impact_map tự chạy run_impacted.sh, thừa hưởng biến thì tập chọn của chúng rỗng
# (gate #616 lượt 2: 7 suite đỏ). Test gates/test_g.sh ghi giá trị nó thấy ra file.
printf 'printf %%s "${DEVKIT_IMPACTED_DIRS-unset}" > "$SEEN_FILE"\n' > "$KIT/tests/gates/test_g.sh"
( cd "$KIT" && SEEN_FILE="$TMP/seen" DEVKIT_IMPACTED_DIRS=gates bash tests/run_impacted.sh >/dev/null 2>&1 )
[ "$(cat "$TMP/seen" 2>/dev/null)" = "unset" ] && ok "test con không thấy DEVKIT_IMPACTED_DIRS" || fail "test con thấy DEVKIT_IMPACTED_DIRS='$(cat "$TMP/seen" 2>/dev/null)'"

[ "$FAILS" = 0 ] && echo "PASS" || echo "FAIL: $FAILS"
exit $(( FAILS > 0 ))
