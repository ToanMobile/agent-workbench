#!/usr/bin/env bash
# Test hồi quy (gate speed v26, lane D2, review mới): các ca ở ranh giới chọn suite của post-fix-gate.py / scoped_gate.py.
#   g1  điểm gộp, PR xoá id khỏi [merge-guard], `rev-parse <base>^{commit}` hỏng: base của guard vẫn phân giải (merge-base), guard vẫn chạy
#   g2  như g1 mà cả merge-base cũng hỏng: fail closed, suite đỏ "merge-guard: base không phân giải", exit 1
#   q   id [merge-guard] thiếu trong ma trận chứa ký tự shell: lệnh đỏ không chạy chuỗi đó như lệnh (shlex.quote)
#   p1  DEVKIT_PRECOMMIT_TESTS=1 chạy như light
#   p2  giá trị lạ (DEVKIT_PRECOMMIT_TESTS=bogus): không chạy suite, có cảnh báo nêu giá trị
#   d   nhánh `skipped` thêm [core-smoke] sau cap: suite cap đã hoãn mà nay chạy thì không còn trong deferred_to_heavy.suites của biên nhận
#   s   scoped_gate.cap_selection không còn tham số `guards` (không ai truyền)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI FLAKY_RETRY DEVKIT_GATE_PARALLEL DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE \
      DEVKIT_IMPACTED_DIRS DEVKIT_SCOPED_TESTS DEVKIT_SCOPED_NO_CONSISTENCY DEVKIT_SLOT_PRIORITY GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK DEVKIT_PER_TEST_CACHE \
      POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_PRECOMMIT_TESTS \
      DEVKIT_LEDGER_ROOT
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1; mkdir -p "$SB_HEAVY_SLOT_DIR"
export DEVKIT_MERGE_POINT=1   # at_merge_point cần dấu này (merge gate / train / integrate đặt) cùng đường dẫn .merge-scratch-*
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# git giả: chặn `rev-parse … <BLOCK>^{commit}` (và `merge-base … <BLOCK> …` khi BLOCK_MB=1), còn lại gọi git thật
REAL_GIT="$(command -v git)"; mkdir -p "$TMP/shim"
cat > "$TMP/shim/git" <<SH
#!/usr/bin/env bash
if [ -n "\${BLOCK:-}" ]; then
  mb=0; hit=0
  for a in "\$@"; do
    [ "\$a" = merge-base ] && mb=1
    [ "\$a" = "\${BLOCK}^{commit}" ] && exit 1
    [ "\$a" = "\$BLOCK" ] && hit=1
  done
  [ "\${BLOCK_MB:-0}" = 1 ] && [ \$mb = 1 ] && [ \$hit = 1 ] && exit 1
fi
exec "$REAL_GIT" "\$@"
SH
chmod +x "$TMP/shim/git"

new_repo() {   # $1 = thư mục repo; $2 = danh sách id [merge-guard]; $3 = mục [core-smoke] (tuỳ chọn)
  local R="$1" KIT="$1/universal-agent-devkit"
  mkdir -p "$KIT/tests/gates" "$KIT/tests/verification" "$KIT/tests/lib" "$KIT/lib" "$R/.agents" "$R/docs" "$R/app"
  git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  cp "$DEVKIT_DIR/tests/run_impacted.sh" "$KIT/tests/run_impacted.sh"; echo '# trống' > "$KIT/tests/impact_map.txt"
  cp "$DEVKIT_DIR/tests/lib/per_test_cache.py" "$DEVKIT_DIR/tests/lib/run_bounded.py" "$KIT/tests/lib/"
  ln -s "$DEVKIT_DIR/bin" "$KIT/bin"
  echo true > "$KIT/tests/verification/test_repo_consistency.sh"
  printf 'echo x >> %s/ran.guard\n' "$TMP" > "$KIT/tests/gates/test_guard.sh"
  printf 'DK="$(cd "$(dirname "$0")/../.." && pwd)"\ngrep -q v "$DK/lib/shared.txt" || exit 1\necho x >> %s/ran.smoke\n' "$TMP" > "$KIT/tests/gates/test_smoke.sh"
  echo v1 > "$KIT/lib/shared.txt"
  echo '# docs' > "$R/docs/a.md"
  echo 'V = 1' > "$R/app/widget.py"; mkdir -p "$R/tests"
  printf 'from app import widget\ndef test_w(): assert widget.V\n' > "$R/tests/test_widget.py"
  printf '.claude/audit-gate/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n' > "$R/.gitignore"
  echo '{"profile":"backend"}' > "$R/.agents/active-profile.json"
  printf '[core]\n.agents/gate-core.txt\n\n[merge-guard]\n# guard\n' > "$R/.agents/gate-core.txt"
  for g in $2; do echo "$g" >> "$R/.agents/gate-core.txt"; done
  [ -n "${3:-}" ] && printf '\n[core-smoke]\n%s\n' "$3" >> "$R/.agents/gate-core.txt"
  python3 - "$R/.agents/regression_matrix.active.json" <<'PY'
import json, sys
json.dump({"project": "t", "rules": [
    {"component": "guard", "watch_files": ["docs/never/*"],
     "mandatory_regression_tests": [{"id": "REG-G1", "name": "guard", "command": "bash universal-agent-devkit/tests/gates/test_guard.sh", "parallel_safe": True}]},
    {"component": "kit", "watch_files": ["universal-agent-devkit/lib/*"],
     "mandatory_regression_tests": [{"id": "REG-DK-ALL-KIT-01", "name": "kit", "command": "bash universal-agent-devkit/tests/run_impacted.sh", "parallel_safe": True}]},
    {"component": "app", "watch_files": ["app/*"],
     "mandatory_regression_tests": [{"id": "REG-APP", "name": "app", "command": "true", "parallel_safe": True}]}]},
    open(sys.argv[1], "w"))
PY
  git -C "$R" add -A && git -C "$R" commit -qm init && git -C "$R" checkout -q -b f
}
gate() { local R="$1"; ( cd "$R" && FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --no-checklist --json --scoped --diff main >"$TMP/out" 2>&1 ); RC=$?; }
nfile() { if [ -f "$TMP/$1" ]; then wc -l < "$TMP/$1" | tr -d ' '; else echo 0; fi; }
drop_guard() { python3 -c 'import sys; p=sys.argv[1]; s=open(p).read().replace("REG-G1\n", ""); open(p, "w").write(s)' "$1/.agents/gate-core.txt"; }

# g1, g2: PR xoá REG-G1 khỏi [merge-guard] (base còn), base không rev-parse được
for c in g1 g2; do
  R="$TMP/.merge-scratch-$c"; new_repo "$R" "REG-G1"; drop_guard "$R"; echo '# đổi' >> "$R/docs/a.md"; git -C "$R" commit -qam e
  B="$(git -C "$R" rev-parse main)"; rm -f "$TMP/ran.guard"
  if [ "$c" = g1 ]; then PATH="$TMP/shim:$PATH" BLOCK="$B" gate "$R"; else PATH="$TMP/shim:$PATH" BLOCK="$B" BLOCK_MB=1 gate "$R"; fi
  if [ "$c" = g1 ]; then
    [ "$(nfile ran.guard)" = 1 ] && ok "g1. rev-parse base hỏng: base guard lấy từ merge-base, guard vẫn chạy (rc=$RC)" \
      || { fail "g1. rc=$RC guard=$(nfile ran.guard) (mong guard chạy 1 lần)"; LC_ALL=C grep -a "merge-guard" "$TMP/out" | head -3; }
  else
    [ "$RC" = 1 ] && LC_ALL=C grep -aq "merge-guard: base không phân giải" "$TMP/out" \
      && ok "g2. base không phân giải được: suite đỏ, exit 1" \
      || { fail "g2. rc=$RC guard=$(nfile ran.guard) (mong exit 1, 'merge-guard: base không phân giải')"; LC_ALL=C grep -a "merge-guard" "$TMP/out" | head -3; }
  fi
done

# q: id thiếu trong ma trận mang ký tự shell
R="$TMP/.merge-scratch-q"; new_repo "$R" "REG-G1"
python3 - "$R/.agents/gate-core.txt" "$TMP/pwned" <<'PY'
import sys
open(sys.argv[1], "a").write("REG-Q';touch${IFS}%s;'\n" % sys.argv[2])
PY
echo '# đổi' >> "$R/docs/a.md"; git -C "$R" commit -qam e
gate "$R"
[ "$RC" = 1 ] && [ ! -e "$TMP/pwned" ] && LC_ALL=C grep -aq "REG-Q" "$TMP/out" \
  && ok "q. id có ký tự shell: chỉ in ra, không chạy, exit 1" || fail "q. rc=$RC pwned=$([ -e "$TMP/pwned" ] && echo có || echo không)"

# p1, p2: DEVKIT_PRECOMMIT_TESTS
P="$TMP/p"; git init -q -b main "$P" || exit 1
( cd "$P" && git config user.email t@t && git config user.name t && mkdir -p src .agents
  echo "def ok(): return 1" > src/core.py
  echo '{"profile":"backend"}' > .agents/active-profile.json
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"echo x >> marker.txt"}]}]}\n' \
    > .agents/regression_matrix.active.json
  printf 'marker.txt\n.claude/\n' > .gitignore
  git add -A && git commit -qm init && echo "def ok(): return 2" > src/core.py && git add src/core.py ) || exit 1
staged() { rm -f "$P/marker.txt"; ( cd "$P" && python3 "$GATE" --staged ) >"$TMP/pout" 2>&1; }
DEVKIT_PRECOMMIT_TESTS=1 staged
[ -s "$P/marker.txt" ] && ok "p1. =1 chạy như light" || fail "p1. =1 không chạy suite"
DEVKIT_PRECOMMIT_TESTS=bogus staged
[ ! -s "$P/marker.txt" ] && LC_ALL=C grep -aq "DEVKIT_PRECOMMIT_TESTS=bogus" "$TMP/pout" \
  && ok "p2. giá trị lạ: không chạy, có cảnh báo nêu giá trị" || fail "p2. ran=$([ -s "$P/marker.txt" ] && echo 1 || echo 0) $(LC_ALL=C grep -a PRECOMMIT "$TMP/pout" | head -2)"
DEVKIT_PRECOMMIT_TESTS=0 staged
[ ! -s "$P/marker.txt" ] && ! LC_ALL=C grep -aq "DEVKIT_PRECOMMIT_TESTS=0" "$TMP/pout" \
  && ok "p3. =0 (mặc định của hook): không chạy, không cảnh báo" || fail "p3. =0 chạy hoặc cảnh báo"

# d: test py không luật nào chạy được (skipped) ⇒ [core-smoke] thêm sau cap; runner kit bị cap hoãn nay chạy test smoke
R="$TMP/d"; new_repo "$R" "" "universal-agent-devkit/tests/gates/test_smoke.sh"
echo '# notes' > "$R/universal-agent-devkit/lib/notes.md"; echo 'V = 2' > "$R/app/widget.py"; git -C "$R" add -A; git -C "$R" commit -qm e
rm -f "$TMP/ran.smoke"; gate "$R"
D="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join(d["deferred_to_heavy"]["suites"]))' "$R/.git/postfix-gate/scoped_pass.json" 2>/dev/null)" \
  || D="(không có biên nhận)"
if [ "$(nfile ran.smoke)" != 1 ] || [ "$RC" != 0 ] || ! LC_ALL=C grep -aq "tests/test_widget.py" "$TMP/out"; then
  fail "d. tiền đề: lượt --scoped exit 0, test py bị bỏ qua, [core-smoke] chạy (rc=$RC smoke=$(nfile ran.smoke))"
  LC_ALL=C grep -aE "core-smoke|deferred|scoped|KẾT LUẬN" "$TMP/out" | head -6 | cut -c1-200
elif [ "$D" = "(không có biên nhận)" ]; then fail "d. không đọc được biên nhận scoped"
else case " $D " in *" REG-DK-ALL-KIT-01 "*) fail "d. runner đã chạy mà vẫn nằm trong deferred_to_heavy.suites: $D" ;;
  *) ok "d. runner chạy [core-smoke] không còn trong deferred_to_heavy.suites ($D)" ;; esac; fi

# s
S="$(python3 -c 'import inspect, sys; sys.path.insert(0, sys.argv[1]); import scoped_gate as g; print("guards" in inspect.signature(g.cap_selection).parameters)' "$DEVKIT_DIR/bin" 2>&1)"
[ "$S" = False ] && ok "s. cap_selection không còn tham số guards" || fail "s. guards còn: $S"

echo
[ "$FAILS" -eq 0 ] && { echo "test_gate_review_d2: PASS"; exit 0; }
echo "test_gate_review_d2: FAIL ($FAILS)"; exit 1
