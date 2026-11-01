#!/usr/bin/env bash
# Hồi quy r14b (#742, 31/10): review_gate.sh chạy `mkdir -p` trước khi kiểm python3. Với PATH không có python3 (QA K-4) lệnh
# đầu tiên hỏng là `mkdir: command not found`, che mất thông báo "python3 không có". Gate phải kiểm python3 trước mọi lệnh
# ngoài, chặn Stop (exit 2, fail-closed) với thông báo nhắc python3 và không tạo gì trong project.
# REVIEW_GATE_HOOK chỉ để chạy test trên bản nháp của hook. Tương thích bash 3.2.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${REVIEW_GATE_HOOK:-$HERE/../../hooks/review_gate.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rg-nopy.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/proj"
for tool in bash cat; do ln -sf "$(command -v "$tool")" "$TMP/bin/$tool"; done

out=$(printf '%s' '{"transcript_path":"/nonexistent","last_assistant_message":"xong"}' \
      | env -i HOME="$TMP" CLAUDE_PROJECT_DIR="$TMP/proj" PATH="$TMP/bin" bash "$HOOK" 2>&1)
rc=$?
first=$(printf '%s\n' "$out" | head -1)
[ "$rc" -eq 2 ] && ok "no python3 → Stop blocked (exit 2, fail-closed)" || fail "no python3: rc=$rc (want 2): $out"
case "$first" in *python3*) ok "first line names python3: $first" ;; *) fail "first line does not name python3: $first" ;; esac
case "$out" in *"command not found"*) fail "a command ran before the python3 check: $out" ;; *) ok "nothing runs before the python3 check" ;; esac
[ ! -e "$TMP/proj/.claude" ] && ok "nothing written in the project" || fail "project written before the python3 check: $(ls -A "$TMP/proj")"

# #754 b: a worktree session (payload cwd under /.claude/worktrees/) went into the W1 v6 block first — python3 and `basename`
# ran before the python3 check, so its first line was the "worktree could not be resolved" warning or "basename: command not found"
out=$(printf '{"session_id":"s1","cwd":"%s/.claude/worktrees/x","transcript_path":"/nonexistent","last_assistant_message":"xong"}' "$TMP/proj" \
      | env -i HOME="$TMP" CLAUDE_PROJECT_DIR="$TMP/proj" PATH="$TMP/bin" bash "$HOOK" 2>&1)
rc=$?
first=$(printf '%s\n' "$out" | head -1)
[ "$rc" -eq 2 ] && ok "worktree session, no python3 → Stop blocked (exit 2)" || fail "worktree session, no python3: rc=$rc (want 2): $out"
case "$first" in *python3*) ok "worktree session: first line names python3" ;; *) fail "worktree session: first line does not name python3: $first" ;; esac
case "$out" in *"command not found"*) fail "worktree session: a command ran before the python3 check: $out" ;; *) ok "worktree session: nothing runs before the python3 check" ;; esac
[ ! -e "$TMP/proj/.claude" ] && ok "worktree session: nothing written in the project" || fail "worktree session: project written: $(ls -A "$TMP/proj")"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
