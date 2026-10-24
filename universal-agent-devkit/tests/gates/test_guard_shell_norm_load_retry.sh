#!/usr/bin/env bash
# tests/gates/test_guard_shell_norm_monotonic.sh must not go red because the machine is busy (#147): under load the 7 s analysis
# watchdog of hooks/hardware_safety_gate.sh (production budget, unchanged) fires on a harmless CONTROL row and the hook answers rc 2
# with its "quá lớn / quá phức tạp" message. That is no verdict, so the row is run again; the safety net still has to catch a real defect.
# Oracle: HW_HOOK points at a wrapper around the real hook that plays a loaded machine.
#   - "once":   the first run of every payload the real hook passes ends in the watchdog message (rc 2); the second run is the real answer.
#               The monotonic test must PASS (before the fix: ✖ CONTROL hw rc 2 + VACUOUS).
#   - "always": the watchdog fires on every run of those payloads (a hook that really is too slow). The monotonic test must still FAIL.
#   - "blocks": the hook blocks a control for a real reason (no watchdog message). The monotonic test must FAIL at once.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MONO="$DEVKIT_DIR/tests/gates/test_guard_shell_norm_monotonic.sh"
REAL_HW="$DEVKIT_DIR/hooks/hardware_safety_gate.sh"
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

run_mono once;   rc=$?
[ "$rc" = 0 ] && ok "a watchdog answer on the first run of a CONTROL row is retried: the monotonic test passes" \
  || { bad "load simulation 'once': the monotonic test failed (rc $rc)"; head -5 "$TMP/once.out"; }
run_mono always; rc=$?
[ "$rc" != 0 ] && ok "a hook that is always too slow still fails the monotonic test" \
  || bad "load simulation 'always': the monotonic test passed although the hook never judged the CONTROL rows"
run_mono blocks; rc=$?
[ "$rc" != 0 ] && grep -q "CONTROL" "$TMP/blocks.out" && ok "a control blocked for a real reason still fails (no retry masks it)" \
  || bad "load simulation 'blocks': a really blocked CONTROL was not reported (rc $rc)"

[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS ($fails)"; exit 1; }
