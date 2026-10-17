#!/usr/bin/env bash
# K8 (17/10, Neighbours-From-Hell, Unity): 6 agent cùng `worktree finish`, 6 gate gộp (biên dịch + EditMode + PlayMode) chạy song song, tải máy
# 100–187 trên 12 nhân, test timeout thành FAIL; agent A2 phải finish 7 lần. Nay gate gộp của CÙNG một repo chạy lần lượt: khoá
# `devkit-merge-gate.lock` trong git dir của main, giữ từ trước gate tới sau fast-forward (người chờ thấy main mới, gộp nó rồi gate MỘT lần).
#   1 hai finish song song: hai gate không bao giờ chồng nhau, mỗi worktree chỉ chạy suite đúng 1 lần, cả hai đều vào main
#   2 khoá bị giữ lâu hơn WORKTREE_MERGE_GATE_LOCK_WAIT_S: từ chối nhanh ("running", không "moved"), main đứng yên, không chạy suite
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; HOLDER=""; trap '[ -n "$HOLDER" ] && kill "$HOLDER" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
export GIT_CONFIG_GLOBAL=/dev/null

repo() {   # check.sh = suite của ma trận: ghi worktree đang chạy, dò chồng nhau bằng mkdir, chạy 3 s
  local p="$TMP/$1"; mkdir -p "$p/.agents" && G "$p" init -q -b main . && G "$p" config user.email t@t && G "$p" config user.name t
  printf 'echo ok\n' > "$p/app.sh"
  printf '[ -n "${GATE_RUNS:-}" ] && basename "$(pwd -P)" >> "$GATE_RUNS"\nif [ -n "${PROBE:-}" ]; then mkdir "$PROBE" 2>/dev/null || echo overlap >> "$PROBE.overlap"; sleep 3; rmdir "$PROBE" 2>/dev/null; fi\necho "all apps ok"\n' > "$p/check.sh"
  printf '{"project":"t","rules":[{"component":"App","watch_files":["*.sh"],"mandatory_regression_tests":[{"id":"REG-APP-01","name":"check","command":"bash check.sh"}]}]}\n' \
    > "$p/.agents/regression_matrix.active.json"
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/evidence/\n.agents/regression_journal/\n.claude/\n' > "$p/.gitignore"
  G "$p" add -A && G "$p" commit -qm base
}
work() {   # work <repo> <worktree> <file>: worktree mới, commit một file *.sh (suite theo dõi)
  (cd "$TMP/$1" && python3 "$WT" add "$TMP/$2" --no-init >/dev/null 2>&1) || fail "setup: worktree add $2"
  echo "echo ok" > "$TMP/$2/$3" && G "$TMP/$2" add "$3" && G "$TMP/$2" commit -qm "work $3"
}

# 1 hai finish song song trên hai worktree của cùng repo
repo a; work a a-w1 app2.sh; work a a-w2 app3.sh; : > "$TMP/runs"
(cd "$TMP/a" && env GATE_RUNS="$TMP/runs" PROBE="$TMP/probe" WORKTREE_FINISH_RETRIES=0 python3 "$WT" finish "$TMP/a-w1" > "$TMP/out1" 2>&1) & p1=$!
(cd "$TMP/a" && env GATE_RUNS="$TMP/runs" PROBE="$TMP/probe" WORKTREE_FINISH_RETRIES=0 python3 "$WT" finish "$TMP/a-w2" > "$TMP/out2" 2>&1) & p2=$!
wait "$p1"; rc1=$?; wait "$p2"; rc2=$?
r1="$(grep -cx "a-w1" "$TMP/runs")"; r2="$(grep -cx "a-w2" "$TMP/runs")"
[ ! -f "$TMP/probe.overlap" ] && ok "1 hai finish song song: hai gate không chạy chồng nhau" || fail "1 hai gate chạy chồng nhau ($(wc -l < "$TMP/probe.overlap" | tr -d ' ') lần)"
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ -f "$TMP/a/app2.sh" ] && [ -f "$TMP/a/app3.sh" ] && [ ! -d "$TMP/a-w1" ] && [ ! -d "$TMP/a-w2" ] \
  && ok "  … cả hai đều vào main và được gỡ, không cần chạy lại" || fail "1 rc1=$rc1 rc2=$rc2: $(tail -2 "$TMP/out1") | $(tail -2 "$TMP/out2")"
[ "$r1" = 1 ] && [ "$r2" = 1 ] && ok "  … mỗi worktree chạy suite đúng 1 lần (người chờ gộp main mới rồi gate một lần)" \
  || fail "1 số lần chạy suite: a-w1=$r1 a-w2=$r2 (mong 1 và 1): $(tr '\n' ' ' < "$TMP/runs")"

# 2 một tiến trình khác giữ khoá gate gộp: hết WORKTREE_MERGE_GATE_LOCK_WAIT_S thì từ chối, "running" (hook Stop không giữ), không "moved"
repo c; work c c-w app2.sh; cb="$(G "$TMP/c" rev-parse HEAD)"; : > "$TMP/runs"
python3 -c 'import fcntl, sys, time
f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[2], "w").close(); time.sleep(60)' "$TMP/c/.git/devkit-merge-gate.lock" "$TMP/c.ready" & HOLDER=$!
for _ in $(seq 50); do [ -f "$TMP/c.ready" ] && break; sleep 0.1; done
[ -f "$TMP/c.ready" ] || fail "2 setup: tiến trình giữ khoá không lên"
t0=$SECONDS
(cd "$TMP/c" && env GATE_RUNS="$TMP/runs" WORKTREE_MERGE_GATE_LOCK_WAIT_S=1 python3 "$WT" automerge "$TMP/c-w" > "$TMP/out" 2> "$TMP/err"); rc=$?
took=$((SECONDS - t0))
python3 -c 'import json,sys; d = json.loads(sys.argv[1]); sys.exit(0 if d.get("status") == "blocked" and d.get("running") is True and not d.get("moved") else 1)' "$(tail -1 "$TMP/out")" 2>/dev/null; js=$?
[ "$rc" = 1 ] && [ "$js" = 0 ] && [ "$took" -lt 20 ] && [ "$(G "$TMP/c" rev-parse HEAD)" = "$cb" ] && [ ! -s "$TMP/runs" ] && [ -d "$TMP/c-w" ] \
  && ok "2 khoá gate gộp bị giữ quá WORKTREE_MERGE_GATE_LOCK_WAIT_S: từ chối sau ${took} s (running, không moved), main đứng yên, không chạy suite" \
  || fail "2 rc=$rc json=$js took=${took}s runs=$(wc -l < "$TMP/runs" | tr -d ' '): $(tail -1 "$TMP/out" | cut -c1-200)"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null; HOLDER=""
# … khoá được nhả: lần sau gộp bình thường
(cd "$TMP/c" && python3 "$WT" finish "$TMP/c-w" > "$TMP/out" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -f "$TMP/c/app2.sh" ] && ok "  … khoá được nhả: finish lần sau gộp xong" || fail "2 sau khi nhả khoá rc=$rc: $(tail -2 "$TMP/out")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_merge_gate_lock: PASS"; exit 0; } || { echo "test_worktree_merge_gate_lock: FAIL ($FAILS)"; exit 1; }
