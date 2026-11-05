#!/usr/bin/env bash
# Test hồi quy (tối ưu gate 03/11, lane 3): cạnh YẾU của bin/scoped_gate.py chỉ chọn test MỘT bước, không đi bắc cầu.
# Đo 03/11 trên 400 commit của main 14 ngày: chữ "git worktree add" trong chuỗi đầu vào của tests/gates/test_guard_shell_norm*.sh nối
# stem tới scripts/git/worktree.py rồi kéo test đó cho mọi file worktree.py nhắc tên; chú thích nhắc tên một test khác thừa hưởng cả bao đóng
# của test kia; ".gitignore" chọn 182 test (phần lớn ghi .gitignore fixture riêng) mà bỏ sót test `git check-ignore` đọc file thật.
#   a. test chỉ có chữ stem: chọn khi chính file đổi, và khi file nó import đổi; KHÔNG chọn khi file nó nhắc tên đổi;
#   b. lệnh con dispatcher `bin/agent-kit <stem>` (dispatch động): vẫn bắc cầu;
#   c. require("../src/panel") (đường dẫn không đuôi): vẫn bắc cầu;
#   d. test nhắc tên test khác trong chú thích: chọn khi test kia đổi, KHÔNG thừa hưởng bao đóng của nó;
#   e. test shell chạy test khác (`bash …/test_b.sh`, qua biến) và test .py nhắc tên test khác: vẫn bắc cầu;
#   f. .gitignore đổi: chọn test `git check-ignore`, không chọn test chỉ ghi .gitignore fixture;
#   g. build_graph không truyền _weak (khoá cache của suite_cache): đồ thị như cũ, giữ cạnh stem;
#   h. explain khớp decide;
#   i. test gọi đích như lệnh (python3 -m, từ đầu lệnh, dispatcher dạng list, heredoc, `. "$VAR"`): vẫn bắc cầu.
# Python stdlib, tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SG_DIR="$DEVKIT_DIR/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SB="$TMP/repo"
mkdir -p "$SB" && cd "$SB" || exit 2
git init -q -b main . && git config user.email t@t && git config user.name t

K=universal-agent-devkit
mkdir -p "$K/scripts/git" "$K/bin" "$K/tests/x" "$K/tests/y" app/src app/tests
printf 'import wtlib\nimport subprocess\nsubprocess.run(["bash", "helper.sh"])\n' > "$K/scripts/git/worktree.py"
printf 'def f():\n    return 1\n' > "$K/scripts/git/wtlib.py"
printf '#!/usr/bin/env bash\necho helper\n' > "$K/scripts/git/helper.sh"
printf '#!/usr/bin/env bash\nexec python3 "$(dirname "$0")/../scripts/git/$1.py" "$@"\n' > "$K/bin/agent-kit"
printf 'import subprocess\nsubprocess.run(["bash", "helper2.sh"])\n' > "$K/scripts/git/wt2.py"
printf '#!/usr/bin/env bash\necho helper2\n' > "$K/scripts/git/helper2.sh"
printf '#!/usr/bin/env bash\ncheck() { :; }\ncheck 2 git "git worktree add ../x"\n' > "$K/tests/x/test_guard_word.sh"
printf '#!/usr/bin/env bash\nbin/agent-kit wt2 add ../x\n' > "$K/tests/x/test_dispatch.sh"
printf 'module.exports = require("./fmt.js");\n' > app/src/panel.js
printf 'module.exports = {};\n' > app/src/fmt.js
printf 'const p = require("../src/panel");\n' > app/tests/panel.test.js
printf '#!/usr/bin/env bash\nbash ../scripts/tool.sh\n' > "$K/tests/y/test_b.sh"
printf '#!/usr/bin/env bash\necho tool\n' > "$K/scripts/tool.sh"
printf '#!/usr/bin/env bash\n# same case as tests/y/test_b.sh asks for\nexit 0\n' > "$K/tests/x/test_mention.sh"
printf '#!/usr/bin/env bash\nbash "$(dirname "$0")/../y/test_b.sh" || exit 1\n' > "$K/tests/x/test_runs.sh"
printf '#!/usr/bin/env bash\nB="$(dirname "$0")/../y/test_b.sh"\nbash "$B"\n' > "$K/tests/x/test_runs_var.sh"
printf 'import subprocess, os\nsubprocess.run(["bash", os.path.join(os.path.dirname(__file__), "..", "y", "test_b.sh")])\n' > "$K/tests/x/test_runs_py.py"
printf '#!/usr/bin/env bash\nROOT="$(cd "$(dirname "$0")/../../.." && pwd)"\ngit -C "$ROOT" check-ignore -q -- .claude/state.json\n' > "$K/tests/x/test_ignored.sh"
printf '#!/usr/bin/env bash\nSB2="$(mktemp -d)"\nprintf "x\\n" > "$SB2/.gitignore"\n' > "$K/tests/x/test_fixture_ignore.sh"
printf '.claude/state.json\n' > .gitignore
# i. (plan review Grok 03/11) test chạy đích như lệnh dù không nêu đường dẫn: `cd … && python3 -m gen3`, từ đầu lệnh `subtool9`,
#    dispatcher dạng list trong heredoc; test chạy test khác qua list trong heredoc hoặc `. "$VAR"`
mkdir -p app/tools app/bin
printf 'import subprocess\nsubprocess.run(["bash", "helper3.sh"])\n' > app/tools/gen3.py
printf '#!/usr/bin/env bash\necho helper3\n' > app/tools/helper3.sh
printf '#!/usr/bin/env bash\ncd ../app/tools && python3 -m gen3\n' > "$K/tests/x/test_module.sh"
printf '#!/usr/bin/env node\nrequire("child_process").execFileSync("bash", ["helper9.sh"]);\n' > app/bin/subtool9.js
printf '#!/usr/bin/env bash\necho helper9\n' > app/bin/helper9.sh
printf '#!/usr/bin/env bash\nsubtool9 --help\n' > "$K/tests/x/test_cmd_word.sh"
printf '#!/usr/bin/env bash\npython3 - <<'"'"'PY'"'"'\nimport os, subprocess\nAK = os.path.join("bin", "agent-kit")\nsubprocess.run(["bash", AK, "wt2", "add"])\nPY\n' > "$K/tests/x/test_dispatch_list.sh"
printf '#!/usr/bin/env bash\npython3 - <<'"'"'PY'"'"'\nimport subprocess\nsubprocess.run(["bash", "tests/y/test_b.sh"])\nPY\n' > "$K/tests/x/test_runs_heredoc.sh"
printf '#!/usr/bin/env bash\nLIB="$(dirname "$0")/../y/test_b.sh"\n. "$LIB"\n' > "$K/tests/x/test_sources_var.sh"
# j. (review Claude 03/11) import Python giữa dòng / import_module là chạy thật: đích chạy helper5.sh theo tên
printf 'import subprocess\ndef main():\n    subprocess.run(["bash", "helper5.sh"])\n' > app/tools/gen5.py
printf '#!/usr/bin/env bash\necho helper5\n' > app/tools/helper5.sh
printf '#!/usr/bin/env bash\npython3 -c "import sys; sys.path.insert(0, \\"app/tools\\"); import gen5; gen5.main()"\n' > "$K/tests/x/test_inline_import.sh"
printf 'import importlib, sys\nsys.path.insert(0, "app/tools")\nimportlib.import_module("gen5").main()\n' > "$K/tests/x/test_import_module.py"
# k. (review Claude 03/11) test shell chạy test khác không qua `bash <tên>` cùng dòng: vòng for, dòng nối, chạy thẳng, timeout
printf '#!/usr/bin/env bash\nfor t in test_b.sh; do\n  bash "$(dirname "$0")/../y/$t"\ndone\n' > "$K/tests/x/test_runs_for.sh"
printf '#!/usr/bin/env bash\nbash \\\n  "$(dirname "$0")/../y/test_b.sh"\n' > "$K/tests/x/test_runs_cont.sh"
printf '#!/usr/bin/env bash\n"$(dirname "$0")/../y/test_b.sh" || exit 1\n' > "$K/tests/x/test_runs_direct.sh"
printf '#!/usr/bin/env bash\ntimeout 60 "$(dirname "$0")/../y/test_b.sh"\n' > "$K/tests/x/test_runs_timeout.sh"
printf '#!/usr/bin/env bash\nok() { :; }   # tests/y/test_b.sh asks for this\nok\n' > "$K/tests/x/test_trailing_comment.sh"
git add -A && git commit -qm init

fail=0
check() { # check <label> <changed file> <test> <want 1|0>
  got="$(python3 - "$SB" "$2" "$3" "$SG_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[4])
import scoped_gate as s
res = s.no_full(s.decide(sys.argv[1], "HEAD", changed=[sys.argv[2]]), sys.argv[1])
print(1 if sys.argv[3] in res["tests"] else 0)
PY
)"
  if [ "$got" = "$4" ]; then echo "PASS $1"; else echo "FAIL $1 (selected=$got want=$4)"; fail=1; fi
}
G="$K/tests/x/test_guard_word.sh"
check "a. stem word: target itself changed"           "$K/scripts/git/worktree.py"  "$G"                         1
check "a. stem word: target's import changed"         "$K/scripts/git/wtlib.py"     "$G"                         1
check "a. stem word: file the target names, not run"  "$K/scripts/git/helper.sh"    "$G"                         0
check "b. dispatcher subcommand stays transitive"     "$K/scripts/git/helper2.sh"   "$K/tests/x/test_dispatch.sh" 1
check "c. require('../src/panel') stays transitive"   app/src/fmt.js                app/tests/panel.test.js      1
check "d. mentioned test changed"                     "$K/tests/y/test_b.sh"        "$K/tests/x/test_mention.sh" 1
check "d. mention does not inherit the other's reach" "$K/scripts/tool.sh"          "$K/tests/x/test_mention.sh" 0
check "d. the other test itself still selected"       "$K/scripts/tool.sh"          "$K/tests/y/test_b.sh"       1
check "e. shell test running the other test"          "$K/scripts/tool.sh"          "$K/tests/x/test_runs.sh"    1
check "e. shell test running it through a variable"   "$K/scripts/tool.sh"          "$K/tests/x/test_runs_var.sh" 1
check "e. python test naming the other test"          "$K/scripts/tool.sh"          "$K/tests/x/test_runs_py.py" 1
check "f. .gitignore: git check-ignore reader"        .gitignore                    "$K/tests/x/test_ignored.sh" 1
check "f. .gitignore: fixture writer not selected"    .gitignore                    "$K/tests/x/test_fixture_ignore.sh" 0
check "i. cd … && python3 -m gen3 stays transitive"   app/tools/helper3.sh          "$K/tests/x/test_module.sh"  1
check "i. command word subtool9 stays transitive"     app/bin/helper9.sh            "$K/tests/x/test_cmd_word.sh" 1
check "i. list dispatcher in heredoc transitive"      "$K/scripts/git/helper2.sh"   "$K/tests/x/test_dispatch_list.sh" 1
check "i. heredoc list running the other test"        "$K/scripts/tool.sh"          "$K/tests/x/test_runs_heredoc.sh" 1
check "i. . \"\$VAR\" sourcing the other test"          "$K/scripts/tool.sh"          "$K/tests/x/test_sources_var.sh" 1
check "j. python3 -c '…; import gen5' transitive"     app/tools/helper5.sh          "$K/tests/x/test_inline_import.sh" 1
check "j. importlib.import_module('gen5') transitive" app/tools/helper5.sh          "$K/tests/x/test_import_module.py" 1
check "k. for-loop running the other test"           "$K/scripts/tool.sh"          "$K/tests/x/test_runs_for.sh" 1
check "k. continued line running the other test"     "$K/scripts/tool.sh"          "$K/tests/x/test_runs_cont.sh" 1
check "k. running the other test directly"           "$K/scripts/tool.sh"          "$K/tests/x/test_runs_direct.sh" 1
check "k. timeout running the other test"            "$K/scripts/tool.sh"          "$K/tests/x/test_runs_timeout.sh" 1
check "k. trailing comment naming it: one step"      "$K/scripts/tool.sh"          "$K/tests/x/test_trailing_comment.sh" 0

# g. khoá cache (suite_cache gọi build_graph không có _weak) giữ cạnh stem; h. explain khớp decide
out="$(python3 - "$SB" "$SG_DIR" "$K" <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
import scoped_gate as s
P, K = sys.argv[1], sys.argv[3]
g = s.build_graph(P)
print("g", 1 if K + "/scripts/git/worktree.py" in g[K + "/tests/x/test_guard_word.sh"] else 0)
print("h1", 1 if K + "/tests/x/test_guard_word.sh" in s.explain(P, K + "/scripts/git/worktree.py")["tests"] else 0)
print("h2", 1 if K + "/tests/x/test_guard_word.sh" in s.explain(P, K + "/scripts/git/helper.sh")["tests"] else 0)
PY
)"
want="g 1
h1 1
h2 0"
if [ "$out" = "$want" ]; then echo "PASS g/h. cache graph keeps stem edge; explain matches decide"
else echo "FAIL g/h. got: $(printf '%s' "$out" | tr '\n' ' ') want: $(printf '%s' "$want" | tr '\n' ' ')"; fail=1; fi
exit "$fail"
