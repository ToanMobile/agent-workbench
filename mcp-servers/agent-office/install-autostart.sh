#!/bin/bash
# Cài Agent Office chạy nền: tự bật khi đăng nhập macOS, tự chạy lại nếu bị tắt.
# Chạy từ bản sao ở ~/.agent-office/app, không chạy thẳng từ thư mục nguồn (worktree bị xoá thì launchd không hỏng).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/.agent-office/app"
LABEL="com.toanmobile.agent-office"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "Không thấy python3. Cài Xcode Command Line Tools: xcode-select --install"; exit 1; fi
mkdir -p "$HOME/Library/LaunchAgents" "$APP"
rm -rf "$APP/web"
cp -R "$SRC/server.py" "$SRC/inbox_hook.py" "$SRC/config.json" "$SRC/web" "$APP/"
chmod 700 "$HOME/.agent-office" "$APP"
# Bản chép không nằm trong repo: chỉ cho server đường dẫn ai-factory.sh thật (nút "Tạo mã mới" của menu Điện thoại gọi nó).
FACTORY="$(cd "$SRC/../.." && pwd)/ai-factory.sh"
"$PY" - "$PLIST" "$LABEL" "$PY" "$APP" "$HOME" "$FACTORY" <<'PYEOF'
import plistlib, sys
path, label, py, app, home, factory = sys.argv[1:7]
plist = {
    "Label": label,
    "ProgramArguments": [py, app + "/server.py"],
    "WorkingDirectory": app,
    "RunAtLoad": True,
    "KeepAlive": {"SuccessfulExit": False},
    "ThrottleInterval": 20,
    "EnvironmentVariables": {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                             "AGENT_OFFICE_FACTORY_SCRIPT": factory},
    "StandardOutPath": home + "/.agent-office/server.log",
    "StandardErrorPath": home + "/.agent-office/server.log",
}
with open(path, "wb") as f:
    plistlib.dump(plist, f)
PYEOF
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null; then launchctl load -w "$PLIST"; fi
PORT="$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1])).get("port",4317))' "$APP/config.json" 2>/dev/null || echo 4317)"
echo "Đã cài. Agent Office tự chạy khi đăng nhập: http://127.0.0.1:$PORT (hoặc http://ai-factory.test:$PORT nếu đã thêm vào /etc/hosts)"
echo "Bản chạy: $APP (đổi code hoặc config.json ở nguồn thì chạy lại script này). Log: tail -f ~/.agent-office/server.log"
