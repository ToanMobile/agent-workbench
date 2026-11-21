#!/usr/bin/env bash
# Test hồi quy #1416: gate_full.install_devkit ép cứng `-a claude` khi cài DevKit vào cây scratch ⇒ repo track `.agents/hooks.json`
# (agent-workbench, các repo app đồng bộ kit) thiếu `.agents/hooks/` trong scratch và `agent-health.py -t .` báo fatal
# "thiếu hoặc hỏng .agents/hooks.json" (cùng lỗi với merge gate ở #1404).
#   1. Repo track `.agents/hooks.json`: dựng scratch qua install_devkit ⇒ có `.agents/hooks/agent_bridge.sh`, agent-health XANH.
#   2. Repo chỉ dùng claude, checkout chính có `.gemini/settings.json` cục bộ bị ignore: scratch giữ đúng tập agent claude
#      (không sinh `.agents/hooks/`, không sinh `.gemini/settings.json`), agent-health XANH.
#   3. scratch_agents: thứ tự và mặc định của tập agent theo marker trong cây scratch.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export LC_ALL=C LANG=C DEVKIT_LANG=vi
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GF="$DEVKIT_DIR/bin/gate_full.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-scratch-agents.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd)"
trap 'rm -rf "$T"' EXIT
[ -f "$GF" ] || { echo "✖ thiếu bin/gate_full.py"; exit 1; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$T/xdg"

# Repo fixture đã cài DevKit; track các file cấu hình như agent-workbench (và `.agents/hooks.json` khi track_ag=1).
init_fixture() {
  local name="$1" agents="$2" track_ag="$3" r="$T/$1-repo"
  git init -q -b main "$r"
  git -C "$r" config user.email t@example.invalid
  git -C "$r" config user.name t
  git -C "$r" config commit.gpgsign false
  printf '/.claude/worktrees/\n' > "$r/.gitignore"
  echo 'VALUE = 1' > "$r/app.py"
  git -C "$r" add .gitignore app.py
  git -C "$r" commit -qm init
  bash "$DEVKIT_DIR/bin/install.sh" -t "$r" -a "$agents" -p backend -y >"$T/$name-install.log" 2>&1 || { bad "setup $name: install.sh lỗi" "$(tail -3 "$T/$name-install.log" | tr '\n' ' ')"; return 1; }
  git -C "$r" add -f .gitignore AGENTS.md DESIGN.md .agents/instincts.md .agents/active-profile.json .claude/settings.json
  [ "$track_ag" -eq 1 ] && git -C "$r" add -f .agents/hooks.json
  git -C "$r" commit -qm "devkit tracked"
}

# Dựng scratch như gate_full (worktree tách rời tại HEAD) rồi gọi đúng hàm install_devkit của gate_full.py.
build_scratch() {
  local name="$1" r="$T/$1-repo" s="$T/$1-scratch"
  git -C "$r" worktree add -q --detach "$s" HEAD || return 1
  python3 - "$GF" "$r" "$s" >"$T/$name-scratch.log" 2>&1 <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("gate_full", sys.argv[1])
gf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gf)


class FakeRun:
    def raw(self, text):
        sys.stdout.write(text)

    def log(self, msg):
        print("LOG " + msg)


gf.install_devkit(FakeRun(), sys.argv[2], sys.argv[3])
PY
}
health() { ( cd "$T/$1-scratch" && python3 .agents/devkit/bin/agent-health.py -t . ) >"$T/$1-health.log" 2>&1; }

# ── 1: repo track .agents/hooks.json
if init_fixture f1 "claude,gemini" 1 && build_scratch f1; then
  health f1; rc=$?
  if [ "$rc" -eq 0 ] && [ -f "$T/f1-scratch/.agents/hooks/agent_bridge.sh" ] && ! grep -q "thiếu hoặc hỏng" "$T/f1-health.log"; then
    ok "1. .agents/hooks.json được track ⇒ scratch có .agents/hooks/agent_bridge.sh, agent-health -t . XANH"
  else
    bad "1. scratch của repo track .agents/hooks.json" "health exit=$rc bridge=$([ -f "$T/f1-scratch/.agents/hooks/agent_bridge.sh" ] && echo có || echo thiếu): $(grep -E 'thiếu hoặc hỏng|FATAL|fatal|✖' "$T/f1-health.log" | head -3 | tr '\n' ' ')"
  fi
  if [ -z "$(git -C "$T/f1-scratch" status --porcelain --untracked-files=no)" ]; then
    ok "1b. file đã track trong scratch giữ nguyên như commit sau khi cài"
  else
    bad "1b. cài DevKit làm bẩn file đã track của scratch" "$(git -C "$T/f1-scratch" status --porcelain --untracked-files=no | head -3 | tr '\n' ' ')"
  fi
else
  bad "1. không dựng được fixture/scratch f1" "$(tail -3 "$T/f1-scratch.log" 2>/dev/null | tr '\n' ' ')"
fi

# ── 2: repo chỉ dùng claude; checkout chính có .gemini/settings.json cục bộ bị ignore
if init_fixture f2 "claude" 0; then
  mkdir -p "$T/f2-repo/.gemini"
  echo '{"local": true}' > "$T/f2-repo/.gemini/settings.json"
  mkdir -p "$T/f2-repo/.git/info"; printf '/.gemini/\n' >> "$T/f2-repo/.git/info/exclude"
  if build_scratch f2; then
    health f2; rc=$?
    if [ "$rc" -eq 0 ] && [ ! -e "$T/f2-scratch/.agents/hooks" ] && [ ! -e "$T/f2-scratch/.gemini/settings.json" ] \
       && [ -f "$T/f2-scratch/.claude/settings.json" ]; then
      ok "2. repo chỉ dùng claude (main có .gemini/settings.json bị ignore) ⇒ scratch giữ tập agent claude, agent-health -t . XANH"
    else
      bad "2. repo chỉ dùng claude" "health exit=$rc hooks=$([ -e "$T/f2-scratch/.agents/hooks" ] && echo có || echo không) gemini=$([ -e "$T/f2-scratch/.gemini/settings.json" ] && echo có || echo không): $(tail -3 "$T/f2-health.log" | tr '\n' ' ')"
    fi
  else
    bad "2. không dựng được scratch f2" "$(tail -3 "$T/f2-scratch.log" | tr '\n' ' ')"
  fi
else
  bad "2. không dựng được fixture f2"
fi

# ── 3: scratch_agents theo marker của cây scratch
out=$(python3 - "$GF" "$T/markers" <<'PY' 2>&1
import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location("gate_full", sys.argv[1])
gf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gf)
root = sys.argv[2]


def tree(name, *markers):
    d = os.path.join(root, name)
    for m in markers:
        os.makedirs(os.path.dirname(os.path.join(d, m)), exist_ok=True)
        open(os.path.join(d, m), "w").close()
    os.makedirs(d, exist_ok=True)
    return d


print(gf.scratch_agents(tree("empty")))
print(gf.scratch_agents(tree("ag", ".agents/hooks.json")))
print(gf.scratch_agents(tree("all", ".agents/hooks.json", ".cursor/hooks.json", ".gemini/settings.json", ".codex/hooks.json",
                             ".claude/settings.json")))
PY
)
want="claude
claude,antigravity
claude,codex,gemini,cursor,antigravity"
if [ "$out" = "$want" ]; then
  ok "3. scratch_agents: mặc định claude; thêm agent theo marker, đúng thứ tự claude,codex,gemini,cursor,antigravity"
else
  bad "3. scratch_agents" "$(printf '%s' "$out" | tr '\n' '|')"
fi

echo
[ "$fails" -eq 0 ] && { echo "test_gate_full_scratch_agents: PASS"; exit 0; } || { echo "test_gate_full_scratch_agents: FAIL ($fails)"; exit 1; }
