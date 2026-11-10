#!/usr/bin/env bash
# Test hồi quy (gate speed v14, mục 2 phần PFG): run_precommit_tests chỉ chạy suite ở DEVKIT_PRECOMMIT_TESTS=light / all; biến vắng (người gọi trực tiếp
# --staged, không qua git-pre-commit.sh) vẫn là light; =1 là light; giá trị khác không chạy gì. Lời gate không còn nói Stop chạy suite, không nói "KHÔNG chạy" khi suite nhẹ đã chạy.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_PRECOMMIT_TESTS DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS GATE_TOTAL_BUDGET_S
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/r"; git init -q -b main "$R" || exit 1
( cd "$R" && git config user.email t@t && git config user.name t && mkdir -p src .agents
  echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> marker.txt"},
                               {"id":"REG-SLOW","name":"gradle","command":"./gradlew test || true"}]}]}
JSON
  printf 'marker.txt\n.claude/\n' > .gitignore
  git add -A && git commit -qm init
  echo "def ok(): return 2" > src/core.py && git add src/core.py ) || exit 1

staged() { rm -f "$R/marker.txt"; ( cd "$R" && python3 "$GATE" --staged ) >"$TMP/out" 2>&1; }
ran() { [ -s "$R/marker.txt" ]; }

staged; ran && ok "biến vắng: fallback light chạy suite nhẹ" || { fail "biến vắng không chạy"; tail -20 "$TMP/out"; }
DEVKIT_PRECOMMIT_TESTS=light staged; ran && ok "light chạy" || fail "light không chạy"
DEVKIT_PRECOMMIT_TESTS=all staged; ran && ok "all chạy" || fail "all không chạy"
DEVKIT_PRECOMMIT_TESTS=0 staged; ran && fail "0 vẫn chạy" || ok "0 không chạy"
DEVKIT_PRECOMMIT_TESTS=off staged; ran && fail "giá trị lạ vẫn chạy suite" || ok "giá trị lạ không chạy suite"
DEVKIT_PRECOMMIT_TESTS=1 staged; ran && ok "=1 chạy như light (lane D2)" || fail "=1 không chạy suite"

staged
if LC_ALL=C grep -aqE "cổng Stop|Stop gate|the Stop" "$TMP/out"; then fail "lời bỏ qua suite vẫn nói Stop chạy: $(LC_ALL=C grep -aE 'cổng Stop|Stop gate' "$TMP/out" | cut -c1-160)"; else ok "lời bỏ qua suite không nhắc Stop"; fi
if LC_ALL=C grep -aqE "KHÔNG chạy ở pre-commit|NOT run in pre-commit" "$TMP/out"; then fail "kết luận nói KHÔNG chạy trong khi suite nhẹ đã chạy"; else ok "kết luận không phủ nhận suite nhẹ đã chạy"; fi
LC_ALL=C grep -aqE "TĨNH SẠCH|STATIC CLEAN" "$TMP/out" && ok "kết luận vẫn là TĨNH SẠCH" || fail "mất TĨNH SẠCH"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "failures: $FAILS"; exit 1
