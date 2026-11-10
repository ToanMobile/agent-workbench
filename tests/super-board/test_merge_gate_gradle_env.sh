#!/usr/bin/env bash
# #969 (REG-GATE-118 của GeelyEx2): merge gate chỉ ghim GRADLE_USER_HOME + daemon khi scratch có gradlew;
# repo không Gradle giữ nguyên môi trường; trần timeout suite nền vẫn 900 (SB_BASE_SUITE_TIMEOUT_S).
# SB_GATE=<file> chạy bản cũ để thấy ĐỎ. Offline, bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${SB_GATE:-$ROOT/.claude/bin/super-board-merge-gate.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-gradle-env.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Lấy đúng hàm của gate (từ dòng khai báo đến dấu } đầu dòng).
awk '/^gradle_env_for_verify\(\) \{/{p=1} p{print} p&&/^\}/{exit}' "$GATE" > "$TMP/fn.sh"
if [ ! -s "$TMP/fn.sh" ]; then fail "gate không có gradle_env_for_verify"; echo "FAILS=$FAILS"; exit 1; fi

run() { # $1 = scratch dir, $2 = GRADLE_OPTS đầu vào; in "HOME|OPTS"
  ( unset GRADLE_USER_HOME GRADLE_OPTS; [ -n "${2:-}" ] && export GRADLE_OPTS="$2"
    export HOME="$TMP/home"; SCRATCH="$1"; . "$TMP/fn.sh"; gradle_env_for_verify
    printf '%s|%s' "${GRADLE_USER_HOME:-}" "${GRADLE_OPTS:-}" )
}
mkdir -p "$TMP/g" "$TMP/n" "$TMP/home"; : > "$TMP/g/gradlew"

out="$(run "$TMP/g" "")"
[ "$out" = "$TMP/home/.gradle|-Dorg.gradle.daemon=true" ] && ok "Gradle: HOME + daemon được ghim" || fail "Gradle: got '$out'"
out="$(run "$TMP/g" "-Xmx1g")"
[ "$out" = "$TMP/home/.gradle|-Xmx1g -Dorg.gradle.daemon=true" ] && ok "Gradle: nối vào GRADLE_OPTS cũ" || fail "Gradle opts: got '$out'"
out="$(run "$TMP/g" "-Dorg.gradle.daemon=true")"
[ "$out" = "$TMP/home/.gradle|-Dorg.gradle.daemon=true" ] && ok "Gradle: không nhân đôi cờ daemon" || fail "Gradle dup: got '$out'"
out="$(run "$TMP/n" "")"
[ "$out" = "|" ] && ok "không gradlew: môi trường nguyên vẹn" || fail "non-Gradle: got '$out'"
grep -q 'gradle_env_for_verify$' <(awk '/^run_verify_cmd_inner\(\) \{/{p=1} p{print} p&&/^\}/{exit}' "$GATE") \
  && ok "run_verify_cmd_inner gọi gradle_env_for_verify" || fail "run_verify_cmd_inner không gọi hàm"
grep -q 'SB_BASE_SUITE_TIMEOUT_S") or 900' "$GATE" && ok "timeout mặc định vẫn 900" || fail "timeout 900 mất"
grep -q -- '--no-daemon' "$TMP/fn.sh" && fail "hàm có --no-daemon" || ok "không --no-daemon"
[ "$FAILS" -eq 0 ] && echo "PASS" && exit 0
echo "FAILS=$FAILS"; exit 1
