#!/usr/bin/env bash
# Test hồi quy (gate speed v26 mục 10): hai cần gạt chờ và độ rộng ở điểm gộp.
#   a  pool gate: DEVKIT_CAPACITY=0.5 (gate_max 1) ở ưu tiên merge ⇒ 2 slot; ưu tiên khác giữ 1; DEVKIT_GATE_SLOTS=1 tường minh giữ 1
#   b  merge gate opt_gate_slots (12 lõi, N = 2): tải 18 không hạn; tải 24 ⇒ N−1; SB_MERGE_OPT_LOAD_MAX vẫn ghi đè
#   c  opt_gate_slots: gate_max 1 và DEVKIT_GATE_SLOTS không đặt ⇒ sàn 2 ⇒ hạn N−1 = 1 khi tải cao; DEVKIT_GATE_SLOTS=1 ⇒ không hạn
#   d  .merge-scratch-*, sáu suite parallel_safe, s=0.75, 12 lõi, tải 0: chạy cùng lúc 6 (trước: 4); tải 30: 3 như cũ; ngoài điểm gộp: 4
#   e  biến độ rộng / slot của điểm gộp không lọt vào môi trường suite
#   f  guard có hạn giờ (REG-DK-SESSION-01) ở điểm gộp: chạy sau cùng, một mình
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI FLAKY_RETRY DEVKIT_GATE_PARALLEL DEVKIT_GATE_DONE DEVKIT_IMPACT_TEST_CHANGED DEVKIT_IMPACTED_SINCE \
      DEVKIT_IMPACTED_DIRS DEVKIT_SCOPED_TESTS DEVKIT_SCOPED_NO_CONSISTENCY DEVKIT_SLOT_PRIORITY GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK DEVKIT_PER_TEST_CACHE \
      POSTFIX_GATE_FULL POSTFIX_GATE_FORCE_FULL DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_GATE_SLOTS \
      DEVKIT_CAPACITY DEVKIT_CAPACITY_CORES DEVKIT_CAPACITY_LOAD DEVKIT_MERGE_PARALLEL DEVKIT_MERGE_WIDE_LOAD_MAX DEVKIT_MERGE_GATE_SLOTS SB_MERGE_OPT_LOAD_MAX
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="$(cd "$DEVKIT_DIR/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
MG="$ROOT/.claude/bin/super-board-merge-gate.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots" SB_HEAVY_SLOT_POLL_S=0.1 DEVKIT_SLOT_LOAD_FILE="$TMP/zero"; mkdir -p "$SB_HEAVY_SLOT_DIR"; echo 0 > "$TMP/zero"
export DEVKIT_MERGE_POINT=1   # at_merge_point cần dấu này (merge gate / train / integrate đặt) cùng đường dẫn .merge-scratch-*
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# a
A="$(DEVKIT_CAPACITY=0.5 DEVKIT_CAPACITY_CORES=12 DEVKIT_CAPACITY_LOAD=0 python3 - "$GATE" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("pfg_w", sys.argv[1]); m = importlib.util.module_from_spec(spec)
sys.modules["pfg_w"] = m; spec.loader.exec_module(m)
os.environ["DEVKIT_SLOT_PRIORITY"] = "merge"; a = m.default_gate_slots()
os.environ["DEVKIT_SLOT_PRIORITY"] = "task"; b = m.default_gate_slots()
os.environ["DEVKIT_SLOT_PRIORITY"] = "merge"; os.environ["DEVKIT_GATE_SLOTS"] = "1"; c = m.default_gate_slots()
print(a, b, c)
PY
)"
[ "$A" = "2 1 1" ] && ok "a. s=0.5: merge 2 slot, ưu tiên khác 1, DEVKIT_GATE_SLOTS=1 giữ 1" || fail "a. merge/task/explicit = $A (muốn 2 1 1)"

# b, c: thân opt_gate_slots + load_now của merge gate, capacity giả
awk '/^load_now\(\) \{/,/^\}/' "$MG" > "$TMP/fn.sh"; awk '/^opt_gate_slots\(\) \{/,/^\}/' "$MG" >> "$TMP/fn.sh"
printf '#!/usr/bin/env bash\ncase "$1" in cores) echo 12 ;; gate_max) cat "%s/gmax" ;; esac\n' "$TMP" > "$TMP/cap"; chmod +x "$TMP/cap"
opt() {   # opt <load> <gate_max> [VAR=giá trị…] → OPT_SLOTS
  echo "$1" > "$TMP/mload"; echo "$2" > "$TMP/gmax"; shift 2
  env "$@" SB_CAPACITY="$TMP/cap" SB_MERGE_LOAD_FILE="$TMP/mload" LOCK_HELD=0 HERE=/nonexistent bash -c '. "$1"; opt_gate_slots; echo "[${OPT_SLOTS}]"' _ "$TMP/fn.sh"
}
[ "$(opt 18 2)" = "[]" ] && ok "b. tải 18 < 2 × 12: không hạn" || fail "b. tải 18: $(opt 18 2)"
[ "$(opt 24 2)" = "[1]" ] && ok "b. tải 24: N−1 = 1" || fail "b. tải 24: $(opt 24 2)"
[ "$(opt 18 2 SB_MERGE_OPT_LOAD_MAX=12)" = "[1]" ] && ok "b. SB_MERGE_OPT_LOAD_MAX ghi đè" || fail "b. ghi đè: $(opt 18 2 SB_MERGE_OPT_LOAD_MAX=12)"
[ "$(opt 30 1)" = "[1]" ] && ok "c. gate_max 1: sàn 2 ⇒ N−1 = 1" || fail "c. sàn: $(opt 30 1)"
[ "$(opt 30 1 DEVKIT_GATE_SLOTS=1)" = "[]" ] && ok "c. DEVKIT_GATE_SLOTS=1 tường minh: không hạn" || fail "c. tường minh: $(opt 30 1 DEVKIT_GATE_SLOTS=1)"

# d, e, f: gate thật trong repo nháp
new_repo() {   # $1 = repo, $2 = 1: thêm guard REG-DK-SESSION-01
  local R="$1" KIT="$1/universal-agent-devkit" i
  mkdir -p "$KIT/tests/lib" "$R/.agents" "$R/app"
  git -C "$R" init -q -b main . && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  ln -s "$DEVKIT_DIR/bin" "$KIT/bin"
  echo 'print(1)' > "$R/app/x.py"
  # suite ghi số đang chạy cùng lúc (max vào max.<lượt>), giữ 2 s, ghi biến môi trường của điểm gộp nó thấy
  cat > "$R/app/rec.sh" <<SH
d="$TMP/run"; mkdir -p "\$d"; touch "\$d/\$1"
n=\$(ls "\$d" | wc -l | tr -d ' '); echo "\$n" >> "$TMP/conc"
echo "\${DEVKIT_MERGE_PARALLEL-unset} \${DEVKIT_MERGE_WIDE_LOAD_MAX-unset} \${DEVKIT_MERGE_GATE_SLOTS-unset}" >> "$TMP/env"
echo "\$1" >> "$TMP/order"
sleep 2; rm -f "\$d/\$1"
SH
  printf '.claude/audit-gate/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n' > "$R/.gitignore"
  echo '{"profile":"backend"}' > "$R/.agents/active-profile.json"
  printf '[core]\n.agents/gate-core.txt\n' > "$R/.agents/gate-core.txt"
  [ "${2:-0}" = 1 ] && printf '\n[merge-guard]\nREG-DK-SESSION-01\n' >> "$R/.agents/gate-core.txt"
  python3 - "$R/.agents/regression_matrix.active.json" <<'PY'
import json, sys
tests = [{"id": "REG-S%d" % i, "name": "s%d" % i, "command": "bash app/rec.sh s%d" % i, "parallel_safe": True} for i in range(1, 7)]
json.dump({"project": "t", "rules": [{"component": "app", "watch_files": ["app/x.py"], "mandatory_regression_tests": tests},
    {"component": "sess", "watch_files": ["nothing/*"], "mandatory_regression_tests": [
        {"id": "REG-DK-SESSION-01", "name": "session", "command": "bash app/rec.sh sess", "parallel_safe": True}]}]}, open(sys.argv[1], "w"))
PY
  git -C "$R" add -A && git -C "$R" commit -qm init && git -C "$R" checkout -q -b f
  echo 'print(2)' > "$R/app/x.py"; git -C "$R" commit -qam e
}
gate() {   # gate <repo> <tải> [VAR=giá trị…]
  local R="$1" L="$2"; shift 2
  rm -rf "$TMP/run" "$TMP/conc" "$TMP/env" "$TMP/order"
  ( cd "$R" && env "$@" DEVKIT_CAPACITY=0.75 DEVKIT_CAPACITY_CORES=12 DEVKIT_CAPACITY_LOAD="$L" FLAKY_RETRY=0 VACUITY_REVERT=0 CLAUDE_PROJECT_DIR="$R" \
      python3 "$GATE" --run-tests --no-checklist --no-cache --scoped --diff main >"$TMP/out" 2>&1 ); RC=$?
}
maxc() { sort -n "$TMP/conc" 2>/dev/null | tail -1; }

R="$TMP/.merge-scratch-d"; new_repo "$R"
gate "$R" 0
[ "$RC" -eq 0 ] && [ "$(maxc)" = 6 ] && ok "d. điểm gộp, tải 0: 6 suite cùng lúc" || { fail "d. tải 0: rc=$RC cùng lúc=$(maxc) (muốn 6)"; tail -8 "$TMP/out"; }
gate "$R" 30
[ "$RC" -eq 0 ] && [ "$(maxc)" = 3 ] && ok "d. điểm gộp, tải 30 ≥ 24: 3 như cũ" || { fail "d. tải 30: rc=$RC cùng lúc=$(maxc) (muốn 3)"; tail -8 "$TMP/out"; }
gate "$R" 0 DEVKIT_MERGE_PARALLEL=6 DEVKIT_MERGE_WIDE_LOAD_MAX=24 DEVKIT_MERGE_GATE_SLOTS=2
[ "$(sort -u "$TMP/env")" = "unset unset unset" ] && ok "e. suite không thấy biến của điểm gộp" || fail "e. suite thấy: $(sort -u "$TMP/env" | tr '\n' ';')"
R="$TMP/plain-d"; new_repo "$R"
gate "$R" 0
[ "$RC" -eq 0 ] && [ "$(maxc)" = 4 ] && ok "d. ngoài điểm gộp: 4 như cũ" || { fail "d. ngoài điểm gộp: rc=$RC cùng lúc=$(maxc) (muốn 4)"; tail -8 "$TMP/out"; }

R="$TMP/.merge-scratch-f"; new_repo "$R" 1
gate "$R" 0
LAST="$(tail -1 "$TMP/order" 2>/dev/null)"
[ "$RC" -eq 0 ] && [ "$LAST" = sess ] && [ "$(tail -1 "$TMP/conc")" = 1 ] && ok "f. guard có hạn giờ chạy sau cùng, một mình" \
  || { fail "f. rc=$RC cuối=$LAST cùng lúc lúc đó=$(tail -1 "$TMP/conc" 2>/dev/null)"; tail -8 "$TMP/out"; }

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "failures: $FAILS"; exit 1
