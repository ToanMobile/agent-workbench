# tests/lib/guard_shell_norm_load_lib.sh: phần chung của tests/gates/test_guard_shell_norm_load_retry*.sh (mỗi chế độ tải một file,
# tách 03/11). Source sau khi đặt MONO (tests/gates/test_guard_shell_norm_monotonic.sh) và REAL_HW (hooks/hardware_safety_gate.sh):
# tạo TMP (xoá khi thoát), fails / ok / bad, wrapper $TMP/loaded_hw.sh giả máy tải nặng, và run_mono.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok() { echo "ok: $1"; }
bad() { echo "✖ $1"; fails=$((fails + 1)); }

cat > "$TMP/loaded_hw.sh" <<'WRAP'
#!/usr/bin/env bash
# a hardware gate on a loaded machine; LOAD_MODE = once | always | blocks, LOAD_DIR = marker folder, REAL_HW = the real hook
payload="$(cat)"
err="$LOAD_DIR/err.$$"
printf '%s' "$payload" | bash "$REAL_HW" 2>"$err"
rc=$?
if [ "$rc" = 0 ]; then
  key="$(printf '%s' "$payload" | cksum | tr -d ' ')"
  case "$LOAD_MODE" in
    once) if [ ! -e "$LOAD_DIR/seen.$key" ]; then
            : > "$LOAD_DIR/seen.$key"
            echo "🛑 [HARDWARE SAFETY GATE] lệnh quá lớn / quá phức tạp để phân tích trong thời hạn của hook (7 s của 10 s) — chặn để an toàn." >&2
            rm -f "$err"; exit 2
          fi ;;
    always) echo "🛑 [HARDWARE SAFETY GATE] lệnh quá lớn / quá phức tạp để phân tích trong thời hạn của hook (7 s của 10 s) — chặn để an toàn." >&2
            rm -f "$err"; exit 2 ;;
    blocks) echo "🛑 [HARDWARE SAFETY GATE REJECTED] a real block of a harmless command" >&2
            rm -f "$err"; exit 2 ;;
  esac
fi
cat "$err" >&2
rm -f "$err"
exit "$rc"
WRAP

run_mono() {   # run_mono <mode>: the monotonic test with the wrapped hardware hook; prints nothing, returns its exit code
  mkdir -p "$TMP/$1"
  LOAD_MODE="$1" LOAD_DIR="$TMP/$1" REAL_HW="$REAL_HW" HW_HOOK="$TMP/loaded_hw.sh" bash "$MONO" > "$TMP/$1.out" 2>&1
}
