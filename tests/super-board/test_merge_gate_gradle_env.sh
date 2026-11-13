#!/usr/bin/env bash
# #969 (REG-GATE-118 của GeelyEx2): merge gate chỉ ghim GRADLE_USER_HOME + daemon khi scratch là project Gradle
# (gradlew / settings.gradle[.kts] ở gốc hoặc lồng ≤3 cấp, như GeelyEx2: PhoneConnect/gradlew);
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

# Lấy đúng hàm phát hiện Gradle và thân run_verify_cmd_inner của gate.
awk '/^scratch_uses_gradle\(\) \{/{p=1} p{print} p&&/^\}/{exit}' "$GATE" > "$TMP/fn.sh"
awk '/^run_verify_cmd_inner\(\) \{/{p=1} p{print} p&&/^\}/{exit}' "$GATE" > "$TMP/inner.sh"
if [ ! -s "$TMP/fn.sh" ]; then fail "gate không có scratch_uses_gradle"; echo "FAILS=$FAILS"; exit 1; fi

det() { ( SCRATCH="$1"; . "$TMP/fn.sh"; scratch_uses_gradle && echo yes || echo no ); }
mkdir -p "$TMP/g" "$TMP/n" "$TMP/home" "$TMP/nested/PhoneConnect" "$TMP/kts" "$TMP/deep/a/b/c/d" "$TMP/nm/node_modules/x"
: > "$TMP/g/gradlew"; : > "$TMP/nested/PhoneConnect/gradlew"; : > "$TMP/kts/settings.gradle.kts"
: > "$TMP/deep/a/b/c/d/gradlew"; : > "$TMP/nm/node_modules/x/gradlew"

[ "$(det "$TMP/g")" = yes ] && ok "gradlew ở gốc: là Gradle" || fail "gradlew gốc không nhận"
[ "$(det "$TMP/nested")" = yes ] && ok "gradlew lồng (GeelyEx2: PhoneConnect/gradlew): là Gradle" || fail "gradlew lồng không nhận (R2)"
[ "$(det "$TMP/kts")" = yes ] && ok "settings.gradle.kts: là Gradle" || fail "settings.gradle.kts không nhận"
[ "$(det "$TMP/n")" = no ] && ok "không dấu Gradle: không ghim" || fail "repo không Gradle bị nhận nhầm"
[ "$(det "$TMP/deep")" = no ] && ok "quá sâu (>3 cấp): bỏ qua" || fail "quét quá sâu"
[ "$(det "$TMP/nm")" = no ] && ok "node_modules bị bỏ qua" || fail "node_modules bị quét"

# Oracle REG-GATE-118 của GeelyEx2: hai export nằm NGUYÊN VĂN trong thân run_verify_cmd_inner, trước post-fix-gate.py.
EXPORT_HOME='export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"'
EXPORT_DAEMON='[[ "${GRADLE_OPTS:-}" == *"-Dorg.gradle.daemon=true"* ]] || export GRADLE_OPTS="${GRADLE_OPTS:+$GRADLE_OPTS }-Dorg.gradle.daemon=true"'
grep -qF -- "$EXPORT_HOME" "$TMP/inner.sh" && ok "run_verify_cmd_inner có export GRADLE_USER_HOME nguyên văn" || fail "thiếu export HOME trong run_verify_cmd_inner"
grep -qF -- "$EXPORT_DAEMON" "$TMP/inner.sh" && ok "run_verify_cmd_inner có export daemon nguyên văn" || fail "thiếu export daemon trong run_verify_cmd_inner"
h=$(grep -n 'GRADLE_USER_HOME' "$TMP/inner.sh" | head -1 | cut -d: -f1); g=$(grep -n 'post-fix-gate.py' "$TMP/inner.sh" | head -1 | cut -d: -f1)
[ -n "$h" ] && [ -n "$g" ] && [ "$h" -lt "$g" ] && ok "export đứng trước post-fix-gate.py" || fail "export không đứng trước post-fix-gate.py"
grep -q 'scratch_uses_gradle' "$TMP/inner.sh" && ok "export có điều kiện scratch_uses_gradle" || fail "export không có điều kiện Gradle"
# Hành vi thật: chạy đúng khối if..fi của thân hàm.
blk="$(awk '/if scratch_uses_gradle/{p=1} p{print} p&&/^  fi/{exit}' "$TMP/inner.sh")"
run() { ( unset GRADLE_USER_HOME GRADLE_OPTS; [ -n "${2:-}" ] && export GRADLE_OPTS="$2"
    export HOME="$TMP/home"; SCRATCH="$1"; . "$TMP/fn.sh"; eval "$blk"; printf '%s|%s' "${GRADLE_USER_HOME:-}" "${GRADLE_OPTS:-}" ); }
out="$(run "$TMP/nested" "")"
[ "$out" = "$TMP/home/.gradle|-Dorg.gradle.daemon=true" ] && ok "Gradle lồng: HOME + daemon được ghim" || fail "Gradle lồng: got '$out'"
out="$(run "$TMP/g" "-Xmx1g")"
[ "$out" = "$TMP/home/.gradle|-Xmx1g -Dorg.gradle.daemon=true" ] && ok "Gradle: nối vào GRADLE_OPTS cũ" || fail "Gradle opts: got '$out'"
out="$(run "$TMP/g" "-Dorg.gradle.daemon=true")"
[ "$out" = "$TMP/home/.gradle|-Dorg.gradle.daemon=true" ] && ok "Gradle: không nhân đôi cờ daemon" || fail "Gradle dup: got '$out'"
out="$(run "$TMP/n" "")"
[ "$out" = "|" ] && ok "không Gradle: môi trường nguyên vẹn" || fail "non-Gradle: got '$out'"
grep -q 'SB_BASE_SUITE_TIMEOUT_S") or 900' "$GATE" && ok "timeout mặc định vẫn 900" || fail "timeout 900 mất"
grep -q -- '--no-daemon' "$TMP/inner.sh" && fail "run_verify_cmd_inner có --no-daemon" || ok "không --no-daemon"
[ "$FAILS" -eq 0 ] && echo "PASS" && exit 0
echo "FAILS=$FAILS"; exit 1
