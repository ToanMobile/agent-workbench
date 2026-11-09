#!/usr/bin/env bash
# Test hồi quy (OfficeReader issue 258): lượt --full đêm chạy từ launchd, môi trường chỉ có PATH/TZ, không có JAVA_HOME. `./gradlew` rơi về stub
# `java` của macOS ("Unable to locate a Java Runtime", 0,04s) ⇒ 9/10 suite đỏ giả mỗi đêm. gate_full.py tự đặt JAVA_HOME cho gate và checks_fail:
#   a. JAVA_HOME trống + có JDK trong danh sách ứng viên ⇒ gate thấy JAVA_HOME = JDK đầu tiên có bin/java;
#   b. JAVA_HOME đã trỏ JDK dùng được ⇒ giữ nguyên, không ghi đè;
#   c. JAVA_HOME trỏ thư mục không có bin/java ⇒ thay bằng ứng viên đầu tiên dùng được;
#   d. không có ứng viên nào dùng được ⇒ không bịa JAVA_HOME (gate thấy trống, lỗi thật vẫn lộ ra);
#   e. khi suite đỏ và checks_fail chạy lại lệnh suite (ở đỉnh / chia đôi), checks_fail cũng thấy JAVA_HOME ứng viên.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GF="$DEVKIT_DIR/bin/gate_full.py"
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1${2:+ — $2}"; fails=$((fails + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/gate-full-java-home.XXXXXX")" || { echo "✖ mktemp thất bại"; exit 2; }
T="$(cd "$T" && pwd)"
trap 'rm -rf "$T"' EXIT
[ -f "$GF" ] || { echo "✖ thiếu bin/gate_full.py"; exit 1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }
g init -q --bare "$T/origin.git"
g init -q "$T/seed" && printf 'ok\n' >"$T/seed/a.txt" && g -C "$T/seed" add -A && g -C "$T/seed" commit -qm base
g -C "$T/seed" remote add origin "$T/origin.git" && g -C "$T/seed" push -q origin main:main
g clone -q "$T/origin.git" "$T/repo"

# JDK giả: jdk1 (dùng được), jdk2 (dùng được), nojdk (không có bin/java)
mkdir -p "$T/jdk1/bin" "$T/jdk2/bin" "$T/nojdk"
: >"$T/jdk1/bin/java"; : >"$T/jdk2/bin/java"; chmod +x "$T/jdk1/bin/java" "$T/jdk2/bin/java"

# gate giả: ghi JAVA_HOME mà gate thấy, xanh luôn
cat >"$T/fakegate.sh" <<'SH'
#!/bin/sh
printf '%s' "${JAVA_HOME-<unset>}" >"$FAKE_JH"
d="$(git rev-parse --absolute-git-dir)/postfix-gate"; mkdir -p "$d"
echo '{"fake": "pass"}' >"$d/full_pass.json"
echo '{"verdict": "PASS", "exit_code": 0, "regression_tests": [{"id": "REG-FAKE-01", "status": "PASS", "command": "true"}]}'
SH
printf '#!/bin/sh\necho "[]"\n' >"$T/gh"; chmod +x "$T/gh"
printf '#!/bin/sh\nexit 0\n' >"$T/nocard.sh"; chmod +x "$T/nocard.sh"
export PATH="$T:$PATH" FAKE_JH="$T/jh.out" FAKE_RETRY_JH="$T/retry_jh.out"
export DEVKIT_GATE_FULL_CMD="sh $T/fakegate.sh" DEVKIT_GATE_FULL_LOG_DIR="$T/logs" DEVKIT_GATE_FULL_POLL_S=1 DEVKIT_CAPACITY_LOAD=0
export DEVKIT_GATE_FULL_GLOBAL_LOCK="$T/global.lock" DEVKIT_GATE_FULL_CARD_CMD="sh $T/nocard.sh"

run_gf() {
  rm -f "$FAKE_JH" "$FAKE_RETRY_JH" "$T/repo/.git/postfix-gate/last_full_green_sha" "$T/repo/.git/postfix-gate/last_full_green_kit"
  python3 "$GF" run --repo "$T/repo" >"$T/out" 2>&1
  echo $?
}
seen() { cat "$FAKE_JH" 2>/dev/null; }
seen_retry() { cat "$FAKE_RETRY_JH" 2>/dev/null; }

# a
unset JAVA_HOME
export DEVKIT_GATE_FULL_JDK_CANDIDATES="$T/nojdk:$T/jdk1:$T/jdk2"
rc=$(run_gf)
chk "a1. gate chạy xong (exit 0)" '[ "$rc" = 0 ]' "rc=$rc $(tail -5 "$T/out")"
chk "a2. JAVA_HOME trống ⇒ gate thấy JDK đầu tiên có bin/java" '[ "$(seen)" = "$T/jdk1" ]' "thấy '$(seen)'"

# b
export JAVA_HOME="$T/jdk2"
rc=$(run_gf)
chk "b1. JAVA_HOME dùng được ⇒ giữ nguyên" '[ "$rc" = 0 ] && [ "$(seen)" = "$T/jdk2" ]' "rc=$rc thấy '$(seen)'"

# c
export JAVA_HOME="$T/nojdk"
rc=$(run_gf)
chk "c1. JAVA_HOME hỏng (không bin/java) ⇒ thay bằng JDK ứng viên" '[ "$rc" = 0 ] && [ "$(seen)" = "$T/jdk1" ]' "rc=$rc thấy '$(seen)'"

# d
unset JAVA_HOME
export DEVKIT_GATE_FULL_JDK_CANDIDATES="$T/nojdk:$T/missing"
rc=$(run_gf)
chk "d1. không ứng viên dùng được ⇒ không bịa JAVA_HOME" '[ "$rc" = 0 ] && [ "$(seen)" = "<unset>" ]' "rc=$rc thấy '$(seen)'"

# e: suite đỏ ⇒ checks_fail chạy lại ở đỉnh và chia đôi cũng phải thấy JAVA_HOME ứng viên
printf 'c2\n' >"$T/seed/b.txt" && g -C "$T/seed" add -A && g -C "$T/seed" commit -qm second && g -C "$T/seed" push -q origin main:main
cat >"$T/retry_cmd.sh" <<'SH'
#!/bin/sh
printf '%s' "${JAVA_HOME-<unset>}" >"$FAKE_RETRY_JH"
exit 1
SH
chmod +x "$T/retry_cmd.sh"
cat >"$T/fakegate_red.sh" <<SH
#!/bin/sh
printf '%s' "\${JAVA_HOME-<unset>}" >"\$FAKE_JH"
echo '{"verdict": "FAIL", "exit_code": 1, "regression_tests": [{"id": "REG-FAKE-RED", "status": "FAIL", "command": "sh $T/retry_cmd.sh", "output": "✖ case1"}]}'
SH
chmod +x "$T/fakegate_red.sh"
unset JAVA_HOME
export DEVKIT_GATE_FULL_JDK_CANDIDATES="$T/jdk1" DEVKIT_GATE_FULL_CMD="sh $T/fakegate_red.sh" DEVKIT_GATE_FULL_BISECT=1
rc=$(run_gf)
chk "e1. checks_fail khi suite đỏ cũng thấy JAVA_HOME ứng viên" '[ "$(seen_retry)" = "$T/jdk1" ]' "rc=$rc thấy retry='$(seen_retry)'"

[ "$fails" = 0 ] && { echo "OK"; exit 0; }
echo "FAIL: $fails"
exit 1
