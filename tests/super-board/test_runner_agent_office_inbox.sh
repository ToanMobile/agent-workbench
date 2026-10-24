#!/usr/bin/env bash
# Test: worker claude của runner nhận lệnh Agent Office giữa chừng (hộp thư + hook PostToolUse).
#  1. Không có bản cài ~/.agent-office/app/inbox_hook.py: không thêm cờ nào, không ghi dòng agent_office (lệnh bật như cũ).
#  2. Có bản cài: --session-id <uuid> + --settings (hook) + --append-system-prompt mang nonce; ghi session id vào log worker.
#  3. Hook lỗi (python không chạy được): không thêm nửa bộ cờ.
#  4. Hai dòng bật claude truyền cờ và AGENT_OFFICE_NONCE; agy/grok không đổi.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
HOOK_SRC="$ROOT/mcp-servers/agent-office/inbox_hook.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sb-ao-inbox.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
probe() {  # $1 = HOME giả; in: số cờ | session id | nonce | settings | system prompt
  HOME="$1" SB_LIB_ONLY=1 bash -c '
    set -euo pipefail
    . "$1"; agent_office_args "$2"
    printf "%s\n" "${#AO_ARGS[@]}" "${AO_ARGS[1]:-}" "$AO_NONCE" "${AO_ARGS[3]:-}" "${AO_ARGS[5]:-}"' _ "$RUNNER" "$tmp/worker.log" 2>&1
}

# 1. Không có bản cài.
mkdir -p "$tmp/home0"; : > "$tmp/worker.log"
out=$(probe "$tmp/home0")
[ "$(printf '%s\n' "$out" | sed -n 1p)" = "0" ] && ok "không có hook: không thêm cờ" || fail "không có hook mà vẫn có cờ: $out"
[ ! -s "$tmp/worker.log" ] && ok "không có hook: không ghi dòng agent_office" || fail "không có hook mà log có: $(cat "$tmp/worker.log")"

# 2. Có bản cài.
mkdir -p "$tmp/home1/.agent-office/app"; cp "$HOOK_SRC" "$tmp/home1/.agent-office/app/inbox_hook.py"; : > "$tmp/worker.log"
out=$(probe "$tmp/home1")
n=$(printf '%s\n' "$out" | sed -n 1p); sid=$(printf '%s\n' "$out" | sed -n 2p); nonce=$(printf '%s\n' "$out" | sed -n 3p)
settings=$(printf '%s\n' "$out" | sed -n 4p); prompt=$(printf '%s\n' "$out" | sed -n '5,$p')
[ "$n" = "6" ] && ok "có hook: 6 phần tử cờ" || fail "có hook cho $n phần tử: $out"
printf '%s' "$sid" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' && ok "session id là uuid thường" || fail "session id '$sid'"
grep -qx "agent_office: session_id=$sid" "$tmp/worker.log" && ok "log worker ghi session id" || fail "log worker thiếu dòng agent_office: $(cat "$tmp/worker.log")"
printf '%s' "$settings" | python3 -c 'import json,sys; d=json.load(sys.stdin); c=d["hooks"]["PostToolUse"][0]["hooks"][0]["command"]; assert "inbox_hook.py" in c and "-I -S" in c' \
  && ok "--settings là JSON hook PostToolUse chạy inbox_hook.py" || fail "--settings sai: $settings"
[ -n "$nonce" ] && printf '%s' "$prompt" | grep -q "\[Agent Office $nonce\]" && ok "system prompt mang đúng nonce" || fail "system prompt/nonce sai: nonce='$nonce'"
out2=$(probe "$tmp/home1"); [ "$(printf '%s\n' "$out2" | sed -n 3p)" != "$nonce" ] && ok "mỗi lần giao một nonce mới" || fail "nonce lặp lại"

# 3. Hook lỗi: không nửa bộ cờ.
mkdir -p "$tmp/home2/.agent-office/app"; printf 'import sys\nsys.exit(3)\n' > "$tmp/home2/.agent-office/app/inbox_hook.py"; : > "$tmp/worker.log"
out=$(probe "$tmp/home2")
[ "$(printf '%s\n' "$out" | sed -n 1p)" = "0" ] && [ ! -s "$tmp/worker.log" ] && ok "hook lỗi: không thêm cờ, không ghi log" || fail "hook lỗi mà vẫn có cờ: $out"

# 4. Dòng bật claude.
n_claude=$(grep -c 'nohup "\$SB_WORKER_WRAP" claude ' "$RUNNER")
n_ao=$(grep 'nohup "\$SB_WORKER_WRAP" claude ' "$RUNNER" | grep -- '--verbose ${AO_ARGS\[@\]+"${AO_ARGS\[@\]}"} -p "\$prompt"' | grep -c 'AGENT_OFFICE_NONCE="\$AO_NONCE"')
[ "$n_claude" = 2 ] && [ "$n_ao" = 2 ] && ok "cả 2 dòng bật claude truyền cờ Agent Office và nonce" || fail "dòng bật claude: $n_ao/$n_claude có cờ"
grep 'agy\|grok' "$RUNNER" | grep 'nohup' | grep -q 'AO_ARGS' && fail "agy/grok bị thêm cờ claude" || ok "agy/grok không đổi"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
