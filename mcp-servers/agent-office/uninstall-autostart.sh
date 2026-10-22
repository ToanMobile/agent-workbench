#!/bin/bash
# Gỡ chế độ chạy nền của Agent Office.
LABEL="com.toanmobile.agent-office"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl unload -w "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "Đã gỡ. Agent Office không còn tự chạy khi đăng nhập."
