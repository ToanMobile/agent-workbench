#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 6): heavy gate bỏ lượt khi không có gì mới. Bỏ CHỈ khi fetch thành công VÀ sha của ref == last_full_green_sha
# VÀ hash cây kit (HEAD) == last_full_green_kit; một bên rỗng hoặc fetch lỗi ⇒ chạy. --force luôn chạy; --force mà mất khoá ⇒ exit khác 0.
# Mọi lượt skip (không commit mới, khoá bận) ghi một dòng history.jsonl có skip_reason.
# Kit chép (gate_full.py + capacity.py) vào một repo git tạm để đổi được commit của kit; gate giả (DEVKIT_GATE_FULL_CMD) luôn xanh.
#   k1. lượt đầu xanh: ghi last_full_green_kit = hash cây kit;
#   k2. lượt hai cùng sha, cùng kit: skip, exit 0, gate không chạy, history skip_reason no-new-commit, summary-latest.md không bị đè;
#   k3. --force: gate chạy;
#   k4. kit có commit mới: gate chạy;
#   k5. origin có commit mới: gate chạy;
#   k6. fetch lỗi (origin hỏng): gate chạy;
#   k7. không có last_full_green_kit: gate chạy;
#   k8. khoá repo do pid sống giữ: không --force exit 0 + dòng history skip_reason lock; --force exit khác 0.
# Tương thích bash 3.2.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-heavy-skip.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd -P)"
SLEEP_PID=""
cleanup() { [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

# kit trong repo git riêng (hash cây kit đổi được bằng commit)
K="$T/kitrepo"
mkdir -p "$K/universal-agent-devkit/bin"
cp "$DEVKIT_DIR/bin/gate_full.py" "$DEVKIT_DIR/bin/capacity.py" "$K/universal-agent-devkit/bin/"
g init -q "$K" && g -C "$K" add -A && g -C "$K" commit -qm kit
GF="$K/universal-agent-devkit/bin/gate_full.py"

g init -q --bare "$T/origin.git"
g init -q "$T/seed"
printf 'a\n' >"$T/seed/a.txt"
g -C "$T/seed" add -A && g -C "$T/seed" commit -qm base
g -C "$T/seed" remote add origin "$T/origin.git"
g -C "$T/seed" push -q origin main
g clone -q "$T/origin.git" "$T/repo"
COMMON="$(cd "$T/repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
PG="$COMMON/postfix-gate"
HIST="$PG/nightly/history.jsonl"

cat >"$T/fakegate.sh" <<'SH'
#!/bin/sh
echo x >>"$FAKE_CALLS"
d="$(git rev-parse --absolute-git-dir)/postfix-gate"; mkdir -p "$d"; echo '{"fake": "pass"}' >"$d/full_pass.json"
echo '{"verdict": "PASS", "exit_code": 0, "regression_tests": [{"id": "REG-FAKE-01", "status": "PASS", "command": "true"}]}'
SH
chmod +x "$T/fakegate.sh"
export FAKE_CALLS="$T/gate.calls" DEVKIT_GATE_FULL_CMD="sh $T/fakegate.sh" DEVKIT_GATE_FULL_LOG_DIR="$T/logs"
export DEVKIT_GATE_FULL_POLL_S=1 DEVKIT_CAPACITY_LOAD=0 DEVKIT_GATE_FULL_GLOBAL_LOCK="$T/global.lock"

run_gf() { : >"$T/gate.calls"; python3 "$GF" run --repo "$T/repo" "$@" >"$T/out" 2>&1; echo $?; }
ran() { [ -s "$T/gate.calls" ]; }
last() { tail -1 "$HIST" 2>/dev/null | python3 -c "import json,sys; r=json.load(sys.stdin); print($1)" 2>/dev/null; }
kit_hash() { git -C "$K" rev-parse HEAD:universal-agent-devkit; }

rc=$(run_gf)
chk "k1. lượt đầu xanh, last_full_green_kit = hash cây kit" \
  '[ "$rc" = 0 ] && ran && [ "$(cat "$PG/last_full_green_kit" 2>/dev/null)" = "$(kit_hash)" ]' "rc=$rc kit=$(cat "$PG/last_full_green_kit" 2>/dev/null) $(tail -3 "$T/out")"
cp "$T/logs/summary-latest.md" "$T/summary.before"
n0=$(wc -l <"$HIST" | tr -d ' ')
rc=$(run_gf)
chk "k2. cùng sha + cùng kit: skip, exit 0, gate không chạy" '[ "$rc" = 0 ] && ! ran && grep -qi skip "$T/out"' "rc=$rc $(tail -3 "$T/out")"
chk "k2b. history thêm một dòng result skip, skip_reason no-new-commit" \
  '[ "$(wc -l <"$HIST" | tr -d " ")" = $((n0 + 1)) ] && [ "$(last "r[\"result\"] + \" \" + r.get(\"skip_reason\", \"\")")" = "skip no-new-commit" ]' "$(tail -1 "$HIST")"
chk "k2c. summary-latest.md không bị lượt skip đè" 'cmp -s "$T/summary.before" "$T/logs/summary-latest.md"'
rc=$(run_gf --force)
chk "k3. --force: gate chạy dù không có gì mới" '[ "$rc" = 0 ] && ran' "rc=$rc $(tail -3 "$T/out")"
printf '# đổi\n' >>"$K/universal-agent-devkit/bin/capacity.py"; g -C "$K" commit -qam kit2
rc=$(run_gf)
chk "k4. kit có commit mới: gate chạy, last_full_green_kit theo kit mới" \
  '[ "$rc" = 0 ] && ran && [ "$(cat "$PG/last_full_green_kit")" = "$(kit_hash)" ]' "rc=$rc $(tail -3 "$T/out")"
rc=$(run_gf)
chk "k4b. (mốc) chạy lại ngay: skip" '[ "$rc" = 0 ] && ! ran' "rc=$rc"
printf 'b\n' >"$T/seed/b.txt"; g -C "$T/seed" add -A; g -C "$T/seed" commit -qm next; g -C "$T/seed" push -q origin main
rc=$(run_gf)
chk "k5. origin có commit mới: gate chạy" '[ "$rc" = 0 ] && ran' "rc=$rc $(tail -3 "$T/out")"
git -C "$T/repo" remote set-url origin "$T/không-có.git"
rc=$(run_gf)
chk "k6. fetch lỗi: không bỏ lượt, gate chạy" '[ "$rc" = 0 ] && ran' "rc=$rc $(tail -3 "$T/out")"
git -C "$T/repo" remote set-url origin "$T/origin.git"
rm -f "$PG/last_full_green_kit"
rc=$(run_gf)
chk "k7. không có last_full_green_kit: gate chạy" '[ "$rc" = 0 ] && ran' "rc=$rc $(tail -3 "$T/out")"
sleep 30 &
SLEEP_PID=$!
mkdir -p "$PG"; printf '{"pid": %s, "started": "x"}\n' "$SLEEP_PID" >"$PG/gate-full.lock"
n0=$(wc -l <"$HIST" | tr -d ' ')
rc=$(run_gf)
chk "k8. khoá bận, không --force: exit 0, gate không chạy, history skip_reason lock" \
  '[ "$rc" = 0 ] && ! ran && [ "$(wc -l <"$HIST" | tr -d " ")" = $((n0 + 1)) ] && [ "$(last "r.get(\"skip_reason\")")" = lock ]' "rc=$rc $(tail -1 "$HIST")"
rc=$(run_gf --force)
chk "k8b. khoá bận + --force: exit khác 0, gate không chạy" '[ "$rc" != 0 ] && ! ran' "rc=$rc $(tail -3 "$T/out")"
kill "$SLEEP_PID" 2>/dev/null; wait "$SLEEP_PID" 2>/dev/null; SLEEP_PID=""

echo
[ "$fails" -eq 0 ] && { echo "PASS test_gate_full_heavy_skip"; exit 0; }
echo "FAIL test_gate_full_heavy_skip ($fails)"; exit 1
