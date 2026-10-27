#!/usr/bin/env bash
# Test hồi quy (#461): hooks/session_context.sh sinh lại .agents/instincts-index.md (file đang track) ngay trong main checkout ở trunk mode
# mỗi khi instincts.md mới hơn → main bẩn mà không phiên nào sửa, điều kiện "git status sạch" của super-board run không đạt.
# Nay: main trunk mode không ghi index (chỉ cảnh báo index cũ, vẫn in dòng "Bài học của dự án"); worktree liên kết vẫn sinh lại như cũ;
# `agent-kit learn` ghi instincts.md và index khớp nhau trong cùng một lần để chúng vào cùng một commit.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="${SCG_KIT:-$(cd "$(dirname "$0")/../.." && pwd)}"   # SCG_KIT: cùng bộ ca trên một bản kit khác (RED trên bản gốc)
HOOK="$DEVKIT_DIR/hooks/session_context.sh"
KIT="$DEVKIT_DIR/bin/agent-kit"
INDEXER="$DEVKIT_DIR/scripts/governance/index_memory.py"
TMP="$(mktemp -d)"; TMPR="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en WORKTREE_GC=0
unset TARGET_DIR WORKTREE_TRUNK_MODE
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
ctx() { printf '{"session_id":"t461","hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>/dev/null; }

# repo tracking a >20 KB instincts.md and its index (stale afterwards: instincts.md touched newer)
R="$TMPR/proj"; mkdir -p "$R/.agents" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t
python3 - <<'PY'
body = "# Instincts\n\n"
for i in range(1, 41):
    body += f"---\n\n### [INSTINCT-{i:03d}] Trap number {i}\n\n" + ("filler line to make the file big enough for the index path.\n" * 12) + "\n"
open(".agents/instincts.md", "w").write(body)
PY
python3 "$INDEXER" .agents/instincts.md >/dev/null
git add -A && git commit -qm init
sleep 1; printf '\n---\n\n### [INSTINCT-041] Committed after the index\n' >> .agents/instincts.md   # instincts.md moves on, the tracked index lags
git add .agents/instincts.md && git commit -qm "lesson 41"
sleep 1; touch .agents/instincts.md   # …and is newer than the index on disk

# 1. main trunk mode: the hook leaves the tracked index alone and the checkout clean, still prints the lessons line with the right count.
out="$(ctx "$R")"
[ -z "$(git status --porcelain -- .agents/instincts-index.md)" ] && ok "trunk main: tracked index not rewritten (status clean)" \
  || fail "trunk main dirty after SessionStart: $(git status --porcelain)"
printf '%s\n' "$out" | grep -q 'Bài học của dự án: .agents/instincts.md (41 mục' && ok "  … and the lessons line still names 41 entries" \
  || fail "lessons line missing/wrong: $(printf '%s' "$out" | grep -i 'instincts' | head -2)"

# 2. linked worktree: index regenerated as before.
W="$TMPR/linked"; git worktree add -q --detach "$W" 2>/dev/null
sleep 1; printf '\n### [INSTINCT-042] Added in the worktree\n' >> "$W/.agents/instincts.md"
ctx "$W" >/dev/null
git -C "$W" status --porcelain -- .agents/instincts-index.md | grep -q 'instincts-index.md' && ok "linked worktree: stale index regenerated as before" \
  || fail "linked worktree index not regenerated"

# 3. agent-kit learn: instincts.md and the index agree in the same run.
export CLAUDE_PROJECT_DIR="$R"
bash "$KIT" learn "Fresh trap for index" --cause c --rule r >/dev/null
n="$(grep -c '^### \[INSTINCT-' .agents/instincts.md)"
idx=".agents/instincts-index.md"
grep -q 'Fresh trap for index' "$idx" && ok "learn: the new lesson is in the index in the same run" || fail "learn left the index stale"
line="$(grep -n 'Fresh trap for index' .agents/instincts.md | head -1 | cut -d: -f1)"
grep 'Fresh trap for index' "$idx" | grep -q "sed -n '${line}," && ok "  … and its line range starts at the real line ($line)" || fail "index range does not match line $line"
[ "$n" -eq 42 ] && ok "  … entry count $n" || fail "entry count $n"
exit "$FAILS"
