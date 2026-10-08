#!/bin/bash
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D"

mkdir -p proj/.agents/local
mkdir -p devkit/profiles/android
mkdir -p devkit/profiles/ios
ln -s "$DEVKIT_ROOT/scripts" devkit/scripts
ln -s "$DEVKIT_ROOT/templates" devkit/templates

# init devkit profile android
cat << 'MD' > devkit/profiles/android/instincts.md
# Android Profile
MD

# init devkit profile ios with [INSTINCT-005]
cat << 'MD' > devkit/profiles/ios/instincts.md
# iOS Profile

---

### [INSTINCT-005] Old Trap
- **Rule:** Do something
MD

# init proj instincts
cat << 'MD' > proj/.agents/instincts.md
# Proj Instincts
MD

export CLAUDE_PROJECT_DIR="$D/proj"
REAL_DEVKIT_ROOT="$DEVKIT_ROOT"
export DEVKIT_ROOT="$D/devkit"

ERRORS=0

echo "--- Test (iv): add không cờ không tạo queue ---"
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" add "Old Trap" --cause "C" --rule "R" --symptom "S"
if [ -f "$D/proj/.agents/local/upstream-queue.md" ]; then
    echo "FAIL: upstream-queue.md created when it shouldn't be"
    ERRORS=$((ERRORS+1))
else
    echo "OK: upstream-queue.md not created"
fi

echo "--- Test (i): agent-kit learn --generic ghi cả hai file ---"
"$REAL_DEVKIT_ROOT/bin/agent-kit" learn "New Trap" --cause "C2" --rule "R2" --symptom "S2" --generic 2>/dev/null || true
if ! grep -q "New Trap" "$D/proj/.agents/local/upstream-queue.md" 2>/dev/null; then
    echo "FAIL: New Trap not in upstream-queue.md"
    ERRORS=$((ERRORS+1))
else
    echo "OK: upstream-queue.md created and updated"
fi

echo "--- Test (v): promote --dry-run không ghi gì ---"
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" promote --from "$D/proj" --profile android --kit "$D/devkit" --dry-run 2>/dev/null || true
if grep -q "New Trap" devkit/profiles/android/instincts.md 2>/dev/null; then
    echo "FAIL: New Trap written during dry-run"
    ERRORS=$((ERRORS+1))
else
    echo "OK: dry-run didn't write"
fi

echo "--- Test (ii): promote ghi vào profile android ---"
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" promote --from "$D/proj" --profile android --kit "$D/devkit" 2>/dev/null || true
if ! grep -q "New Trap" devkit/profiles/android/instincts.md 2>/dev/null; then
    echo "FAIL: New Trap not in profile android instincts"
    ERRORS=$((ERRORS+1))
else
    echo "OK: profile android instincts updated"
fi
if ! grep -q -E -e "promoted:\*\* android" "$D/proj/.agents/local/upstream-queue.md" 2>/dev/null; then
    echo "FAIL: not marked as promoted to android in queue"
    ERRORS=$((ERRORS+1))
else
    echo "OK: marked as promoted to android in queue"
fi

if grep -q -E -e "---[[:space:]]*---" devkit/profiles/android/instincts.md; then
    echo "FAIL: double separators found"
    ERRORS=$((ERRORS+1))
else
    echo "OK: no double separators"
fi

echo "--- Test: promote duplicate entry (Old Trap) to ios ---"
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" add "Old Trap" --force --generic 2>/dev/null || true
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" promote --from "$D/proj" --profile ios --kit "$D/devkit" 2>/dev/null || true
if [ $(grep -c "### \[INSTINCT" devkit/profiles/ios/instincts.md) -ne 2 ]; then
    echo "FAIL: duplicate entry was added instead of ignored/marked"
    ERRORS=$((ERRORS+1))
else
    echo "OK: duplicate entry only marked, not duplicated"
fi
if ! grep -q -E -e "promoted:\*\* ios" "$D/proj/.agents/local/upstream-queue.md" 2>/dev/null; then
    echo "FAIL: duplicate entry not marked as promoted to ios in queue"
    ERRORS=$((ERRORS+1))
else
    echo "OK: duplicate entry marked as promoted to ios in queue"
fi

echo "--- Test: promote to two profiles, check next ID ---"
if ! grep -q "\[INSTINCT-006\] New Trap" devkit/profiles/ios/instincts.md; then
    echo "FAIL: New Trap didn't get INSTINCT-006 in ios profile"
    ERRORS=$((ERRORS+1))
else
    echo "OK: New Trap got INSTINCT-006 in ios profile"
fi

echo "--- Test (iii): chạy promote lần hai = không đổi ---"
MD5_BEFORE=$(md5sum devkit/profiles/ios/instincts.md | awk '{print $1}')
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" promote --from "$D/proj" --profile ios --kit "$D/devkit" 2>/dev/null || true
MD5_AFTER=$(md5sum devkit/profiles/ios/instincts.md | awk '{print $1}')
if [ "$MD5_BEFORE" != "$MD5_AFTER" ]; then
    echo "FAIL: profile modified on second promote"
    ERRORS=$((ERRORS+1))
else
    echo "OK: second promote didn't modify profile"
fi
echo "--- Test (vii): chạy promote lần ba và kiểm tra số lượng marker ---"
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" promote --from "$D/proj" --profile ios --kit "$D/devkit" 2>/dev/null || true
MARKER_COUNT=$(grep -c "\*\*promoted:\*\* ios" "$D/proj/.agents/local/upstream-queue.md" || true)
if [ "$MARKER_COUNT" -ne 2 ]; then # 2 entries were promoted to ios
    echo "FAIL: marker count is $MARKER_COUNT instead of 2"
    ERRORS=$((ERRORS+1))
else
    echo "OK: marker count is correct"
fi

echo "--- Test (vi): kiểm tra không có đôi dấu phân cách liền nhau ---"
if perl -0777 -ne 'exit(!/---\s*\n\s*---/)' devkit/profiles/ios/instincts.md; then
    echo "FAIL: profile contains double separator"
    ERRORS=$((ERRORS+1))
else
    echo "OK: profile does not contain double separator"
fi

echo "--- Test (viii): kiểm tra biên --profile ---"
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" promote --from "$D/proj" --profile ../.. --kit "$D/devkit" 2>/dev/null && {
    echo "FAIL: promote accepted ../.."
    ERRORS=$((ERRORS+1))
}
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" promote --from "$D/proj" --profile /etc --kit "$D/devkit" 2>/dev/null && {
    echo "FAIL: promote accepted /etc"
    ERRORS=$((ERRORS+1))
}
echo "OK: promote rejected invalid profiles"

echo "--- Test (ix): Race condition lock file ---"
# Thêm Lesson A trước
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" add "Lesson A" --generic >/dev/null

PROFILE_FILE="$D/devkit/profiles/ios/instincts.md"
touch "$PROFILE_FILE"

# Python block to hold LOCK_EX on PROFILE_FILE
cat << 'EOF' > "$D/proj/hold_profile_lock.py"
import sys, time, fcntl
with open(sys.argv[1], "a+") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    sys.stdout.write("LOCKED\n")
    sys.stdout.flush()
    time.sleep(10)
EOF

# Chạy trình giữ khóa nền
python3 -I "$D/proj/hold_profile_lock.py" "$PROFILE_FILE" > "$D/proj/profile_lock_status.txt" &
PROFILE_LOCK_PID=$!

# Chờ khóa profile
while ! grep -q "LOCKED" "$D/proj/profile_lock_status.txt" 2>/dev/null; do
    sleep 0.1
done

# Chạy promote nền (sẽ chặn ở profile)
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" promote --from "$D/proj" --profile ios --kit "$D/devkit" >/dev/null 2>&1 &
PROMOTE_PID=$!

# Kịch bản dò sidecar lock (thử LOCK_NB)
cat << 'EOF' > "$D/proj/probe_lock.py"
import sys, fcntl
try:
    with open(sys.argv[1], "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # Khóa thành công -> trả về 0 (promote chưa giữ)
        sys.exit(0)
except BlockingIOError:
    # Bị block -> promote đã giữ -> trả về 1
    sys.exit(1)
EOF

LOCK_FILE="$D/proj/.claude/audit-gate/upstream-queue.lock"
mkdir -p "$D/proj/.claude/audit-gate"
touch "$LOCK_FILE"

PROBE_WAITED=0
while python3 -I "$D/proj/probe_lock.py" "$LOCK_FILE"; do
    sleep 0.1
    PROBE_WAITED=$((PROBE_WAITED+1))
    if [ $PROBE_WAITED -gt 100 ]; then
        echo "FAIL: promote never acquired sidecar lock"
        ERRORS=$((ERRORS+1))
        break
    fi
done

# Khi probe_lock.py exit 1 -> promote đang giữ khóa sidecar và chờ profile
# Chạy learn nền
python3 -I "$REAL_DEVKIT_ROOT/bin/instincts.py" add "Lesson B" --generic >/dev/null 2>&1 &
LEARN_PID=$!

# Cho learn 1s để khởi động và chặn
sleep 1

# Nhả khóa profile
kill -9 $PROFILE_LOCK_PID 2>/dev/null || true

wait $PROMOTE_PID
wait $LEARN_PID

QUEUE_CONTENT=$(cat "$D/proj/.agents/local/upstream-queue.md")
PROFILE_CONTENT=$(cat devkit/profiles/ios/instincts.md)

# Lesson B phải không bị mất
if ! echo "$QUEUE_CONTENT" | grep -q "Lesson B"; then
    if ! echo "$PROFILE_CONTENT" | grep -q "Lesson B"; then
        echo "FAIL: Lesson B is completely lost!"
        ERRORS=$((ERRORS+1))
    fi
fi

# Lesson A phải có trong profile đúng 1 lần
A_COUNT=$(echo "$PROFILE_CONTENT" | grep -c "### \[.*\] Lesson A" || true)
if [ "$A_COUNT" -ne 1 ]; then
    echo "FAIL: Lesson A is in profile $A_COUNT times"
    ERRORS=$((ERRORS+1))
else
    echo "OK: Lesson A is in profile exactly 1 time, Lesson B not lost"
fi

LOCK_COUNT=$(find "$D/proj/.agents/local" -name "*.lock" | wc -l)
if [ "$LOCK_COUNT" -ne 0 ]; then
    echo "FAIL: Found .lock files in .agents/local/"
    find "$D/proj/.agents/local" -name "*.lock"
    ERRORS=$((ERRORS+1))
else
    echo "OK: No .lock files in .agents/local/"
fi

if [ $ERRORS -gt 0 ]; then
    echo "$ERRORS FAILED"
    exit 1
else
    echo "ALL OK"
    exit 0
fi
