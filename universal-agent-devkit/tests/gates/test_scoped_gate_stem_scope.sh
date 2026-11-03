#!/usr/bin/env bash
# Test hồi quy (tối ưu gate 03/11): luật nhắc STEM của bin/scoped_gate.py (test chứa stem nguyên từ của file code) chỉ nối trong
# thành phần của test — như run_impacted.sh (cd vào kit, chỉ grep test kit cho file kit). Đo 03/11: test DevKit có chữ "profiles" /
# "daemon" / "panel" kéo 107 test kit cho một sửa của mcp-servers/cc-switcher-mcp/src/profiles.js (GATES 569–604 s mỗi lượt).
#   a. test kit gọi lệnh con theo stem ("agent-kit githooks install") ⇒ vẫn chọn khi scripts/githooks.sh của kit đổi;
#   b. test kit chỉ có chữ "profiles" ⇒ KHÔNG chọn khi mcp-servers/foo/src/profiles.js đổi; test của chính mcp-servers chứa chữ đó ⇒ chọn;
#   c. test kit nêu basename file của thành phần khác (node …/panel.js) ⇒ vẫn chọn (luật basename không đổi);
#   d. test ở tests/ gốc repo giữ luật stem toàn repo ("daemon" ⇒ chọn khi mcp-servers/foo/src/daemon.js đổi).
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
mkdir -p "$K/scripts" "$K/bin" "$K/tests/x" mcp-servers/foo/src mcp-servers/foo/tests tests/y
printf '#!/usr/bin/env bash\necho hooks\n' > "$K/scripts/githooks.sh"
printf '#!/usr/bin/env bash\ncase "$1" in githooks) bash "$(dirname "$0")/../scripts/$1.sh" ;; esac\n' > "$K/bin/agent-kit"
printf '#!/usr/bin/env bash\nbin/agent-kit githooks install\n' > "$K/tests/x/test_cmd.sh"
printf '#!/usr/bin/env bash\nfor p in profiles/*; do test -d "$p"; done\n' > "$K/tests/x/test_profiles_word.sh"
printf '#!/usr/bin/env bash\nnode ../mcp-servers/foo/src/panel.js --check\n' > "$K/tests/x/test_names_panel.sh"
printf 'module.exports = { list() { return []; } };\n' > mcp-servers/foo/src/profiles.js
printf 'module.exports = {};\n' > mcp-servers/foo/src/panel.js
printf 'module.exports = {};\n' > mcp-servers/foo/src/daemon.js
printf '#!/usr/bin/env bash\n# loads profiles through the package entry\nnode -e "require(\\"./src\\")"\n' > mcp-servers/foo/tests/test_foo.sh
printf '#!/usr/bin/env bash\n# start the daemon of every server\nexit 0\n' > tests/y/test_root_stem.sh
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
check "a. kit stem subcommand kept"             "$K/scripts/githooks.sh"       "$K/tests/x/test_cmd.sh"            1
check "b. kit word 'profiles' not cross-picked" mcp-servers/foo/src/profiles.js "$K/tests/x/test_profiles_word.sh"  0
check "b. same-component stem kept"             mcp-servers/foo/src/profiles.js mcp-servers/foo/tests/test_foo.sh   1
check "c. cross-component basename kept"        mcp-servers/foo/src/panel.js    "$K/tests/x/test_names_panel.sh"   1
check "d. root tests/ keep repo-wide stem"      mcp-servers/foo/src/daemon.js   tests/y/test_root_stem.sh           1
exit "$fail"
