#!/usr/bin/env bash
# Test hồi quy (#644, review OCR): lượt `post-fix-gate.py --scoped` chạy test của diff ĐÚNG đường, không đỏ oan / xanh giả.
#   a. scoped_suites: chỉ tests/<thư mục>/test_*.sh và hooks/tests/*.sh của kit đi qua runner run_impacted.sh (chạy bằng bash); *.test.mjs,
#      test_*.py của kit đi như test ngoài kit;
#   b. test có luật ma trận CỤ THỂ phủ (không bắt-tất-cả) ⇒ suite của luật đó (lệnh ma trận, đúng môi trường: `cd pkg && uv run …`), không lệnh
#      trần `python3 -m pytest` / `node --test`; một suite một lần; suite đã chọn không thêm lại;
#   c. .sh không luật nào phủ ⇒ lệnh trần `bash` trong SCOPED-EXTRA;
#   d. .py / .mjs chỉ luật bắt-tất-cả (hay chỉ luật runner kit) phủ ⇒ lý do leo full (fail closed, không xanh giả qua runner);
#   e. biên nhận scoped_pass.json ghi `base` là sha commit (push_gate đòi sha hex), kể cả khi base_ref là "HEAD" (không --diff, cây bẩn);
#   k. runner là lệnh run_impacted.sh KHÔNG tiền tố DEVKIT_IMPACTED_DIRS=; chỉ còn shard ⇒ thêm mọi shard (không lọc mất test ngoài shard đầu);
#   l. DEVKIT_SCOPED_TESTS chỉ tới suite runner kit: suite khác thấy `unset`;
#   m. cây có lượt --full đỏ (runs.jsonl, cùng fp, sau lượt full xanh gần nhất) ⇒ lượt --scoped xanh không ghi biên nhận scoped.
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
# k. ma trận chỉ còn shard (REG-DK-ALL-01 bỏ, #616): runner không được là shard đầu (lọc mất test ngoài thư mục gates mà vẫn PASS)
SH = [("REG-G", "gates"), ("REG-W", "worktree_git"), ("REG-R", "!gates,!worktree_git")]
shards = [{"component": "dk-" + i, "watch_files": [K + "x/" + i],
           "mandatory_regression_tests": [{"id": i, "command": "DEVKIT_IMPACTED_DIRS=%s %s" % (d, RUN)}]} for i, d in SH]
def run2(label, rs, tests, selected=()):
    added, kit, why = m.scoped_suites({"tests": tests, "smoke": []}, rs, list(selected))
    print(f"{label}|kit={','.join(kit)}|ids={','.join(t.get('id') for _, t in added)}|why={'yes' if why else 'no'}")
run2("K1", shards, [K + "tests/verification/test_v.sh"])
run2("K2", shards + [{"component": "dk-all", "watch_files": [K + "*"], "mandatory_regression_tests": [{"id": "REG-ALL", "command": RUN}]}],
     [K + "tests/verification/test_v.sh"])
run2("K3", shards, [K + "tests/worktree_git/test_w.sh"], selected=[{"id": "REG-G", "command": "x"}])
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
case "$(line K1)" in "K1|kit=tests/verification/test_v.sh|ids=REG-G,REG-W,REG-R|why=no") ok "k. chỉ còn shard ⇒ thêm MỌI shard (test ở tests/verification chạy qua shard REST)" ;;
  *) fail "k. chỉ còn shard: $(line K1) (mong ids=REG-G,REG-W,REG-R)" ;; esac
case "$(line K2)" in "K2|kit=tests/verification/test_v.sh|ids=REG-ALL|why=no") ok "k. có runner không tiền tố (đứng sau các shard) ⇒ chỉ nó" ;;
  *) fail "k. runner không tiền tố không được ưu tiên: $(line K2)" ;; esac
case "$(line K3)" in "K3|kit=tests/worktree_git/test_w.sh|ids=REG-W,REG-R|why=no") ok "k. shard đã chọn không thêm lại, thêm các shard còn lại" ;;
  *) fail "k. shard đã chọn: $(line K3) (mong ids=REG-W,REG-R)" ;; esac
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

# h. đổi tên file code (git mv) mà test còn gọi tên cũ: nguồn rename là file code bị xoá với decide. #741: --scoped không leo full nữa —
#    lý do cũ "file code bị xoá" vẫn được nêu (would_full), lượt chạy scoped
git mv src/old.py src/new.py
scoped
HMODE="$(tail -1 "$(git rev-parse --absolute-git-dir)/postfix-gate/runs.jsonl" 2>/dev/null | python3 -c 'import json,sys; print(json.loads(sys.stdin.read() or "{}").get("mode"))' 2>/dev/null)"
if ! printf '%s\n' "$GOUT" | grep -q -- "--scoped → full" && printf '%s\n' "$GOUT" | grep -q "không leo full; trước đây: .*file code bị xoá ⇒ full: src/old.py" \
   && [ "$HMODE" = scoped ]; then ok "h. git mv file code ⇒ nguồn rename vào decide như file bị xoá; --scoped nêu lý do cũ, không leo full (#741)"
else fail "h. git mv src/old.py → src/new.py: exit $RC, mode $HMODE (mong scoped, nêu 'file code bị xoá' trong would_full)"; printf '%s\n' "$GOUT" | grep -E "scoped|REG-" | tail -5; fi
git mv src/new.py src/old.py

# m. xanh scoped không đè full đỏ: runs.jsonl có lượt --full exit 1 trên cùng fp (sau lượt full xanh gần nhất) ⇒ không ghi biên nhận scoped
RL="$(git rev-parse --absolute-git-dir)/postfix-gate/runs.jsonl"
echo 'a = 3' > src/a.py
rm -f "$SP"; scoped --no-cache; m0=$RC; [ -f "$SP" ] && m0r=yes || m0r=no
FP="$(tail -1 "$RL" 2>/dev/null | python3 -c 'import json,sys; r=json.loads(sys.stdin.read()); print(r.get("fp","") if r.get("mode")=="scoped" else "")' 2>/dev/null)"
logline() { printf '{"v": 1, "epoch": %s, "mode": "full", "exit": %s, "verdict": "%s", "fp": "%s"}\n' "$(date +%s)" "$1" "$2" "$FP" >> "$RL"; }
if [ "$m0" != 0 ] || [ "$m0r" != yes ] || [ -z "$FP" ]; then fail "m. tiền đề: lượt scoped đầu exit $m0, biên nhận $m0r, fp '$FP'"
else
  logline 1 FAIL
  rm -f "$SP"; scoped --no-cache; m1=$RC; [ -f "$SP" ] && m1r=yes || m1r=no
  if [ "$m1" = 0 ] && [ "$m1r" = no ] && printf '%s\n' "$GOUT" | grep -qE -- "--full đỏ|red --full"; then ok "m. cây có lượt --full đỏ ⇒ scoped xanh không ghi biên nhận, nói lý do"
  else fail "m. sau dòng full exit 1 cùng fp: exit $m1, biên nhận scoped: $m1r (mong không)"; printf '%s\n' "$GOUT" | grep -E "scoped|full" | tail -4; fi
  logline 0 PASS
  rm -f "$SP"; scoped --no-cache; [ -f "$SP" ] && ok "m. đối chứng: lượt --full xanh sau đó (cùng fp) ⇒ scoped lại ghi biên nhận" \
    || fail "m. đối chứng: full xanh sau full đỏ mà scoped vẫn không ghi biên nhận (exit $RC)"
fi
git checkout -q -- src/a.py

# l. DEVKIT_SCOPED_TESTS chỉ tới suite runner kit (run_impacted.sh): suite khác (REG-S) không thấy nó
R2="$TMP/repo2"
mkdir -p "$R2/src" "$R2/kit/tests/x" "$R2/tools" && cd "$R2" || exit 2
git init -q -b main . && git config user.email t@t && git config user.name t
echo 'K = 1' > src/k.py
printf '#!/usr/bin/env bash\npython3 src/k.py\n' > kit/tests/x/test_k.sh
printf '#!/usr/bin/env bash\nprintf %%s "${DEVKIT_SCOPED_TESTS-unset}" > "%s/env.KIT"\necho ok\n' "$TMP" > kit/tests/run_impacted.sh
printf '#!/usr/bin/env bash\nprintf %%s "${DEVKIT_SCOPED_TESTS-unset}" > "%s/env.S"\n' "$TMP" > tools/env_s.sh
printf '.claude/\n' > .gitignore
cat > matrix.json <<'JSON'
{"project": "t2", "rules": [
  {"component": "S", "watch_files": ["src/k.py"], "mandatory_regression_tests": [{"id": "REG-S", "name": "s", "command": "bash tools/env_s.sh"}]},
  {"component": "KIT", "watch_files": ["kit/*"], "mandatory_regression_tests": [{"id": "REG-KIT", "name": "kit", "command": "bash kit/tests/run_impacted.sh"}]}]}
JSON
git add -A && git commit -qm init
echo 'K = 2' > src/k.py
GOUT="$(CLAUDE_PROJECT_DIR="$R2" python3 "$GATE" --matrix "$R2/matrix.json" --run-tests --scoped --no-checklist --no-cache 2>&1)"; RC=$?
envS="$(cat "$TMP/env.S" 2>/dev/null || echo NOT-RUN)"; envK="$(cat "$TMP/env.KIT" 2>/dev/null || echo NOT-RUN)"
if printf '%s\n' "$GOUT" | grep -q -- "--scoped → full"; then fail "l. tiền đề: --scoped leo full: $(printf '%s\n' "$GOUT" | grep -- '--scoped → full' | head -1)"
else
  [ "$envS" = unset ] && ok "l. suite không phải runner kit: DEVKIT_SCOPED_TESTS unset" || fail "l. suite REG-S thấy DEVKIT_SCOPED_TESTS='$envS' (mong unset)"
  [ "$envK" = tests/x/test_k.sh ] && ok "l. suite runner kit nhận danh sách scoped" || fail "l. runner REG-KIT nhận '$envK' (mong tests/x/test_k.sh)"
fi
cd "$R" || exit 2

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

# m2 (OCR vòng 4). Lượt task trên nhánh ngoài nhánh đích ghi biên nhận task. Cây đã có lượt --full đỏ (runs.jsonl, cùng fp) thì lượt
#    --scoped xanh không được ghi biên nhận task: đó là XONG trên một cây đã biết là đỏ. Repo nháp riêng có origin, nhánh feat.
M2="$TMP/m2"; mkdir -p "$M2/src" "$M2/tests" && git init -q --bare "$TMP/m2-origin.git" && (
  cd "$M2" && git init -q -b main && git config user.email t@t && git config user.name t && git remote add origin "$TMP/m2-origin.git"
  printf 'X = 1\n' > src/x.py; printf '#!/usr/bin/env bash\ngrep -q X src/x.py\n' > tests/test_x.sh; printf '.claude/\n' > .gitignore
  printf '{"project": "m2", "rules": [{"component": "X", "watch_files": ["src/x.py", "tests/test_x.sh"], "mandatory_regression_tests": [{"id": "REG-X", "name": "x", "command": "bash tests/test_x.sh"}]}]}\n' > matrix.json
  git add -A && git commit -qm init && git push -q origin main && git checkout -q -b feat
  printf 'X = 2\n' > src/x.py && git commit -qam "edit x" ) >/dev/null 2>&1
m2run() { (cd "$M2" && CLAUDE_PROJECT_DIR="$M2" python3 "$GATE" --matrix "$M2/matrix.json" --run-tests --scoped --no-checklist --no-cache >/dev/null 2>&1); }
M2TR="$(cd "$M2" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/postfix-gate"
m2run; M2FP="$(tail -1 "$M2TR/runs.jsonl" 2>/dev/null | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("fp",""))' 2>/dev/null)"
if [ -z "$M2FP" ] || [ ! -f "$M2TR/task_receipts/$M2FP.json" ]; then fail "m2. tiền đề: lượt --scoped trên nhánh feat không ghi biên nhận task (fp '$M2FP')"
else
  printf '{"v": 1, "epoch": %s, "mode": "full", "exit": 1, "verdict": "FAIL", "fp": "%s"}\n' "$(date +%s)" "$M2FP" >> "$M2TR/runs.jsonl"
  rm -f "$M2TR/task_receipts/$M2FP.json"; m2run
  [ -f "$M2TR/task_receipts/$M2FP.json" ] && fail "m2. cây có lượt --full đỏ mà lượt scoped xanh vẫn ghi biên nhận task" \
    || ok "m2. cây có lượt --full đỏ ⇒ lượt scoped xanh không ghi biên nhận task"
fi

echo
[ "$FAILS" = 0 ] && { echo "PASS: test_gate_scoped_routing"; exit 0; }
echo "FAIL: test_gate_scoped_routing ($FAILS)"; exit 1
