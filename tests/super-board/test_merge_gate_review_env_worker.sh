#!/usr/bin/env bash
# #742 vòng sửa 3 (review 409a7296), merge gate super-board-merge-gate.sh:
#   E  0976a4c5db (P0, INSTINCT-015): gate bỏ đúng bộ biến môi trường mà Stop hook (hooks/review_gate.sh) bỏ trước review-fanout.sh,
#      lấy từ một nguồn (review_runner.py gate-env-names). Trước đây gate giữ ANTIGRAVITY_PM_AGY / REVIEW_MAX_*: một PASS đã ký,
#      ghi meta.runtime trong môi trường của Stop hook, đọc lại thành FOREIGN → NONE → exit 10 và không PR nào merge được.
#   W  d68ca2df2a (P1): PASS_REDUCED chỉ nhận qua --accept-reduced-review của chính lượt chạy: SB_MERGE_ACCEPT_REDUCED_REVIEW thừa
#      hưởng bị bỏ qua (exit 10, có ghi chú), worker của board (SB_BOARD_WORKER=1) không được truyền cờ (exit 13), như --review-status-file.
# Fixture giống tests/super-board/test_merge_gate_review_ci_hardening.sh (gh giả, khoá HMAC trong HOME tạm). Tương thích bash 3.2.
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

# verdict_rt <sha> <skip|""> <VERDICT>: một summary đã ký mang meta.runtime như review-fanout.sh ghi khi Stop hook chạy review
# (môi trường đã bỏ các biến của review_runner.gate_env: không có ANTIGRAVITY_PM_AGY / REVIEW_MAX_*)
verdict_rt() {
  local h run
  h=$(hash_of "$1" "$2"); run="$COMMON/review-fanout/$h"
  rm -rf "$run"; mkdir -p "$run"
  env -u ANTIGRAVITY_PM_AGY -u REVIEW_MAX_USD python3 - "$run/summary.json" "$h" "$3" "$2" "$DK" <<'PY'
import importlib.util, json, sys
path, h, v, skip, dk = sys.argv[1:6]
sp = importlib.util.spec_from_file_location("review_runner", dk + "/review_runner.py")
rr = importlib.util.module_from_spec(sp); sp.loader.exec_module(rr)
skipped = [s for s in skip.split(",") if s]
req = [r for r in ["claude", "antigravity", "grok", "ocr", "registry"] if r not in skipped]
json.dump({"verdict": v, "reasons": [], "meta": {"code_hash": h, "depth": "light", "required": req, "runtime": rr.reviewer_runtime(skipped)},
           "reviewers": {r: {"status": "ok", "verdict": "pass"} for r in req}, "reduced": bool(skipped), "skipped_by_override": skipped},
          open(path, "w"), indent=1)
PY
  python3 "$DK/review_sign.py" sign "$run/summary.json"
}
printf '#!/bin/sh\nexit 0\n' > "$TMP/agy"; chmod +x "$TMP/agy"

# ── E. môi trường của gate có ANTIGRAVITY_PM_AGY / REVIEW_MAX_* (board, merge-queue): PASS ký dưới môi trường của Stop hook vẫn merge
clear_verdicts; verdict_rt "$H5" "" PASS
gate 5 "$GATE" --
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] && ok "E0 control: signed PASS with meta.runtime merges in a clean environment" || fail "E0 control: $(why)"
gate 5 "$GATE" ANTIGRAVITY_PM_AGY="$TMP/agy" REVIEW_MAX_USD=1 --
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] \
  && ok "E1 ANTIGRAVITY_PM_AGY + REVIEW_MAX_USD in the gate's environment: the same PASS still merges (not FOREIGN / exit 10)" || fail "E1 env: $(why)"
names=$(env -i PATH="$PATH" HOME="$HOME" ANTIGRAVITY_PM_AGY=x REVIEW_MAX_USD=1 REVIEW_OCR_BIN=x REVIEW_GROK_MODEL=x REVIEW_TIMEOUT_CLAUDE=1 \
  bash "$DK/review-fanout.sh" --gate-env-names 2>&1 | tr '\n' ' ')
if [ "$names" = "ANTIGRAVITY_PM_AGY REVIEW_GROK_MODEL REVIEW_MAX_USD REVIEW_OCR_BIN " ]; then
  ok "E2 review-fanout.sh --gate-env-names: one list (ANTIGRAVITY_PM_AGY, *_MODEL, REVIEW_MAX_*, *_BIN; not REVIEW_TIMEOUT_*)"
else fail "E2 gate-env-names: [$names]"; fi

# ── W. PASS_REDUCED: chỉ cờ của lượt chạy, không biến thừa hưởng, không worker
clear_verdicts; verdict "$H5" "grok" PASS_REDUCED light ok pass sign
gate 5 "$GATE" SB_MERGE_ACCEPT_REDUCED_REVIEW=grok --
[ "$RC" -eq 10 ] && [ "$(merged_calls)" = 0 ] && grep -q 'inherited SB_MERGE_ACCEPT_REDUCED_REVIEW is ignored' "$TMP/err" \
  && ok "W1 inherited SB_MERGE_ACCEPT_REDUCED_REVIEW=grok does not accept PASS_REDUCED (exit 10, noted)" || fail "W1 env override: $(why)"
gate 5 "$GATE" SB_BOARD_WORKER=1 -- --accept-reduced-review grok
[ "$RC" -eq 13 ] && [ "$(merged_calls)" = 0 ] && [ ! -e "$TMP/verified" ] && grep -q 'board worker may not pass --accept-reduced-review' "$TMP/err" \
  && ok "W2 SB_BOARD_WORKER=1 --accept-reduced-review grok: refused (exit 13), nothing verified or merged" || fail "W2 worker flag: $(why)"
gate 5 "$GATE" SB_BOARD_WORKER=1 SB_MERGE_ACCEPT_REDUCED_REVIEW=grok --
[ "$RC" -eq 10 ] && [ "$(merged_calls)" = 0 ] && ok "W3 worker with the inherited variable: still no PASS_REDUCED (exit 10)" || fail "W3 worker env: $(why)"
gate 5 "$GATE" -- --accept-reduced-review grok
[ "$RC" -eq 0 ] && [ "$(merged_calls)" = 1 ] && ok "W4 control: --accept-reduced-review grok of this run (no worker) merges" || fail "W4 control: $(why)"

if [ "$FAILS" -eq 0 ]; then echo "all passed"; exit 0; else echo "$FAILS failed"; exit 1; fi
