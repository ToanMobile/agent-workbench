#!/usr/bin/env bash
# Hồi quy 31/10/2026 — merge gate tự động 100%, fail-closed (super-board-merge-gate.sh):
#   R1 chưa có lượt review 4 bên nào (NONE) → không merge, báo rõ `review-missing:` và thoát riêng exit 10 để merge-queue đếm lần thử
#      (3 lần → 🛡 Blocked) thay vì lặp mù Review ↔ Merge (13bcd39b20)
#   R2 summary.json không chữ ký / chữ ký giả / bị sửa sau khi ký / FAIL → không merge (exit 6); verdict của head khác → exit 10
#   R3 PASS_REDUCED bị từ chối mặc định; chỉ nhận khi lượt chạy đặt --accept-reduced-review <đúng skip list>
#   C1 check CI đỏ → không merge (exit 11), kể cả check đỏ khi đang chờ auto-merge (auto-merge bị tắt lại)
#   C2 repo có required checks → `gh pr merge --auto --squash --delete-branch --match-head-commit <sha>`, không --admin;
#      không có required check → merge ngay (không --auto); đọc protection lỗi → không merge (exit 4)
#   M1 PR money/auth/migration: không có đường người duyệt; cần review deep + security ok/pass + test bổ sung; thiếu test bổ sung
#      trong config → exit 9; PASS_REDUCED không bao giờ đủ (exit 6); chưa review gì kể cả kèm --accept-reduced-review → exit 10
#   T1 không tìm thấy review-fanout.sh của DevKit → exit 9 (fail-closed)
#   T2 DevKit cũ không có `review-fanout.sh --verify-summary` → exit 9 (fail-closed, gate không tự tính HMAC)
#   G  #744: cửa sổ grandfather tạm (hạn 2026-11-01 06:00 +07) đã gỡ: PR mở trước #742 thiếu review → exit 10, summary không ký → exit 6,
#      gate không đọc createdAt và helper đã xoá
#   S  2823727da8: REVIEW_REGRESSION_STATUS thừa hưởng từ môi trường bị loại bỏ; đường dẫn status ngoài cây (B2) chỉ nhận qua cờ
#      --review-status-file <abs-path> (cấm SB_BOARD_WORKER=1) hoặc merge_policy.review_status_file trong --config tin cậy, kiểm tra nằm
#      ngoài repo/scratch và không được làm rơi/bỏ qua hàng BUG-REV-* đang mở trong checklist của nhánh
# Verdict đi qua đúng entry point thật: universal-agent-devkit/bin/review-fanout.sh --status / --verify-summary (khoá HMAC trong
# HOME tạm của test, ký bằng review_sign.py như review-merge.py). gh là bản giả. Tương thích bash 3.2.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/universal-agent-devkit/tests/lib/clean_git_env.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-gate-hardening.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
DK="$ROOT/universal-agent-devkit/bin"
export HOME="$TMP/home"; mkdir -p "$HOME"
unset REVIEW_SKIP_REVIEWERS REVIEW_CLAUDE_MODEL REVIEW_GROK_MODEL REVIEW_AGY_MODEL REVIEW_REGRESSION_STATUS \
  REVIEW_CLAUDE_BIN REVIEW_GROK_BIN REVIEW_AGY_CLI REVIEW_DEEP_LINES SB_MERGE_ACCEPT_REDUCED_REVIEW
export SB_HEAVY_SLOT_DIR="$TMP/heavy-slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export SB_NOTIFY_SKIP=1 SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_MERGE_RECHECK_DELAY_S=0
export SB_MERGE_AUTO_POLL_S=1 SB_MERGE_AUTO_WAIT_S=20

# Gate chạy từ bản sao (symlink đã giải): <wb>/.claude/bin + <wb>/universal-agent-devkit → DevKit thật của repo.
WB="$TMP/wb"; mkdir -p "$WB/.claude"
cp -RL "$ROOT/.claude/bin" "$WB/.claude/bin" 2>/dev/null
ln -s "$ROOT/universal-agent-devkit" "$WB/universal-agent-devkit"
GATE="$WB/.claude/bin/super-board-merge-gate.sh"
# Bản không có DevKit cạnh gate (T1).
WB2="$TMP/wb2"; mkdir -p "$WB2/.claude"; cp -RL "$WB/.claude/bin" "$WB2/.claude/bin"
GATE_NODK="$WB2/.claude/bin/super-board-merge-gate.sh"
# Bản có DevKit "cũ": --status thật, nhưng --verify-summary là đối số lạ (exit 2) như trước khi entry point đó có (T2).
WB3="$TMP/wb3"; mkdir -p "$WB3/.claude" "$WB3/universal-agent-devkit/bin"; cp -RL "$WB/.claude/bin" "$WB3/.claude/bin"
printf '#!/usr/bin/env bash
[ "${1:-}" = --verify-summary ] && { echo "review-fanout: unknown argument $1" >&2; exit 2; }
exec bash "%s/review-fanout.sh" "$@"
' "$DK" \
  > "$WB3/universal-agent-devkit/bin/review-fanout.sh"
GATE_OLDDK="$WB3/.claude/bin/super-board-merge-gate.sh"

O="$TMP/origin.git"; R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q --bare -b main "$O"
git init -q -b main "$R"
git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf '.claude/\n' > "$R/.gitignore"
echo a > "$R/a"; git -C "$R" add .gitignore a; git -C "$R" commit -qm init
git -C "$R" remote add origin "$O"; git -C "$R" push -q origin main
COMMON="$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"

# pr <N> <path>: nhánh feat-<N> (không mang issue-N: bỏ qua AC) thêm <path>, đã push; diff + meta cho gh giả, worktree review.
pr() {
  git -C "$R" branch -q --no-track "feat-$1" origin/main
  git -C "$R" worktree add -q "$W/build-$1" "feat-$1"
  mkdir -p "$(dirname "$W/build-$1/$2")"; echo "change $1" > "$W/build-$1/$2"
  git -C "$W/build-$1" add "$2"; git -C "$W/build-$1" commit -qm "card $1"
  git -C "$R" push -q origin "feat-$1"
  git -C "$R" rev-parse "feat-$1" > "$TMP/pr$1.head"; echo "feat-$1" > "$TMP/pr$1.ref"
  git -C "$R" diff origin/main "feat-$1" > "$TMP/pr$1.diff"
  printf '{"files":[{"path":"%s","additions":1,"deletions":0}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' "$2" > "$TMP/pr$1.meta"
  git -C "$R" worktree add -q --detach "$W/review-$1" "$(cat "$TMP/pr$1.head")"
}
pr 5 b.txt
pr 7 server/auth/login.kt
H5=$(cat "$TMP/pr5.head"); H7=$(cat "$TMP/pr7.head")

# Mã băm code state đúng như gate hỏi: checkout sạch của head, --base merge-base(head, origin/main), môi trường REVIEW_* trống.
hash_of() {  # hash_of <sha> [skip]
  local wt="$W/hash-$1-${2:-full}" mb
  [ -d "$wt" ] || git -C "$R" worktree add -q --detach "$wt" "$1"
  mb=$(git -C "$R" merge-base "$1" origin/main)
  bash "$DK/review-fanout.sh" --repo "$wt" --base "$mb" ${2:+--skip "$2"} --hash
}
# verdict <sha> <skip|""> <VERDICT> <depth> <sec status> <sec verdict> [sign|nosig|tamper|badsig]
verdict() {
  local h run
  h=$(hash_of "$1" "$2"); run="$COMMON/review-fanout/$h"
  rm -rf "$run"; mkdir -p "$run"
  python3 - "$run/summary.json" "$h" "$3" "$4" "$5" "$6" "$2" <<'PY'
import json, sys
path, h, v, depth, ss, sv, skip = sys.argv[1:8]
req = ["claude", "antigravity", "grok", "ocr", "registry"] + (["security", "verifier"] if depth == "deep" else [])
skipped = [s for s in skip.split(",") if s]
req = [r for r in req if r not in skipped]
revs = {r: {"status": "ok", "verdict": "pass"} for r in req}
if depth == "deep":
    revs["security"] = {"status": ss, "verdict": sv}
json.dump({"verdict": v, "reasons": [], "meta": {"code_hash": h, "depth": depth, "required": req},
           "reviewers": revs, "reduced": bool(skipped), "skipped_by_override": skipped}, open(path, "w"), indent=1)
PY
  case "${7:-sign}" in
    nosig) : ;;
    sign) python3 "$DK/review_sign.py" sign "$run/summary.json" ;;
    tamper) python3 "$DK/review_sign.py" sign "$run/summary.json"
            python3 - "$run/summary.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); s["note"] = "edited after signing"; json.dump(s, open(sys.argv[1], "w"))
PY
            ;;
    badsig) printf '%064d\n' 0 > "$run/summary.json.sig" ;;
  esac
}
clear_verdicts() { rm -rf "$COMMON/review-fanout"/[0-9a-f]*; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/gh.calls"
if [ "$1" = api ]; then
  [ "${FAKE_API_FAIL:-0}" = 1 ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
  path=$2; jqx=""
  while [ $# -gt 0 ]; do [ "$1" = --jq ] && jqx=$2; shift; done
  case "$path" in
    */rules/branches/*) body='[]' ;;
    */branches/*)
      if [ "${FAKE_REQUIRED:-0}" = 1 ]; then
        body='{"protected":true,"protection":{"enabled":true,"required_status_checks":{"enforcement_level":"everyone","contexts":["ci/test"],"checks":[{"context":"ci/test","app_id":null}]}}}'
      else
        body='{"protected":false,"protection":{"enabled":false,"required_status_checks":{"enforcement_level":"off","contexts":[],"checks":[]}}}'
      fi ;;
    *) echo "fake gh: unexpected api $path" >&2; exit 1 ;;
  esac
  if [ -n "$jqx" ]; then printf '%s' "$body" | jq -r "$jqx"; else printf '%s\n' "$body"; fi
  exit 0
fi
n=$(printf '%s\n' "$@" | grep -E '^[0-9]+$' | head -1)
head=$(cat "$FAKE_DIR/pr$n.head")
case " $* " in
  *" pr view "*"headRefName,headRefOid"*) echo "$(cat "$FAKE_DIR/pr$n.ref") $head" ;;
  *" pr view "*"createdAt"*) [ -n "${FAKE_CREATED:-}" ] || { echo "fake gh: no createdAt" >&2; exit 1; }; echo "$FAKE_CREATED" ;;
  *" pr view "*"state,mergeCommit,headRefOid"*)
    if [ -e "$FAKE_DIR/merged" ]; then printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$head" "$head"
    else printf '{"state":"OPEN","mergeCommit":null,"headRefOid":"%s"}\n' "$head"; fi ;;
  *" pr view "*"labels,files"*) cat "$FAKE_DIR/pr$n.meta" ;;
  *" pr view "*"state,autoMergeRequest"*) echo "OPEN armed" ;;
  *" pr view "*"autoMergeRequest"*) echo false ;;
  *" pr view "*"mergeCommit"*) echo "$head" ;;
  *" pr view "*"title"*) echo "card $n" ;;
  *" pr view "*"body"*) echo "" ;;
  *" pr diff "*) cat "$FAKE_DIR/pr$n.diff" ;;
  *" pr checks "*)
    st=${FAKE_CHECKS:-pass}
    if [ -s "$FAKE_DIR/merge.calls" ] && [ -n "${FAKE_CHECKS_AFTER:-}" ]; then st=$FAKE_CHECKS_AFTER; fi
    case "$st" in
      none) echo "no checks reported on the '$(cat "$FAKE_DIR/pr$n.ref")' branch" >&2; exit 1 ;;
      pass) echo '[{"name":"ci/test","state":"SUCCESS","bucket":"pass"}]' ;;
      pending) echo '[{"name":"ci/test","state":"IN_PROGRESS","bucket":"pending"}]'; exit 8 ;;
      fail) echo '[{"name":"ci/test","state":"FAILURE","bucket":"fail"},{"name":"lint","state":"SUCCESS","bucket":"pass"}]'; exit 1 ;;
      *) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
    esac ;;
  *" pr merge "*"--disable-auto"*) echo "$*" >> "$FAKE_DIR/disable.calls" ;;
  *" pr merge "*) echo "$*" >> "$FAKE_DIR/merge.calls"; [ "${FAKE_AUTO_HOLD:-0}" = 1 ] || : > "$FAKE_DIR/merged" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP"

CFG="$TMP/cfg.json"
python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["touch " + sys.argv[1]],
  "merge_policy":{"default":"auto","machine_gate":{"verify_commands":["touch " + sys.argv[2]]}}}))' "$TMP/verified" "$TMP/extra" > "$CFG"
CFG_NOEXTRA="$TMP/cfg-noextra.json"
python3 -c 'import json,sys; print(json.dumps({"base_branch":"main","repo":{"path":".","remote":""},"verify_commands":["touch " + sys.argv[1]],
  "merge_policy":{"default":"auto"}}))' "$TMP/verified" > "$CFG_NOEXTRA"

# gate <pr> <gate> <env…> -- <args…>
gate() {
  local n="$1" g="$2"; shift 2
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  rm -f "$TMP/verified" "$TMP/extra" "$TMP/merged" "$TMP/merge.calls" "$TMP/disable.calls" "$TMP/gh.calls" "$TMP/halt.json"
  rm -rf "$COMMON/super-board/verified-trees"
  local h; h=$(cat "$TMP/pr$n.head")
  ( cd "$W/review-$n" && env ${envs[@]+"${envs[@]}"} bash "$g" --config "$CFG" --pr "$n" --expect-head "$h" --lock-timeout 5 "$@" ) \
    >"$TMP/out" 2>"$TMP/err"; RC=$?
}
merged_calls() { [ -s "$TMP/merge.calls" ] && wc -l < "$TMP/merge.calls" | tr -d ' ' || echo 0; }
why() { echo "rc=$RC out=[$(tail -4 "$TMP/out" | tr '\n' '|')] err=[$(tail -6 "$TMP/err" | tr '\n' '|')]"; }

# ── R1. chưa có lượt review (NONE → exit 10 riêng để merge-queue không lặp Review ↔ Merge, 13bcd39b20)
clear_verdicts
gate 5 "$GATE" -- 
[ "$RC" -eq 10 ] && [ "$(merged_calls)" = 0 ] && grep -q "^review-missing: $H5 " "$TMP/out" \
  && grep -q 'no 4-way review run exists' "$TMP/err" && [ ! -e "$TMP/verified" ] \
  && ok "R1 no review run (NONE): distinct exit 10 + review-missing stdout, nothing verified, gh pr merge never called" || fail "R1 no verdict: $(why)"

# ── R2. không chữ ký / bị sửa sau khi ký / chữ ký giả
for mode in nosig tamper badsig; do
  clear_verdicts; verdict "$H5" "" PASS light ok pass "$mode"
  gate 5 "$GATE" --
  [ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] \
    && ok "R2 ${mode} PASS summary: exit 6, no merge" || fail "R2 ${mode}: $(why)"
done
# Đối chứng: verdict PASS ký thật → merge
clear_verdicts; verdict "$H5" "" PASS light ok pass sign
gate 5 "$GATE" --
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] && [ -e "$TMP/verified" ] \
  && ok "control: signed PASS for the exact head merges (exit 0, one merge call)" || fail "control signed PASS: $(why)"
# Verdict PASS của head khác không trả lời cho head này
clear_verdicts; verdict "$H7" "" PASS light ok pass sign
gate 5 "$GATE" --
[ "$RC" -eq 10 ] && [ "$(merged_calls)" = 0 ] && ok "R2 a signed PASS of another head does not count (no review of this head: exit 10)" || fail "R2 other head: $(why)"
# Verdict FAIL
clear_verdicts; verdict "$H5" "" FAIL light ok pass sign
gate 5 "$GATE" --
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && ok "R2 signed FAIL: exit 6, no merge" || fail "R2 FAIL: $(why)"

# ── R3. PASS_REDUCED
clear_verdicts; verdict "$H5" "grok" PASS_REDUCED light ok pass sign
gate 5 "$GATE" --
[ "$RC" -eq 10 ] && [ "$(merged_calls)" = 0 ] && ok "R3 PASS_REDUCED without an override: rejected (no full review of the head: exit 10)" || fail "R3 default: $(why)"
gate 5 "$GATE" SB_MERGE_ACCEPT_REDUCED_REVIEW=ocr --
[ "$RC" -eq 10 ] && [ "$(merged_calls)" = 0 ] && ok "R3 override for another skip list (ocr) does not accept a grok-reduced PASS (exit 10)" || fail "R3 wrong list: $(why)"
gate 5 "$GATE" -- --accept-reduced-review grok
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] && grep -q 'accepting PASS_REDUCED' "$TMP/err" \
  && ok "R3 --accept-reduced-review grok: PASS_REDUCED accepted for this run only" || fail "R3 flag: $(why)"
gate 5 "$GATE" REVIEW_SKIP_REVIEWERS=grok --
[ "$RC" -eq 10 ] && [ "$(merged_calls)" = 0 ] && ok "R3 inherited REVIEW_SKIP_REVIEWERS is ignored (no back door, exit 10)" || fail "R3 env skip: $(why)"
# Lượt review reduced đang chạy (3:RUNNING) → exit 4 chờ nhịp sau, không đánh đồng thành exit 6 (về Review).
clear_verdicts
RUN_GROK="$COMMON/review-fanout/$(hash_of "$H5" "grok")"
mkdir -p "$RUN_GROK"; echo "$$" > "$RUN_GROK/pid"
gate 5 "$GATE" -- --accept-reduced-review grok
rm -rf "$RUN_GROK"
[ "$RC" -eq 4 ] && [ "$(merged_calls)" = 0 ] && grep -q 'still running' "$TMP/err" \
  && ok "R3 reduced review still running (3:RUNNING): exit 4 retry, not exit 6" || fail "R3 running reduced: $(why)"
# PASS_REDUCED ghi vào thư mục của review đủ 4 bên cũng không phải PASS
clear_verdicts; verdict "$H5" "" PASS_REDUCED light ok pass sign
gate 5 "$GATE" --
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && ok "R3 PASS_REDUCED in the full-review slot: rejected" || fail "R3 slot: $(why)"

# ── C1/C2. CI
clear_verdicts; verdict "$H5" "" PASS light ok pass sign
gate 5 "$GATE" FAKE_CHECKS=fail --
[ "$RC" -eq 11 ] && [ "$(merged_calls)" = 0 ] && grep -q '^ci-check: ci/test' "$TMP/out" && [ ! -e "$TMP/verified" ] \
  && ok "C1 failing check: exit 11 before verify, no merge" || fail "C1 failing: $(why)"
gate 5 "$GATE" FAKE_CHECKS=broken --
[ "$RC" -eq 4 ] && [ "$(merged_calls)" = 0 ] && ok "C1 unreadable checks: exit 4, no merge (fail-closed)" || fail "C1 unreadable: $(why)"
gate 5 "$GATE" FAKE_REQUIRED=1 FAKE_CHECKS=pending --
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] && grep -q -- '--auto' "$TMP/merge.calls" && grep -q -- '--squash' "$TMP/merge.calls" \
  && grep -q -- '--delete-branch' "$TMP/merge.calls" && grep -q -- "--match-head-commit $H5" "$TMP/merge.calls" \
  && ! grep -q -- '--admin' "$TMP/gh.calls" \
  && ok "C2 required checks: gh pr merge --auto --squash --delete-branch --match-head-commit <head>, no --admin" || fail "C2 auto: $(why) calls=$(cat "$TMP/merge.calls" 2>/dev/null)"
gate 5 "$GATE" FAKE_REQUIRED=0 FAKE_CHECKS=none --
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] && ! grep -q -- '--auto' "$TMP/merge.calls" && grep -q -- "--match-head-commit $H5" "$TMP/merge.calls" \
  && ok "C2 no required checks: immediate squash merge without --auto" || fail "C2 immediate: $(why)"
gate 5 "$GATE" FAKE_REQUIRED=1 FAKE_CHECKS=pending FAKE_AUTO_HOLD=1 FAKE_CHECKS_AFTER=fail --
[ "$RC" -eq 11 ] && [ -s "$TMP/disable.calls" ] && grep -q '^ci-check: ci/test' "$TMP/out" \
  && ok "C1 check turns red while auto-merge waits: exit 11 and auto-merge disabled again" || fail "C1 red while waiting: $(why) disable=$(cat "$TMP/disable.calls" 2>/dev/null)"
gate 5 "$GATE" FAKE_REQUIRED=1 FAKE_CHECKS=pending FAKE_AUTO_HOLD=1 SB_MERGE_AUTO_WAIT_S=2 --
[ "$RC" -eq 4 ] && [ -s "$TMP/disable.calls" ] && ok "C2 required checks never finish: exit 4, auto-merge disabled" || fail "C2 timeout: $(why)"
gate 5 "$GATE" FAKE_API_FAIL=1 --
[ "$RC" -eq 4 ] && [ "$(merged_calls)" = 0 ] && ok "C2 branch protection unreadable: exit 4, no merge (fail-closed)" || fail "C2 api fail: $(why)"

# ── M1. machine gate (auth path)
clear_verdicts; verdict "$H7" "" PASS light ok pass sign
gate 7 "$GATE" --
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && grep -q '^machine-gate: auth' "$TMP/out" && ! grep -q '^human-gate:' "$TMP/out" \
  && grep -q 'deep review' "$TMP/err" && ok "M1 auth PR + light review: no human route, exit 6 (deep review required)" || fail "M1 light: $(why)"
clear_verdicts; verdict "$H7" "" PASS deep ok fail sign
gate 7 "$GATE" --
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && grep -q 'security reviewer' "$TMP/err" \
  && ok "M1 auth PR + deep review whose security reviewer did not pass: exit 6" || fail "M1 sec fail: $(why)"
clear_verdicts; verdict "$H7" "" PASS deep ok pass sign
gate 7 "$GATE" --
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] && [ -e "$TMP/extra" ] && [ -e "$TMP/verified" ] \
  && ! grep -q -e '^human-gate:' -e '^approval-request:' "$TMP/out" \
  && ok "M1 auth PR + deep PASS + security ok + extra test green: merged with no human step" || fail "M1 merge: $(why)"
CFG_SAVE=$CFG; CFG=$CFG_NOEXTRA
gate 7 "$GATE" --
[ "$RC" -eq 9 ] && [ "$(merged_calls)" = 0 ] && grep -q '^verification-readiness: .*machine_gate.verify_commands' "$TMP/err" \
  && ok "M1 gated PR without configured extra tests: exit 9 (fail-closed), nothing merged" || fail "M1 no extra: $(why)"
CFG=$CFG_SAVE
python3 - "$CFG" "$TMP/cfg-redextra.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); c["merge_policy"]["machine_gate"]["verify_commands"] = ["false"]
json.dump(c, open(sys.argv[2], "w"))
PY
CFG=$TMP/cfg-redextra.json
gate 7 "$GATE" --
[ "$RC" -eq 11 ] && [ "$(merged_calls)" = 0 ] && ok "M1 extra test red: exit 11, no merge" || fail "M1 red extra: $(why)"
CFG=$CFG_SAVE
clear_verdicts; verdict "$H7" "grok" PASS_REDUCED deep ok pass sign
gate 7 "$GATE" -- --accept-reduced-review grok
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && ok "M1 gated PR: PASS_REDUCED refused even with --accept-reduced-review" || fail "M1 reduced: $(why)"
clear_verdicts
gate 7 "$GATE" -- --accept-reduced-review grok
[ "$RC" -eq 10 ] && [ "$(merged_calls)" = 0 ] && grep -q "^review-missing: $H7 " "$TMP/out" \
  && ok "M1 unreviewed gated PR with --accept-reduced-review: still exit 10 (review-missing, no exit-6 queue loop)" || fail "M1 unreviewed reduced: $(why)"

# ── T1. DevKit review tool missing
clear_verdicts; verdict "$H5" "" PASS light ok pass sign
gate 5 "$GATE_NODK" --
[ "$RC" -eq 9 ] && [ "$(merged_calls)" = 0 ] && grep -q '^verification-readiness: no DevKit review-fanout.sh' "$TMP/err" \
  && ok "T1 no review-fanout.sh next to the gate: exit 9, no merge (fail-closed)" || fail "T1 missing tool: $(why)"

# ── T2. DevKit without --verify-summary
gate 5 "$GATE_OLDDK" --
[ "$RC" -eq 9 ] && [ "$(merged_calls)" = 0 ] && grep -q '^verification-readiness: .*--verify-summary is unavailable' "$TMP/err" \
  && ok "T2 review-fanout.sh without --verify-summary: exit 9, no merge (fail-closed)" || fail "T2 old DevKit: $(why)"

# ── G. #744: cửa sổ grandfather tạm (PR mở trước #742, hạn 2026-11-01 06:00 +07) đã hết hạn và bị gỡ khỏi gate: G1–G7 cũ
# kiểm tính năng hết hạn đó (miễn verdict trong cửa sổ, đồng hồ, CLI không nới) nên bỏ cùng helper; còn lại đúng luật đầy đủ.
clear_verdicts
gate 5 "$GATE" FAKE_CREATED=2026-10-30T10:00:00Z --
[ "$RC" -eq 10 ] && [ "$(merged_calls)" = 0 ] && ! grep -q GRANDFATHERED "$TMP/err" && ! grep -q createdAt "$TMP/gh.calls" \
  && [ ! -e "$WB/.claude/bin/super-board-grandfather.py" ] \
  && ok "G PR opened before #742 with no review run: exit 10 (review-missing), never grandfathered, createdAt never read, helper gone" \
  || fail "G pre-cutoff PR (no review): $(why) createdAt=$(grep -c createdAt "$TMP/gh.calls")"
clear_verdicts; verdict "$H5" "" PASS light ok pass nosig
gate 5 "$GATE" FAKE_CREATED=2026-10-30T10:00:00Z --
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && ! grep -q GRANDFATHERED "$TMP/err" && ! grep -q createdAt "$TMP/gh.calls" \
  && ok "G PR opened before #742 without a signed verdict (unsigned summary): exit 6, never grandfathered, createdAt never read" \
  || fail "G pre-cutoff PR (unsigned): $(why) createdAt=$(grep -c createdAt "$TMP/gh.calls")"

# ── S. 2823727da8: REVIEW_REGRESSION_STATUS thừa hưởng từ môi trường bị loại bỏ; status ngoài cây (B2) chỉ nhận qua --review-status-file
# hoặc merge_policy.review_status_file trong --config, phải nằm ngoài repo/scratch và không được làm rơi hàng BUG-REV-* đang mở.
STF="$TMP/status-outside.json"; printf '%s\n' '{"version":1,"items":{}}' > "$STF"
clear_verdicts; REVIEW_REGRESSION_STATUS="$STF" verdict "$H5" "" PASS light ok pass sign
gate 5 "$GATE" REVIEW_REGRESSION_STATUS="$STF" --
[ "$RC" -eq 10 ] && [ "$(merged_calls)" = 0 ] && [ ! -e "$TMP/verified" ] && grep -q 'inherited REVIEW_REGRESSION_STATUS is ignored' "$TMP/err" \
  && ok "S1 inherited REVIEW_REGRESSION_STATUS is ignored: bound review not matched (exit 10), no merge" || fail "S1 env status: $(why)"
gate 5 "$GATE" -- --review-status-file "$STF"
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] && grep -q "review: regression status from $STF (sha256 " "$TMP/err" \
  && ok "S2 --review-status-file <the file the review read>: signed PASS found, merged, file + sha256 logged" || fail "S2 flag: $(why)"
printf '%s\n' '{"version":1,"items":{"REG-X":{"kind":"test","status":"PASS"}}}' > "$TMP/status-other.json"
gate 5 "$GATE" -- --review-status-file "$TMP/status-other.json"
[ "$RC" -eq 10 ] && [ "$(merged_calls)" = 0 ] && ok "S3 --review-status-file with other bytes: another code state (exit 10), no merge" || fail "S3 other status: $(why)"
gate 5 "$GATE" -- --review-status-file status-outside.json
[ "$RC" -eq 64 ] && [ "$(merged_calls)" = 0 ] && grep -q 'must name an existing file by absolute path' "$TMP/err" \
  && ok "S4a relative --review-status-file: usage error (exit 64)" || fail "S4a relative: $(why)"
printf '%s\n' '{"version":1,"items":{}}' > "$R/inside-repo.json"
gate 5 "$GATE" -- --review-status-file "$R/inside-repo.json"
rm -f "$R/inside-repo.json"
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && grep -q 'outside the repo' "$TMP/err" \
  && ok "S4b inside-repo --review-status-file (even valid checklist JSON in main worktree): rejected (exit 6), no merge" || fail "S4b inside repo: $(why)"
gate 5 "$GATE" SB_BOARD_WORKER=1 -- --review-status-file "$STF"
[ "$RC" -eq 13 ] && [ "$(merged_calls)" = 0 ] && grep -q 'board worker may not pass --review-status-file' "$TMP/err" \
  && ok "S4c SB_BOARD_WORKER=1 cannot pass --review-status-file (exit 13)" || fail "S4c worker flag: $(why)"

git -C "$R" branch -q --no-track feat-8 origin/main
git -C "$R" worktree add -q "$W/build-8" feat-8
mkdir -p "$W/build-8/.agents"
printf '%s\n' '{"version":1,"items":{"BUG-REV-s5":{"kind":"bug","status":"OPEN","title":"open review bug","tests":[]}}}' > "$W/build-8/.agents/regression_status.json"
git -C "$W/build-8" add .agents/regression_status.json; git -C "$W/build-8" commit -qm "card 8"
git -C "$R" push -q origin feat-8
H8=$(git -C "$R" rev-parse feat-8); echo "$H8" > "$TMP/pr8.head"; echo "feat-8" > "$TMP/pr8.ref"
git -C "$R" diff origin/main feat-8 > "$TMP/pr8.diff"
printf '{"files":[{"path":".agents/regression_status.json","additions":1,"deletions":0}],"labels":[],"body":"","additions":1,"deletions":0,"changedFiles":1}' > "$TMP/pr8.meta"
git -C "$R" worktree add -q --detach "$W/review-8" "$H8"
clear_verdicts; REVIEW_REGRESSION_STATUS="$STF" verdict "$H8" "" PASS light ok pass sign
gate 8 "$GATE" -- --review-status-file "$STF"
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && grep -q 'BUG-REV-s5' "$TMP/err" \
  && ok "S5 empty out-of-tree status file cannot mask active BUG-REV-* row in tracked checklist (exit 6)" || fail "S5 mask bug row: $(why)"
STF_KIND="$TMP/status-spoof-kind.json"
printf '%s\n' '{"version":1,"items":{"BUG-REV-s5":{"kind":"test","last":{"status":"PASS"}}}}' > "$STF_KIND"
clear_verdicts; REVIEW_REGRESSION_STATUS="$STF_KIND" verdict "$H8" "" PASS light ok pass sign
gate 8 "$GATE" -- --review-status-file "$STF_KIND"
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && grep -q 'BUG-REV-s5' "$TMP/err" \
  && ok "S5b out-of-tree status file changing BUG-REV-* kind away from bug is rejected (exit 6)" || fail "S5b kind spoof: $(why)"
STF_AUTO="$TMP/status-autoclosed.json"
printf '%s\n' '{"version":1,"items":{"BUG-REV-s5":{"kind":"bug","state":"auto_closed","tests":[]}}}' > "$STF_AUTO"
clear_verdicts; REVIEW_REGRESSION_STATUS="$STF_AUTO" verdict "$H8" "" PASS light ok pass sign
gate 8 "$GATE" -- --review-status-file "$STF_AUTO"
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && grep -q 'BUG-REV-s5' "$TMP/err" \
  && ok "S5c out-of-tree status file marking BUG-REV-* AUTO_CLOSED without test is rejected (exit 6)" || fail "S5c auto_closed spoof: $(why)"
mkdir -p "$COMMON/postfix-gate"
printf '%s\n' '{"rows":{"BUG-REV-p1":{"id":"BUG-REV-p1","kind":"bug","fixed":false,"title":"pending bug","tests":[]}},"stats":{},"inbox":{}}' > "$COMMON/postfix-gate/pending_rows.json"
clear_verdicts; REVIEW_REGRESSION_STATUS="$STF" verdict "$H5" "" PASS light ok pass sign
gate 5 "$GATE" -- --review-status-file "$STF"
rm -f "$COMMON/postfix-gate/pending_rows.json"
[ "$RC" -eq 6 ] && [ "$(merged_calls)" = 0 ] && grep -q 'BUG-REV-p1' "$TMP/err" \
  && ok "S5d out-of-tree status file omitting BUG-REV-* from trunk pending_rows.json (load_view) is rejected (exit 6)" || fail "S5d pending_rows mask: $(why)"
STF_UNPROVEN="$TMP/status-unproven.json"
printf '%s\n' '{"version":1,"items":{"BUG-REV-s5":{"id":"BUG-REV-s5","kind":"bug","fixed":true,"tests":["REG-T1"],"linked_ts":1700000000},"REG-T1":{"id":"REG-T1","kind":"test","last":{"status":"PASS","ts":1700000010,"at":"2026-11-01T00:00:10Z"}}}}' > "$STF_UNPROVEN"
clear_verdicts; REVIEW_REGRESSION_STATUS="$STF_UNPROVEN" verdict "$H8" "" PASS light ok pass sign
gate 8 "$GATE" -- --review-status-file "$STF_UNPROVEN"
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] \
  && ok "S5e out-of-tree status file with fixed + passing linked test (UNPROVEN, B2) is accepted (exit 0)" || fail "S5e unproven B2: $(why)"

CFG_B2="$TMP/cfg-b2.json"
python3 - "$CFG" "$CFG_B2" "$STF" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); c.setdefault("merge_policy", {})["review_status_file"] = sys.argv[3]
json.dump(c, open(sys.argv[2], "w"))
PY
clear_verdicts; REVIEW_REGRESSION_STATUS="$STF" verdict "$H5" "" PASS light ok pass sign
CFG_SAVE=$CFG; CFG=$CFG_B2
gate 5 "$GATE" SB_BOARD_WORKER=1 --
[ "$RC" -eq 13 ] && [ "$(merged_calls)" = 0 ] && grep -q 'board worker may not use merge_policy.review_status_file' "$TMP/err" \
  && ok "S6a SB_BOARD_WORKER=1 cannot inject merge_policy.review_status_file via --config (exit 13)" || fail "S6a worker config status: $(why)"
gate 5 "$GATE" --
CFG=$CFG_SAVE
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] && grep -q "review: regression status from $STF (sha256 " "$TMP/err" \
  && ok "S6 merge_policy.review_status_file in trusted --config matches B2 review without CLI flag" || fail "S6 config status file: $(why)"
CFG_BAD_B2="$TMP/cfg-bad-b2.json"
python3 - "$CFG" "$CFG_BAD_B2" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); c.setdefault("merge_policy", {})["review_status_file"] = "relative-status.json"
json.dump(c, open(sys.argv[2], "w"))
PY
CFG=$CFG_BAD_B2
gate 5 "$GATE" --
CFG=$CFG_SAVE
[ "$RC" -eq 9 ] && [ "$(merged_calls)" = 0 ] && grep -q 'verification-readiness: merge_policy.review_status_file' "$TMP/err" \
  && ok "S6b invalid merge_policy.review_status_file in --config fails readiness (exit 9)" || fail "S6b bad config status: $(why)"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
