#!/usr/bin/env bash
# 17/11 chủ repo gỡ Grok khỏi DevKit: install.sh không còn agent `grok`/`xai` (help, menu, `all`).
# Đường "chỉ AGENTS.md" (repo chỉ có AGENTS.md, không thư mục riêng của công cụ nào) trước mượn tên grok, nay là `agents-md`:
# re-init vẫn giữ đúng đường đó, không nở ra mọi công cụ.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P="$(mktemp -d -t devkit-agentsmd-XXXXXX)"
trap 'rm -rf "$P"' EXIT
FAILS=0
# "grok" như một từ riêng; đường dẫn chứa nó (vd worktree grok-cleanup/) không tính
has_grok() { grep -qiE '(^|[^a-z/-])grok([^a-z/-]|$)'; }
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

HELP="$(bash "$DEVKIT_ROOT/bin/install.sh" --help 2>&1)"
printf '%s' "$HELP" | has_grok && fail "help còn nhắc Grok" || ok "help không còn Grok"
printf '%s' "$HELP" | grep -q 'agents-md' && ok "help có agents-md" || fail "help thiếu agents-md"

git -C "$P" init -q .
OUT="$(bash "$DEVKIT_ROOT/bin/install.sh" -t "$P" -y -p backend -a grok -m symlink 2>&1 < /dev/null)"
printf '%s' "$OUT" | grep -q 'Unknown agent: grok' && ok "-a grok là agent lạ" || fail "-a grok vẫn được nhận: $(printf '%s' "$OUT" | grep -i grok | head -2)"

rm -rf "$P"; mkdir -p "$P"; git -C "$P" init -q .
bash "$DEVKIT_ROOT/bin/install.sh" -t "$P" -y -p backend -a agents-md -m symlink >/dev/null 2>&1 < /dev/null || fail "cài -a agents-md thoát khác 0"
grep -q "universal-agent-devkit" "$P/AGENTS.md" 2>/dev/null && ok "-a agents-md ghi AGENTS.md" || fail "-a agents-md không ghi AGENTS.md"
[ ! -e "$P/.codex" ] && [ ! -e "$P/.cursor" ] && [ ! -e "$P/.gemini" ] && ok "-a agents-md không thêm thư mục công cụ" || fail "-a agents-md thêm thư mục công cụ"

REINIT_OUT="$(python3 - "$DEVKIT_ROOT" "$P" <<'PY'
import subprocess, sys
root, proj = sys.argv[1:3]
r = subprocess.run(["bash", f"{root}/bin/install.sh", f"--target={proj}", "--domain=auto", "--mode=symlink"],
                   stdin=subprocess.DEVNULL, capture_output=True, text=True, start_new_session=True)
print(r.stdout)
print(f"REINIT_RC={r.returncode}")
PY
)"
printf '%s' "$REINIT_OUT" | grep -q "REINIT_RC=0" && ok "re-init thoát 0" || fail "re-init lỗi: $(printf '%s' "$REINIT_OUT" | tail -3)"
printf '%s' "$REINIT_OUT" | grep -q "keeping the agents already set up: agents-md" && ok "re-init giữ đường agents-md" \
  || fail "re-init không giữ agents-md: $(printf '%s' "$REINIT_OUT" | grep -i 'keeping\|grok' | head -2)"
printf '%s' "$REINIT_OUT" | has_grok && fail "re-init còn in Grok: $(printf '%s' "$REINIT_OUT" | grep -i grok | head -3)" || ok "re-init không in Grok"
[ ! -e "$P/.codex" ] && [ ! -e "$P/.cursor" ] && ok "re-init không nở ra mọi công cụ" || fail "re-init thêm .codex/.cursor"

if [ $FAILS -gt 0 ]; then echo "FAILED: $FAILS errors"; exit 1; fi
echo "ALL TESTS PASSED"
