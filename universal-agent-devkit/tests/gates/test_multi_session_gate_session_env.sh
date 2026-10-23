#!/usr/bin/env bash
# Test hồi quy (#240, 22/10): các suite của merge gate phải xanh khi chạy TRONG phiên/verify của máy thật.
# post-fix-gate chọn id phiên theo thứ tự --session, DEVKIT_SESSION_ID, CLAUDE_CODE_SESSION_ID, CLAUDE_SESSION_ID; phiên Claude hay worker
# board export các biến đó. test_multi_session_gate.sh (ca 7: "phiên của chính mình qua CLAUDE_CODE_SESSION_ID không bị đếm là phiên khác") và
# test_gate_stop_reuse_race.sh (ca K1: gate đổi nhánh theo id phiên) đọc id của máy thật và đỏ oan ở merge gate.
# multi_session_gate (nhanh): chạy thật với id rò vào. reuse_race (~2 phút): chạy thật file suite nhưng dừng ở lệnh đầu sau `unset` (shim mktemp), không chạy gate.
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
OUT="$(DEVKIT_SESSION_ID=leaked-real-session CLAUDE_SESSION_ID=leaked-real-session CLAUDE_CODE_SESSION_ID=leaked-real-session \
  bash "$DEVKIT_DIR/tests/gates/test_multi_session_gate.sh" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "✔ test_multi_session_gate.sh xanh khi id phiên của máy thật rò vào môi trường"
else
  printf '%s\n' "$OUT" | grep -E "^(✖|❌)" | head -10
  echo "✖ test_multi_session_gate.sh exit $rc khi id phiên thật rò vào"
  FAILS=$((FAILS + 1))
fi
# reuse_race: chạy THẬT file suite nhưng chặn ở lệnh ngoài đầu tiên sau dòng `unset` (mktemp): shim ghi lại id phiên mà suite còn thấy rồi thoát.
# Nhanh (không chạy gate), và chỉ đỏ khi hành vi đổi: gỡ dòng `unset` thì shim thấy id rò vào.
TMPD="$(mktemp -d)" || { echo "✖ mktemp failed"; exit 1; }
trap 'rm -rf "$TMPD"' EXIT
mkdir "$TMPD/bin"
cat > "$TMPD/bin/mktemp" <<'SHIM'
#!/bin/sh
env | grep -E '^(DEVKIT_SESSION_ID|CLAUDE_SESSION_ID|CLAUDE_CODE_SESSION_ID)=' > "$SEEN_FILE"
exit 1
SHIM
chmod +x "$TMPD/bin/mktemp"
# AC2: suite không đụng registry phiên thật — chụp danh sách + mtime trước/sau.
snap() { python3 -I -c 'import os,sys
sys.path.insert(0, sys.argv[1])
import session_lock
d, _ = session_lock.sessions_dir(os.getcwd())
print(sorted((f, os.stat(os.path.join(d, f)).st_mtime_ns) for f in os.listdir(d)) if d and os.path.isdir(d) else [])' "$DEVKIT_DIR/bin"; }
BEFORE="$(snap)"
SEEN_FILE="$TMPD/seen" PATH="$TMPD/bin:$PATH" \
  DEVKIT_SESSION_ID=leaked-a CLAUDE_SESSION_ID=leaked-b CLAUDE_CODE_SESSION_ID=leaked-c \
  bash "$DEVKIT_DIR/tests/gates/test_gate_stop_reuse_race.sh" >/dev/null 2>&1
if [ -f "$TMPD/seen" ] && [ ! -s "$TMPD/seen" ]; then
  echo "✔ test_gate_stop_reuse_race.sh chạy thật: id phiên rò vào đã bị gỡ trước khi suite chạm gate"
else
  echo "✖ test_gate_stop_reuse_race.sh còn thấy id phiên rò vào: $(cat "$TMPD/seen" 2>/dev/null | tr '\n' ' ') (shim không chạy nếu file thiếu)"
  FAILS=$((FAILS + 1))
fi
if [ "$BEFORE" = "$(snap)" ]; then
  echo "✔ registry phiên thật không đổi trước/sau"
else
  echo "✖ registry phiên thật bị đổi bởi suite"
  FAILS=$((FAILS + 1))
fi
if [ "$FAILS" -eq 0 ]; then echo "✅ test_multi_session_gate_session_env: all passed"; else echo "❌ test_multi_session_gate_session_env: $FAILS ca đỏ"; exit 1; fi
