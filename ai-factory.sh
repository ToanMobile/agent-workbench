#!/usr/bin/env bash
# ai-factory: one command for the whole factory.
#   ai-factory          start Agent Office, every super-board runner, and a Cloudflare quick tunnel;
#                       print a QR code (link + a fresh secret key) to open the office on a phone anywhere
#   ai-factory stop     stop the tunnel (the key stops working), the Agent Office server it started, every runner
#   ai-factory status   show what runs
# The key changes on every start, so an old QR code stops working; the Mac itself never needs it.
set -uo pipefail

SELF="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$0")"
ROOT="$(cd "$(dirname "$SELF")" && pwd)"
APP="$ROOT/mcp-servers/agent-office"
BOARDS="$ROOT/universal-agent-devkit/scripts/governance/super_board_all.py"
STATE="$HOME/.agent-office"
KEY_FILE="$STATE/remote-key"
SRV_PID="$STATE/server.pid"
TUN_PID="$STATE/tunnel.pid"
TUN_LOG="$STATE/tunnel.log"
mkdir -p "$STATE" && chmod 700 "$STATE"
PORT="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("port",4317))' "$APP/config.json")"

listening() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; }
alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }
stop_pid() { # only the PID this script recorded, never a process found by name
  if alive "$1"; then kill "$(cat "$1")"; fi
  rm -f "$1"
}

case "${1:-start}" in
  stop)
    stop_pid "$TUN_PID"; rm -f "$KEY_FILE"
    stop_pid "$SRV_PID"
    python3 "$BOARDS" stop
    echo "Đã dừng AI Factory (tunnel, server, các board)."
    exit 0 ;;
  status)
    if listening; then echo "Agent Office: đang chạy (http://ai-factory.localhost:$PORT/)"; else echo "Agent Office: tắt"; fi
    if alive "$TUN_PID"; then echo "Tunnel: đang chạy ($(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$TUN_LOG" | head -1))"; else echo "Tunnel: tắt"; fi
    python3 "$BOARDS" status
    exit 0 ;;
  start) ;;
  *) echo "Dùng: ai-factory [start|stop|status]"; exit 2 ;;
esac

# 1. Agent Office server (left alone when one already listens, e.g. the autostart one)
if ! listening; then
  (cd "$APP" && nohup python3 server.py >>"$STATE/server.log" 2>&1 & echo $! >"$SRV_PID")
  for _ in $(seq 1 40); do listening && break; sleep 0.25; done
fi
if listening; then echo "✔ Agent Office: http://ai-factory.localhost:$PORT/"; else echo "✖ Agent Office không lên, xem $STATE/server.log"; exit 1; fi

# 2. every super-board runner
if python3 "$BOARDS" start; then echo "✔ Các board đã chạy"; else echo "⚠ Một số board không khởi động được (xem ở trên)"; fi

# 3. quick tunnel with a fresh key: the old tunnel and its key go first
stop_pid "$TUN_PID"
if ! command -v cloudflared >/dev/null; then
  echo "⚠ Chưa có cloudflared (brew install cloudflared): bỏ qua truy cập từ xa"
else
  (umask 077 && python3 -c 'import secrets;print(secrets.token_urlsafe(32))' >"$KEY_FILE")
  : >"$TUN_LOG"
  nohup cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" >"$TUN_LOG" 2>&1 &
  echo $! >"$TUN_PID"
  URL=""
  for _ in $(seq 1 60); do
    URL="$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$TUN_LOG" | head -1)"
    [ -n "$URL" ] && break
    alive "$TUN_PID" || break
    sleep 0.5
  done
  if [ -z "$URL" ]; then
    echo "✖ Tunnel không lên, xem $TUN_LOG"
    stop_pid "$TUN_PID"; rm -f "$KEY_FILE"
  else
    LINK="$URL/#key=$(cat "$KEY_FILE")"
    echo
    echo "📱 Quét mã này bằng điện thoại (mã đổi mỗi lần chạy ai-factory):"
    if command -v qrencode >/dev/null; then qrencode -t ANSIUTF8 -m 2 "$LINK"; else echo "(cài qrencode để hiện QR: brew install qrencode)"; fi
    printf %s "$LINK" | pbcopy 2>/dev/null && echo "Link đầy đủ đã chép vào clipboard."
    echo "Địa chỉ tunnel: $URL"
  fi
fi

# 4. open the office on this Mac
open "http://ai-factory.localhost:$PORT/" 2>/dev/null || true
