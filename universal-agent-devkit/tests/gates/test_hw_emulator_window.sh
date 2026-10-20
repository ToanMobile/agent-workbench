#!/usr/bin/env bash
# Test hồi quy cho phần chặn Android Emulator thiếu -no-window của hooks/hardware_safety_gate.sh (ac2c2731, 20/10).
#
# 20/10: hàm emulator_window_violation tách cả lệnh theo từng dòng và phân tích từng đoạn, kể cả khi lệnh không nhắc
# tới emulator: `eval '<12000 dòng trống>…ls'` mất 3,66 s (bản trước 0,12 s), test_guard_shell_norm_monotonic (8 luồng,
# máy tải nặng) chạm hạn 7 s và hook chặn một lệnh vô hại (fail-closed). Lệnh không có chữ emulator/qemu-system/-avd
# (sau khi bỏ dấu nháy và \) phải đi qua ngay; hành vi chặn giữ nguyên. Tương thích bash 3.2.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HW="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P/src"
git -C "$P" init -q . && printf 'x\n' > "$P/src/a.kt" && git -C "$P" add -A \
  && git -C "$P" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm init
unset HARDWARE_SAFETY_GATE HARDWARE_OVERRIDE PROOF_WINDOW

python3 -I - "$HW" "$P" <<'PY'
import json, os, shlex, subprocess, sys, time
hw, proj = sys.argv[1:3]
env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
env.update(CLAUDE_PROJECT_DIR=proj, ADB_DENY_SERIALS="", ADB_ALLOW_SERIALS="", ANDROID_SERIAL="")
fails = 0

def run(cmd):
    payload = json.dumps({"session_id": "s", "transcript_path": "", "cwd": proj, "hook_event_name": "PreToolUse",
                          "tool_name": "Bash", "tool_input": {"command": cmd, "description": "d"}})
    t0 = time.time()
    p = subprocess.run(["bash", hw], input=payload, capture_output=True, text=True, cwd=proj, env=env, timeout=90)
    return p.returncode, time.time() - t0, p.stderr

def check(cmd, want, what):
    global fails
    rc, _, err = run(cmd)
    if rc == want:
        print(f"✔ {what}")
    else:
        fails += 1
        print(f"✖ {what}: rc {rc} (want {want}) {err[:160]!r}")

check("emulator -avd Pixel", 2, "emulator -avd without -no-window is blocked")
check("emulator -avd Pixel -no-window -no-audio", 0, "emulator -avd -no-window passes")
check('e"m"ulator -avd Pixel', 2, "quoted e\"m\"ulator -avd is still blocked")
check("bash -c 'emulator -avd Pixel'", 2, "emulator inside bash -c is blocked")
check("PROOF_WINDOW=1 emulator -avd Pixel", 0, "PROOF_WINDOW=1 allows the window")
check("emulator -list-avds", 0, "emulator -list-avds passes")
check("ls\nemulator -avd Pixel", 2, "emulator on a later line is blocked")

big = "git status\n" + "\n" * 12000 + "cat > x <<EOF\nb\nEOF\nls"
for name, cmd in (("eval", "eval " + shlex.quote(big)), ("plain", big)):
    best = min(run(cmd)[1] for _ in range(2))
    rc = run(cmd)[0]
    if rc == 0 and best < 1.0:
        print(f"✔ harmless 12000-line command ({name}) passes in {best:.2f}s")
    else:
        fails += 1
        print(f"✖ harmless 12000-line command ({name}): rc {rc}, {best:.2f}s (want rc 0 under 1 s)")
sys.exit(1 if fails else 0)
PY
rc=$?
[ "$rc" -eq 0 ] && echo "✅ test_hw_emulator_window: all passed" || { echo "❌ test_hw_emulator_window: failed"; exit 1; }
