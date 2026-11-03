#!/usr/bin/env bash
# Test hồi quy (tối ưu gate 03/11): luật nhắc STEM của bin/scoped_gate.py (test chứa stem nguyên từ của file code, không basename) vào
# file thuộc một GÓI có manifest (package.json, pyproject.toml…) mà test ở ngoài gói chỉ nối khi test nêu đường dẫn / module của nó.
# Đo 03/11: test DevKit có chữ "profiles" / "daemon" / "panel" kéo 107 test kit cho mcp-servers/cc-switcher-mcp/src/profiles.js.
#   a. test kit gọi lệnh con theo stem ("agent-kit githooks install", kit không phải gói) ⇒ vẫn chọn;
#   b. test kit chỉ có chữ "profiles" ⇒ KHÔNG chọn khi gói mcp-servers/foo đổi src/profiles.js; test trong chính gói ⇒ chọn;
#   c. test kit nêu basename file của gói (node …/panel.js) ⇒ vẫn chọn (luật basename không đổi);
#   d. test ngoài gói require("…/src/daemon") (đường dẫn không đuôi) ⇒ vẫn chọn; chỉ chữ "daemon" ⇒ không;
#   e. review F1: require("../lib/util") từ test/, require("./index") từ test ở gốc repo, `-m tools.gen` (gói pyproject) ⇒ vẫn chọn;
#   f. file trong bin/ của gói (lệnh foo-cli) ⇒ vẫn chọn theo stem.
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
mkdir -p "$K/scripts" "$K/bin" "$K/tests/x" mcp-servers/foo/src mcp-servers/foo/bin mcp-servers/foo/tests mcp-servers/py/tools \
  tests/y test lib scripts/tests
printf '#!/usr/bin/env bash\necho hooks\n' > "$K/scripts/githooks.sh"
printf '#!/usr/bin/env bash\ncase "$1" in githooks) bash "$(dirname "$0")/../scripts/$1.sh" ;; esac\n' > "$K/bin/agent-kit"
printf '#!/usr/bin/env bash\nbin/agent-kit githooks install\n' > "$K/tests/x/test_cmd.sh"
printf '#!/usr/bin/env bash\nfor p in profiles/*; do test -d "$p"; done\n' > "$K/tests/x/test_profiles_word.sh"
printf '#!/usr/bin/env bash\nnode ../mcp-servers/foo/src/panel.js --check\n' > "$K/tests/x/test_names_panel.sh"
printf '#!/usr/bin/env bash\npython3 -m tools.gen --dry-run\n' > "$K/tests/x/test_py_module.sh"
printf '{"name": "foo", "bin": {"foo-cli": "bin/foo-cli.js"}}\n' > mcp-servers/foo/package.json
printf 'module.exports = { list() { return []; } };\n' > mcp-servers/foo/src/profiles.js
printf 'module.exports = {};\n' > mcp-servers/foo/src/panel.js
printf 'module.exports = {};\n' > mcp-servers/foo/src/daemon.js
printf '#!/usr/bin/env node\n' > mcp-servers/foo/bin/foo-cli.js
printf '#!/usr/bin/env bash\n# loads profiles through the package entry\nnode -e "require(\\"./src\\")"\n' > mcp-servers/foo/tests/test_foo.sh
printf '[project]\nname = "py"\n' > mcp-servers/py/pyproject.toml
printf 'print(1)\n' > mcp-servers/py/tools/gen.py
printf '#!/usr/bin/env bash\n# start the daemon of every server\nexit 0\n' > tests/y/test_root_word.sh
printf '#!/usr/bin/env bash\nnode -e "require(\\"../mcp-servers/foo/src/daemon\\")"\n' > tests/y/test_root_path.sh
printf '#!/usr/bin/env bash\nfoo-cli --version\n' > tests/y/test_bin_cmd.sh
printf 'module.exports = {};\n' > lib/util.js
printf 'module.exports = {};\n' > index.js
printf 'const u = require("../lib/util");\n' > test/util.test.js
printf 'const i = require("./index");\n' > app.test.js
printf 'import subprocess\nsubprocess.run(["python3", "-m", "tools.gen"])\n' > scripts/tests/test_gen.py
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
check "a. kit stem subcommand kept"              "$K/scripts/githooks.sh"         "$K/tests/x/test_cmd.sh"           1
check "b. kit word 'profiles' not cross-picked"  mcp-servers/foo/src/profiles.js  "$K/tests/x/test_profiles_word.sh" 0
check "b. same-package stem kept"                mcp-servers/foo/src/profiles.js  mcp-servers/foo/tests/test_foo.sh  1
check "c. cross-package basename kept"           mcp-servers/foo/src/panel.js     "$K/tests/x/test_names_panel.sh"  1
check "d. extensionless path require kept"       mcp-servers/foo/src/daemon.js    tests/y/test_root_path.sh          1
check "d. bare word 'daemon' not cross-picked"   mcp-servers/foo/src/daemon.js    tests/y/test_root_word.sh          0
check "e. test/ require ../lib/util kept"        lib/util.js                      test/util.test.js                  1
check "e. root-level test require ./index kept"  index.js                         app.test.js                        1
check "e. python -m tools.gen kept (pyproject)"  mcp-servers/py/tools/gen.py      "$K/tests/x/test_py_module.sh"    1
check "e. python -m tools.gen kept (root pkg)"   mcp-servers/py/tools/gen.py      scripts/tests/test_gen.py          1
check "f. package bin/ command kept"             mcp-servers/foo/bin/foo-cli.js   tests/y/test_bin_cmd.sh            1
exit "$fail"
