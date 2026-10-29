#!/usr/bin/env bash
# Test hồi quy (#644, review OCR): lượt `post-fix-gate.py --scoped` chạy test của diff ĐÚNG đường, không đỏ oan / xanh giả.
#   a. scoped_suites: chỉ tests/<thư mục>/test_*.sh và hooks/tests/*.sh của kit đi qua runner run_impacted.sh (chạy bằng bash); *.test.mjs,
#      test_*.py của kit đi như test ngoài kit;
#   b. test có luật ma trận CỤ THỂ phủ (không bắt-tất-cả) ⇒ suite của luật đó (lệnh ma trận, đúng môi trường: `cd pkg && uv run …`), không lệnh
#      trần `python3 -m pytest` / `node --test`; một suite một lần; suite đã chọn không thêm lại;
#   c. .sh không luật nào phủ ⇒ lệnh trần `bash` trong SCOPED-EXTRA;
#   d. .py / .mjs chỉ luật bắt-tất-cả (hay chỉ luật runner kit) phủ ⇒ lý do leo full (fail closed, không xanh giả qua runner);
#   e. biên nhận scoped_pass.json ghi `base` là sha commit (push_gate đòi sha hex), kể cả khi base_ref là "HEAD" (không --diff, cây bẩn).
# Python stdlib, tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_SLOT_PRIORITY

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"   # khoá slot riêng (không đụng gate thật của máy)
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# ── a–d. scoped_suites (hàm thuần): in từng dòng "nhãn|kết quả" rồi so
OUT="$(python3 - "$GATE" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pfg_routing", sys.argv[1]); m = importlib.util.module_from_spec(spec)
sys.modules["pfg_routing"] = m; spec.loader.exec_module(m)
K = "universal-agent-devkit/"
RUN = "bash universal-agent-devkit/tests/run_impacted.sh"
rules = [
    {"component": "devkit-all", "watch_files": [K + "*"], "mandatory_regression_tests": [{"id": "REG-DK", "command": RUN}]},
    {"component": "pkg", "watch_files": ["pkg/*.py"],
     "mandatory_regression_tests": [{"id": "REG-PKG", "command": "cd pkg && uv run --frozen --extra dev pytest -q"}]},
    {"component": "kit-wf", "watch_files": [K + "workflows/*.mjs"],
     "mandatory_regression_tests": [{"id": "REG-WF", "command": "cd universal-agent-devkit/workflows && node --test"}]},
    {"component": "other-all", "watch_files": ["other/*"], "mandatory_regression_tests": [{"id": "REG-OTHER", "command": "true"}]},
    # luật cụ thể mà lệnh là runner kit: runner chỉ chạy DEVKIT_SCOPED_TESTS ⇒ không được dùng nó cho test ngoài runner
    {"component": "kit-skills", "watch_files": [K + "skills/*.py"], "mandatory_regression_tests": [{"id": "REG-RUN2", "command": RUN}]},
]
def run(label, tests, selected=()):
    added, kit, why = m.scoped_suites({"tests": tests, "smoke": []}, rules, list(selected))
    ids = [t.get("id") for _, t in added]
    extra = [t.get("command") for _, t in added if t.get("id") == "SCOPED-EXTRA"]
    print(f"{label}|kit={','.join(kit)}|ids={','.join(ids)}|extra={extra[0] if extra else ''}|why={'yes' if why else 'no'}")
run("A", [K + "tests/gates/test_x.sh", K + "hooks/tests/test_h.sh", K + "workflows/a.test.mjs",
          "pkg/tests/test_p.py", "pkg/tests/test_q.py", "scripts/test_s.sh"])
run("B", ["other/test_o.py"])
run("C", [K + "skills/ui/scripts/tests/test_u.py"])
run("D", [K + "tests/verification/test_proof_run_before.py"])
run("E", ["pkg/tests/test_p.py"], selected=[{"id": "REG-PKG", "command": "cd pkg && uv run --frozen --extra dev pytest -q"}])
run("F", ["other/test_o.sh"])
PY
)"
line() { printf '%s\n' "$OUT" | grep "^$1|"; }
A="$(line A)"
case "$A" in "A|kit=tests/gates/test_x.sh,hooks/tests/test_h.sh|"*) ok "a. chỉ tests/<dir>/test_*.sh + hooks/tests/*.sh của kit qua runner" ;;
  *) fail "a. test kit qua runner sai: $A" ;; esac
ids="$(printf '%s' "$A" | sed -n 's/.*|ids=\([^|]*\)|.*/\1/p')"
[ "$(printf '%s' "$ids" | tr ',' '\n' | grep -c '^REG-PKG$')" = 1 ] && printf '%s' "$ids" | grep -q REG-WF && printf '%s' "$ids" | grep -q REG-DK \
  && ok "b. test có luật cụ thể ⇒ suite của luật (REG-PKG một lần, REG-WF), runner REG-DK thêm" || fail "b. suite thêm sai: $A"
case "$A" in *"pytest -q "*|*"node --test "*) fail "b. còn lệnh trần pytest / node --test: $A" ;;
  *"extra=rc=0; bash 'scripts/test_s.sh' || rc=1; exit \$rc|"*|*"extra=rc=0; bash scripts/test_s.sh || rc=1; exit \$rc|"*) ok "c. .sh không luật phủ ⇒ bash trần trong SCOPED-EXTRA" ;;
  *) fail "c. SCOPED-EXTRA sai: $A" ;; esac
case "$A" in *"|why=no") ok "a–c. không leo full" ;; *) fail "a–c. leo full oan: $A" ;; esac
case "$(line B)" in *"|why=yes") ok "d. .py chỉ luật bắt-tất-cả phủ ⇒ leo full" ;; *) fail "d. .py không luật cụ thể mà không leo full: $(line B)" ;; esac
case "$(line C)" in *"|why=yes") ok "d. .py chỉ luật runner kit phủ ⇒ leo full (không xanh giả qua runner)" ;; *) fail "d. luật runner kit nhận test .py: $(line C)" ;; esac
case "$(line D)" in *"kit=|"*"|why=yes") ok "d. test_*.py dưới tests/ của kit không qua runner bash, leo full" ;; *) fail "d. test .py của kit: $(line D)" ;; esac
case "$(line E)" in "E|kit=|ids=|extra=|why=no") ok "b. suite của luật đã được chọn: không thêm lại" ;; *) fail "b. suite đã chọn bị thêm lại: $(line E)" ;; esac
case "$(line F)" in *"bash"*"other/test_o.sh"*"|why=no") ok "c. .sh chỉ luật bắt-tất-cả phủ ⇒ bash trần" ;; *) fail "c. .sh ngoài luật: $(line F)" ;; esac
[ -n "$A" ] || { printf '%s\n' "$OUT" | tail -15; }

# ── e. biên nhận scoped: base là sha commit, kể cả khi base_ref là "HEAD"
R="$TMP/repo"
mkdir -p "$R/src" "$R/tests" && cd "$R" || exit 2
git init -q -b main . && git config user.email t@t && git config user.name t
echo 'a = 1' > src/a.py
printf '#!/usr/bin/env bash\ngrep -q = src/a.py\n' > tests/test_a.sh
printf 'from src import a\n\ndef test_a():\n    assert a\n' > tests/test_a.py
printf 'O = 1\n' > src/old.py   # h: đổi tên file code mà test còn gọi tên cũ
printf '#!/usr/bin/env bash\npython3 src/old.py\n' > tests/test_old.sh
printf '.claude/\n' > .gitignore
# REG-A có impacted_command (f): lượt scoped phải chạy lệnh ĐẦY ĐỦ của suite đã chọn, không chế độ impacted
cat > matrix.json <<JSON
{"project": "t", "rules": [{"component": "A", "watch_files": ["src/a.py", "tests/test_a.py"],
  "mandatory_regression_tests": [{"id": "REG-A", "name": "a", "command": "echo full >> '$TMP/mode.A'; bash tests/test_a.sh",
                                  "impacted_command": "echo impacted >> '$TMP/mode.A'; true {pytest_nodes}"}]},
  {"component": "O", "watch_files": ["src/old.py", "src/new.py"],
   "mandatory_regression_tests": [{"id": "REG-O", "name": "o", "command": "bash tests/test_old.sh"}]}]}
JSON
git add -A && git commit -qm init   # ở nhánh đích: lượt task không tự đổi base sang merge-base(main, HEAD)
echo 'a = 2' > src/a.py   # cây bẩn, không --diff ⇒ base_ref "HEAD"
GOUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --scoped --no-checklist 2>&1)"; RC=$?
SP="$(git rev-parse --absolute-git-dir)/postfix-gate/scoped_pass.json"
base="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("base", "NO-BASE"))' "$SP" 2>/dev/null || echo NO-RECEIPT)"
if printf '%s\n' "$GOUT" | grep -q -- "--scoped → full"; then fail "e. tiền đề: --scoped leo full: $(printf '%s\n' "$GOUT" | grep -- '--scoped → full' | head -1)"
elif [ "$RC" = 0 ] && [ "$base" = "$(git rev-parse HEAD)" ]; then ok "e. base_ref HEAD ⇒ biên nhận scoped ghi base = sha HEAD"
else fail "e. exit $RC, base trong biên nhận = $base (mong $(git rev-parse HEAD))"; printf '%s\n' "$GOUT" | tail -12; fi
# f. suite có impacted_command: --scoped chạy lệnh đầy đủ (chế độ impacted/resource/package/module không vào biên nhận scoped)
[ "$(cat "$TMP/mode.A" 2>/dev/null)" = full ] && ok "f. --scoped chạy lệnh đầy đủ của suite có impacted_command" \
  || fail "f. --scoped chạy REG-A ở chế độ: $(tr '\n' ' ' < "$TMP/mode.A" 2>/dev/null) (mong full)"
# f0. đối chứng: lượt task không --scoped vẫn chọn impacted (chế độ impacted có thật trong harness này)
: > "$TMP/mode.A"
CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --no-checklist >/dev/null 2>&1
[ "$(cat "$TMP/mode.A" 2>/dev/null)" = impacted ] && ok "f0. đối chứng: lượt không --scoped chạy REG-A impacted" \
  || fail "f0. đối chứng: lượt không --scoped chạy REG-A ở chế độ: $(tr '\n' ' ' < "$TMP/mode.A" 2>/dev/null) (mong impacted)"

# g. lượt sau trên CÙNG cây exit ≠ 0 (không BUSY / BUDGET / SLOT) bỏ biên nhận scoped của cây đó: test mới không suite nào chạy
#    (orphan) — lượt đầu --allow-orphan-tests PASS ghi biên nhận, lượt sau không cờ đó exit 2
scoped() { GOUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --run-tests --scoped --no-checklist "$@" 2>&1)"; RC=$?; }
printf '#!/usr/bin/env bash\ngrep -q = src/a.py\n' > tests/test_new.sh
rm -f "$SP"; scoped --allow-orphan-tests; r1=$RC; [ -f "$SP" ] && had=yes || had=no
scoped; r2=$RC
if [ "$r1" = 0 ] && [ "$had" = yes ] && [ "$r2" = 2 ] && [ ! -e "$SP" ]; then ok "g. cùng cây: lượt sau exit 2 bỏ scoped_pass.json"
else fail "g. exit $r1 rồi $r2 (mong 0 rồi 2), biên nhận sau lượt đầu: $had, còn sau lượt exit 2: $([ -e "$SP" ] && echo có || echo không)"
  printf '%s\n' "$GOUT" | grep -E "CHƯA|UNVERIFIED|scoped|orphan" | tail -5; fi
rm -f tests/test_new.sh; git checkout -q -- src/a.py

# h. đổi tên file code (git mv) mà test còn gọi tên cũ: nguồn rename là file code bị xoá ⇒ --scoped leo full
git mv src/old.py src/new.py
scoped
if printf '%s\n' "$GOUT" | grep -q -- "--scoped → full"; then ok "h. git mv file code ⇒ --scoped leo full (nguồn rename vào decide như file bị xoá)"
else fail "h. git mv src/old.py → src/new.py mà --scoped không leo full (exit $RC)"; printf '%s\n' "$GOUT" | grep -E "scoped|REG-" | tail -5; fi
git mv src/new.py src/old.py

# i. super-board-verify-flags.sh (cùng repo workbench, ngoài kit; kit tách riêng thì bỏ qua): --full / --force-full / --scoped là TOKEN
#    nguyên, `--full-name` không phải ý full ⇒ vẫn chèn --scoped
VF="$DEVKIT_DIR/../.claude/bin/super-board-verify-flags.sh"
if [ -f "$VF" ]; then
  vf() { bash -c '. "$1"; sb_verify_inject_flags "$2" main' _ "$VF" "$1"; }
  case "$(vf 'python3 bin/post-fix-gate.py --run-tests --full-name x')" in *" --scoped"*) ok "i. --full-name không chặn chèn --scoped" ;;
    *) fail "i. --full-name bị coi như --full: $(vf 'python3 bin/post-fix-gate.py --run-tests --full-name x')" ;; esac
  case "$(vf 'python3 bin/post-fix-gate.py --run-tests --full')" in *"--scoped"*) fail "i. --full mà vẫn chèn --scoped" ;; *) ok "i. --full (token) giữ ý full" ;; esac
  case "$(vf 'python3 bin/post-fix-gate.py --run-tests --force-full --brief')" in *"--scoped"*) fail "i. --force-full mà vẫn chèn --scoped" ;; *) ok "i. --force-full (token) giữ ý full" ;; esac
  [ "$(vf 'python3 bin/post-fix-gate.py --scoped --run-tests' | grep -o -- '--scoped' | wc -l | tr -d ' ')" = 1 ] \
    && ok "i. --scoped có sẵn: không chèn lần nữa" || fail "i. --scoped chèn trùng"
fi
# j. board mới (super-board-setup.py migrate_config): verify không ép --full (verify-flags chèn --scoped; --full đêm thuộc gate-full)
SS="$DEVKIT_DIR/../.claude/bin/super-board-setup.py"
if [ -f "$SS" ]; then
  v="$(python3 - "$SS" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sb_setup", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.migrate_config({})[0].get("verify_commands"))
PY
)"
  case "$v" in *"post-fix-gate.py --run-tests --brief"*) ok "j. board mới: verify_commands không có --full" ;; *) fail "j. board mới: verify_commands = $v" ;; esac
fi

echo
[ "$FAILS" = 0 ] && { echo "PASS: test_gate_scoped_routing"; exit 0; }
echo "FAIL: test_gate_scoped_routing ($FAILS)"; exit 1
