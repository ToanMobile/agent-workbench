#!/usr/bin/env bash
# 04/11 (duyệt test sửa không bước người): merge gate / train hỏi `--has-edited-tests` để giữ đường bi quan (verify trong khoá, không
# autosync, exit 2 khi base đi trước head). Duyệt nay tra thẳng biên bản antigravity-pm (post-fix-gate _pm_audit_cross_review), không
# còn comment edited-tests, nên --has-edited-tests ... --top --base cũng hỏi biên bản: audit pass có auditedHead trong <base>..<head> = pm (không phải true của comment).
#  E1 audit trên nhánh PR -> pm (code cũ: false). E2 audit chỉ trên main -> false. E3 người gọi cũ (không --top) -> false như cũ.
#  E4 base không resolve -> pm (không kiểm được: bi quan). E5 pm home lạ không phải fixture -> false (biên bản không tính).
#  E6 PR có audit nhưng không sửa test đã có (chỉ code) -> false: audit lớn không làm PR thường bi quan. E7 sửa script ma trận nhắc tên
#  (script suite) -> pm.
#  E8 sửa script tầng hai không có tên trong ma trận -> pm. E9 ma trận chỉ ở cây làm việc (không ở base) -> false. E11 rule ma trận PR nối thêm -> pm.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
INS="$ROOT/.claude/bin/super-board-install-edited-test-approval.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-et-pm.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
export DEVKIT_PM_HOME_TEST=1
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R/tests" && cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
mkdir -p src bin && echo a > tests/t.sh && echo 'fun a()=1' > src/a.kt && echo 'echo ok' > bin/suite-runner && git add -A && git commit -qm M0
M0="$(git rev-parse HEAD)"
git checkout -q -b feat && echo b > tests/t.sh && git commit -qam "PR sửa test"
X="$(git rev-parse HEAD)"
git commit -q --allow-empty -m "PR tiếp"
H="$(git rev-parse HEAD)"
echo '{"comments":[]}' > "$TMP/meta.json"
pm() {   # pm <task-id> <auditedHead>: audit pass do PM tự chạy grok
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  printf '{"id":"%s","project":"%s","dispatches":[{"kind":"audit","agent":"grok","at":"2026-11-04T00:00:00Z"}],"verdicts":{"audit":{"verdict":"pass","round":1,"reviewer":"grok","notes":"ok","auditedHead":"%s"}}}\n' \
    "$1" "$(pwd -P)" "$2" > "$TMP/pm/projects/p-$1/tasks/$1/task.json"
}
has_et() { local out rc=0; out=$(bash "$INS" --has-edited-tests "$TMP/meta.json" "$@" 2>/dev/null) || rc=$?; printf '%s %s' "$rc" "$out"; }

pm T2001-main "$M0"
got="$(has_et "$H" --top "$R" --base main)"
[ "$got" = "1 false" ] && ok "E2: audit chỉ trên main -> false" || fail "E2: audit trên main: '$got' (muốn '1 false')"

pm T2002-pr "$X"
got="$(has_et "$H" --top "$R" --base main)"
[ "$got" = "0 pm" ] && ok "E1: audit pass trên nhánh PR, không comment -> pm (giữ khoá, không autosync)" || fail "E1: audit trên PR: '$got' (muốn '0 pm')"

got="$(has_et "$H")"
[ "$got" = "1 false" ] && ok "E3: người gọi cũ không --top/--base -> false như cũ" || fail "E3: CLI cũ: '$got' (muốn '1 false')"

got="$(has_et "$H" --top "$R" --base no-such-ref)"
[ "$got" = "0 pm-unknown" ] && ok "E4: base không resolve -> pm-unknown (bi quan, không phải duyệt)" || fail "E4: base hỏng: '$got' (muốn '0 pm-unknown')"

got="$(DEVKIT_PM_HOME_TEST=0 has_et "$H" --top "$R" --base main)"
[ "$got" = "1 false" ] && ok "E5: pm home lạ không phải fixture -> false" || fail "E5: pm home lạ: '$got' (muốn '1 false')"

git checkout -q -b code main && echo 'fun a()=2' > src/a.kt && git commit -qam "PR chỉ sửa code"
C="$(git rev-parse HEAD)"; pm T2003-code "$C"
got="$(has_et "$C" --top "$R" --base main)"
[ "$got" = "1 false" ] && ok "E6: PR có audit nhưng không sửa test đã có -> false" || fail "E6: PR chỉ code: '$got' (muốn '1 false')"

git checkout -q main && mkdir -p .agents && echo '{"rules":[{"mandatory_regression_tests":[{"command":"bash bin/suite-runner"}]}]}' > .agents/regression_matrix.active.json && git add .agents && git commit -qm "ma trận" && git checkout -q -b runner main && echo 'exit 0' > bin/suite-runner && git commit -qam "PR sửa script suite"
U="$(git rev-parse HEAD)"; pm T2004-runner "$U"
# (ma trận đã commit lên main ở trên: detector đọc ma trận ở base như gate)
got="$(has_et "$U" --top "$R" --base main)"
[ "$got" = "0 pm" ] && ok "E7: PR sửa script ma trận nhắc tên, có audit -> pm" || fail "E7: script suite: '$got' (muốn '0 pm')"

# E8 (Grok review 04/11): script tầng hai — ma trận gọi bin/suite-runner, nó gọi tools/helper.py (gate theo suite_runner_paths); PR chỉ
#    sửa helper.py (không phải đường dẫn test, tên không có trong ma trận) -> pm. E10 (OCR vòng 2): .py không ai nhắc -> false.
git checkout -q -b helper main && mkdir -p tools && echo 'print(1)' > tools/helper.py && echo 'print(0)' > tools/other.py \
  && printf 'python3 tools/helper.py\n' > bin/suite-runner && git add tools bin && git commit -qm "thêm helper" \
  && git push -q . helper:main 2>/dev/null; git checkout -q -b helper2 main && echo 'print(2)' > tools/helper.py && git commit -qam "PR sửa helper"
V="$(git rev-parse HEAD)"; pm T2005-helper "$V"
got="$(has_et "$V" --top "$R" --base main)"
[ "$got" = "0 pm" ] && ok "E8: PR sửa script tầng hai (.py do script suite gọi), có audit -> pm" || fail "E8: script tầng hai: '$got' (muốn '0 pm')"
git checkout -q -b other main && echo 'print(3)' > tools/other.py && git commit -qam "PR sửa .py không ai gọi"
Q="$(git rev-parse HEAD)"; pm T2006-other "$Q"
got="$(has_et "$Q" --top "$R" --base main)"
[ "$got" = "1 false" ] && ok "E10: PR sửa .py không suite nào gọi, có audit -> false (không bi quan thừa)" || fail "E10: .py thường: '$got' (muốn '1 false')"

# E9 (Grok review 04/11): ma trận chỉ có ở cây làm việc (chưa commit ở base) nhắc tools/other.py -> không tính (gate đọc ở base) -> false
git checkout -q other && printf '{"rules":[{"mandatory_regression_tests":[{"command":"python3 tools/other.py"}]}]}' > .agents/regression_matrix.active.json
got="$(has_et "$Q" --top "$R" --base main)"
[ "$got" = "1 false" ] && ok "E9: ma trận chỉ ở cây làm việc -> không tính (đọc ở base) -> false" || fail "E9: ma trận cây làm việc: '$got' (muốn '1 false')"
git checkout -q -- .agents/regression_matrix.active.json

# E11 (review vòng cuối P2-1): PR nối thêm rule ma trận gọi tools/third.py (đã có, không ai nhắc ở base) và sửa chính script đó -> pm
#     (gate tin ma trận nối thêm của PR: trust_additive_matrix)
git checkout -q main && echo 'print(4)' > tools/third.py && git add tools/third.py && git commit -qm "thêm third"
git checkout -q -b addrule main && python3 - <<'PY'
import json
p = ".agents/regression_matrix.active.json"
m = json.load(open(p))
m["rules"].append({"mandatory_regression_tests": [{"command": "python3 tools/third.py"}]})
json.dump(m, open(p, "w"))
PY
echo 'print(5)' > tools/third.py && git commit -qam "PR nối rule + sửa third.py"
A="$(git rev-parse HEAD)"; pm T2007-addrule "$A"
got="$(has_et "$A" --top "$R" --base main)"
[ "$got" = "0 pm" ] && ok "E11: PR nối rule ma trận và sửa script rule đó gọi, có audit -> pm" || fail "E11: rule nối thêm: '$got' (muốn '0 pm')"

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
