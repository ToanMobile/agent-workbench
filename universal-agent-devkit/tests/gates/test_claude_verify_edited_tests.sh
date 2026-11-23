#!/usr/bin/env bash
# Kiểm thử Hướng A: duyệt chéo test cũ bị sửa/xoá bằng `claude-verify` (`CV...`) mà không phụ thuộc bắt buộc vào Antigravity,
# đồng thời giữ nguyên chốt chống tự duyệt (builder != reviewer), phạm vi base..head, khớp cây/blob, seal Ed25519 và tương thích Antigravity.
#  P1-P8: tra thẳng biên bản CV, scratch merge gate, trailer Test-approved-by, approve-tests, xoá test, --chain-audit, tương thích Antigravity, seal mode bật ký đúng.
#  N1-N5: builder tự duyệt, sổ builder rỗng, engine antigravity, reviewer cũ, --auto-approve-tests, test ngoài phạm vi base..head, sửa test sau seal,
#         main sửa test, seal giả/không ký khi seal mode bật, CV fail mới hơn, replay bản cũ, sai nhánh thẻ, CLAUDE_VERIFY_HOME lạ, ghép sai cặp trailer.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_AUTO_APPROVE_TESTS DEVKIT_TRANSCRIPTS_DIR TARGET_DIR DEVKIT_AGENT_ID CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID
unset WORKTREE_TRUNK_MODE DEVKIT_GATE_MERGE_CHECK CI DEVKIT_VERDICT_SEAL_PUB
unset CLAUDECODE GROK_SESSION_ID GROK_WORKSPACE_ROOT GROK_HOOK_EVENT

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="$(cd "$DEVKIT_DIR/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
CV="$DEVKIT_DIR/bin/claude_verify.py"
KIT="$DEVKIT_DIR/bin/agent-kit"
AUDIT_CHECK="$ROOT/.claude/bin/super-board-audit-check.py"
INSTALL_ET="$ROOT/.claude/bin/super-board-install-edited-test-approval.sh"

TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/projects"
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
export CLAUDE_VERIFY_HOME="$TMP/cv"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
export DEVKIT_PM_HOME_TEST=1
export GIT_CONFIG_GLOBAL=/dev/null

FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
tailout() { printf '%s' "$OUT" | grep -E "Duyệt test|duyệt chéo|Test đã có|CHƯA XÁC MINH|tự duyệt|exit" | tail -5 | cut -c1-240; }

V0='#!/bin/sh\ngrep -q "ok" src/Core.kt\ngrep -q "fun" src/Core.kt\n'
V1='#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\n'
V2='#!/bin/sh\ngrep -q "ok()" src/Core.kt\ngrep -q "fun" src/Core.kt\ngrep -q "=" src/Core.kt\n'

mk() {   # mk <dir> [issue=21]: tạo repo main M0 (tests/t.sh V0, tests/old.sh) và chuyển sang nhánh issue-<N>-x
  local d="$1" n="${2:-21}"
  mkdir -p "$d/src" "$d/tests" && cd "$d" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf '.claude/audit-gate/\n' > .gitignore
  mkdir -p .claude && echo '{"DEVKIT_IMPACT_TEST_ENABLED":"1","DEVKIT_REGRESSION_TEST_ENABLED":"1"}' > .claude/config.json
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/t.sh"}]}]}
JSON
  echo 'fun ok()=1' > src/Core.kt
  echo 'fun other()=1' > src/Other.kt
  printf "$V0" > tests/t.sh
  printf '#!/bin/sh\ngrep -q "fun" src/Core.kt\n' > tests/old.sh
  git add -A && git commit -qm "M0"
  git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b "issue-${n}-x"
}

pr_commit() {
  printf "$1" > tests/t.sh
  echo "fun ok()=$RANDOM" > src/Core.kt
  git commit -qam "$2"
  local br; br="$(git symbolic-ref -q --short HEAD || true)"
  [ -n "$br" ] && git update-ref "refs/remotes/origin/${br}" HEAD
  git rev-parse HEAD
}

reg() {   # reg <repo> <lane> <issue> <session> [engine]
  SB_RUNNER_REGISTER=1 python3 "$CV" register --lane "$2" --repo "$1" --issue "$3" --session "$4" ${5:+--engine "$5"}
}

seal_cv() {   # seal_cv <repo> <session> <head> <branch> [findings_json]: niêm phong qua claude_verify.py seal, gán SID và SRC
  local repo="$1" sess="$2" head="$3" br="$4" finds="${5:-[]}" mb
  mb="$(git -C "$repo" merge-base refs/remotes/origin/main "$head")"
  jq -n --arg h "$head" --arg b "$mb" --argjson f "$finds" '{head:$h, base:$b, findings:$f, reviewed_at:"2026-11-23T00:00:00Z"}' > "$TMP/rep.json"
  OUT_SEAL="$(cd "$repo" && CLAUDE_CODE_SESSION_ID="$sess" python3 "$CV" seal --repo "$repo" --head "$head" --report "$TMP/rep.json" --branch "$br" 2>&1)"
  SRC=$?
  SID="$(printf '%s\n' "$OUT_SEAL" | sed -n 's/^task_id=\(CV[^ ]*\) .*/\1/p' | head -1)"
}

write_cv_record() {   # write_cv_record <repo> <tid> <head> <base> <verdict> <reviewer> <issue> <branch> [seed_hex] [ts]
  python3 - "$DEVKIT_DIR/bin" "$CLAUDE_VERIFY_HOME/records" "$@" <<'PY'
import base64, json, os, subprocess, sys
sys.path.insert(0, sys.argv[1]); import verdict_seal as vs
rec_dir, repo, tid, head, base, verdict, rv, issue, br = sys.argv[2:11]
seed = sys.argv[11] if len(sys.argv) > 11 and sys.argv[11] else ""
ts = sys.argv[12] if len(sys.argv) > 12 and sys.argv[12] else "2026-11-23T01:00:00+00:00"
tree = subprocess.run(["git", "-C", repo, "rev-parse", head + "^{tree}"], capture_output=True, text=True).stdout.strip()
p = {"v": 1, "kind": "claude-verify", "task_id": tid, "head": head, "tree": tree, "base": base,
     "verdict": verdict, "findings": [], "reviewer_session": rv, "builder_session": "builder-sess",
     "issue": int(issue), "branch": br, "ts": ts}
s = json.dumps(p, sort_keys=True, ensure_ascii=False)
sig = base64.b64encode(vs.sign(bytes.fromhex(seed), s.encode())).decode() if seed else None
os.makedirs(rec_dir, exist_ok=True)
json.dump({"payload": s, "sig": sig}, open(os.path.join(rec_dir, tid + ".json"), "w"))
PY
}

run_gate() {
  local d="$1"; shift
  OUT="$(cd "$d" && env "$@" CLAUDE_PROJECT_DIR="$d" python3 "$GATE" --matrix "$d/matrix.json" --lang vi --run-tests --diff main 2>&1)"
  RC=$?
}

pg_approved() {
  local d="$1" rng="$2"; shift 2
  OUT="$(cd "$d" && env "$@" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate as p; ok, why = p.approved(sys.argv[2], sys.argv[3]); print(ok, why); sys.exit(0 if ok else 2)' "$DEVKIT_DIR/bin" "$d" "$rng" 2>&1)"
  RC=$?
}

cvid() { printf 'CV20261123T0000%02d-%s-abcdef' "$1" "$(printf '%s' "$2" | cut -c1-12)"; }

# ── P1: Tra thẳng biên bản claude-verify (không json, không trailer, không Antigravity) → exit 0 PASS
mk "$TMP/p1" 21
X="$(pr_commit "$V1" "PR sửa test")"
reg "$TMP/p1" build 21 builder-sess && reg "$TMP/p1" review 21 reviewer-sess
seal_cv "$TMP/p1" reviewer-sess "$X" issue-21-x
run_gate "$TMP/p1" CLAUDECODE=1
if [ "$SRC" = 0 ] && [ "$RC" = 0 ] && has "duyệt chéo bởi claude-verify (task $SID)" && [ ! -e "$TMP/p1/.claude/audit-gate/approved_tests.json" ]; then
  ok "P1: biên bản claude-verify tại head PR, không json/trailer/Antigravity → PASS"
else
  bad "P1: seal=$SRC rc=$RC sid=$SID $(tailout)"
fi

# ── P2: Scratch merge gate (main tiến thêm commit không chạm test, merge main vào PR detach) → PASS
mk "$TMP/p2" 22
X="$(pr_commit "$V1" "PR sửa test")"
reg "$TMP/p2" build 22 builder-sess && reg "$TMP/p2" review 22 reviewer-sess
seal_cv "$TMP/p2" reviewer-sess "$X" issue-22-x
git -C "$TMP/p2" checkout -q main && echo "fun other()=22" > "$TMP/p2/src/Other.kt" && git -C "$TMP/p2" commit -qam "main tiến"
git -C "$TMP/p2" update-ref refs/remotes/origin/main HEAD
git -C "$TMP/p2" checkout -q --detach main && git -C "$TMP/p2" merge -q --no-ff --no-edit issue-22-x
run_gate "$TMP/p2"
if [ "$RC" = 0 ] && has "duyệt chéo bởi claude-verify (task $SID)"; then
  ok "P2: scratch merge gate (main tiến + merge PR) → PASS qua claude-verify"
else
  bad "P2: scratch merge gate: rc=$RC $(tailout)"
fi

# ── P3: Trailer `Test-approved-by: claude-verify <CV...>` (push_gate.approved + post-fix-gate --since)
mk "$TMP/p3" 23
M0="$(git -C "$TMP/p3" rev-parse main)"
X="$(pr_commit "$V1" "PR sửa test")"
reg "$TMP/p3" build 23 builder-sess && reg "$TMP/p3" review 23 reviewer-sess
seal_cv "$TMP/p3" reviewer-sess "$X" issue-23-x
git -C "$TMP/p3" commit -q --allow-empty -m "audit claude-verify" -m "Test-approved-by: claude-verify $SID"
pg_approved "$TMP/p3" "main..HEAD" CLAUDECODE=1
if [ "$RC" = 0 ] && has "claude-verify pass"; then
  ok "P3a: push_gate.approved nhận trailer Test-approved-by: claude-verify $SID"
else
  bad "P3a: push_gate.approved trailer: rc=$RC out=$OUT"
fi
OUT="$(cd "$TMP/p3" && CLAUDE_PROJECT_DIR="$TMP/p3" python3 "$GATE" --matrix "$TMP/p3/matrix.json" --lang vi --run-tests --since "$M0" 2>&1)"; RC=$?
if [ "$RC" = 0 ]; then
  ok "P3b: post-fix-gate --since nhận trailer Test-approved-by: claude-verify"
else
  bad "P3b: post-fix-gate --since: rc=$RC $(tailout)"
fi

# ── P4: `agent-kit approve-tests <CV...>` trong phiên Claude Code ghi mục reviewer=claude-verify → gate PASS
mk "$TMP/p4" 24
X="$(pr_commit "$V1" "PR sửa test")"
reg "$TMP/p4" build 24 builder-sess && reg "$TMP/p4" review 24 reviewer-sess
seal_cv "$TMP/p4" reviewer-sess "$X" issue-24-x
OUT="$(cd "$TMP/p4" && CLAUDECODE=1 CLAUDE_PROJECT_DIR="$TMP/p4" bash "$KIT" approve-tests "$SID" 2>&1)"; RC=$?
if [ "$RC" = 0 ] && has "duyệt chéo claude-verify, task $SID" && grep -q '"reviewer": "claude-verify"' "$TMP/p4/.claude/audit-gate/approved_tests.json"; then
  ok "P4: agent-kit approve-tests <CV...> ghi mục reviewer=claude-verify"
else
  bad "P4: approve-tests CV: rc=$RC out=$(printf '%s' "$OUT" | tail -3)"
fi

# ── P5: PR xoá test cũ (`tests/old.sh`) nằm trong base..head của CV → PASS
mk "$TMP/p5" 25
git -C "$TMP/p5" rm -q tests/old.sh && echo "fun ok()=25" > "$TMP/p5/src/Core.kt" && git -C "$TMP/p5" commit -qam "PR xoá test cũ"
git -C "$TMP/p5" update-ref refs/remotes/origin/issue-25-x HEAD
X="$(git -C "$TMP/p5" rev-parse HEAD)"
reg "$TMP/p5" build 25 builder-sess && reg "$TMP/p5" review 25 reviewer-sess
seal_cv "$TMP/p5" reviewer-sess "$X" issue-25-x
run_gate "$TMP/p5"
if [ "$RC" = 0 ] && has "duyệt chéo bởi claude-verify (task $SID)"; then
  ok "P5: PR xoá test cũ có biên bản claude-verify → PASS"
else
  bad "P5: PR xoá test cũ: rc=$RC $(tailout)"
fi

# ── P6: super-board-audit-check.py --chain-audit và install-edited-test-approval.sh --has-edited-tests nhận biên bản CV (không có Antigravity)
echo '{"comments":[]}' > "$TMP/empty-meta.json"
OUT="$(python3 "$AUDIT_CHECK" --chain-audit "$(git -C "$TMP/p1" rev-parse HEAD)" --base main --top "$TMP/p1" 2>&1)"; RC=$?
if [ "$RC" = 0 ]; then ok "P6a: super-board-audit-check.py --chain-audit nhận biên bản claude-verify"; else bad "P6a: chain-audit rc=$RC out=$OUT"; fi
OUT="$(bash "$INSTALL_ET" --has-edited-tests "$TMP/empty-meta.json" "$(git -C "$TMP/p1" rev-parse HEAD)" --top "$TMP/p1" --base main 2>&1)"; RC=$?
if [ "$RC" = 0 ] && [ "$OUT" = "pm" ]; then ok "P6b: install-edited-test-approval --has-edited-tests trả pm cho CV"; else bad "P6b: has-edited-tests rc=$RC out=$OUT"; fi

# ── P7: Tương thích ngược Antigravity (trailer + biên bản PM) vẫn PASS
mk "$TMP/p7" 27
X="$(pr_commit "$V1" "PR sửa test")"
mkdir -p "$TMP/pm/projects/p-p7/tasks/T7001-ag"
python3 - "$TMP/pm/projects/p-p7/tasks/T7001-ag/task.json" "$TMP/p7" "$X" <<'PY'
import json, os, subprocess, sys
dest, proj, head = sys.argv[1:4]
mb = subprocess.run(["git", "-C", proj, "merge-base", "main", head], capture_output=True, text=True).stdout.strip()
json.dump({"id": "T7001-ag", "project": os.path.realpath(proj),
           "dispatches": [{"kind": "audit", "agent": "antigravity", "at": "2026-11-23T00:00:00Z", "auditedHead": head, "verdict": "pass", "auditBase": mb, "edited": ["tests/t.sh"]}],
           "verdicts": {"audit": {"verdict": "pass", "reviewer": "antigravity", "auditedHead": head, "notes": "ok"}}}, open(dest, "w"))
PY
git -C "$TMP/p7" commit -q --allow-empty -m "audit agy" -m "Test-approved-by: antigravity T7001-ag"
pg_approved "$TMP/p7" "main..HEAD"
P7_PG=$RC
run_gate "$TMP/p7"
if [ "$P7_PG" = 0 ] && [ "$RC" = 0 ] && has "duyệt chéo bởi antigravity (task T7001-ag)"; then
  ok "P7: tương thích ngược đường Antigravity vẫn PASS"
else
  bad "P7: tương thích Antigravity: pg=$P7_PG gate=$RC $(tailout)"
fi

# ── N1: Builder tự duyệt (reviewer_session == builder-sess) → từ chối ở cả gate lẫn push_gate
mk "$TMP/n1" 31
X="$(pr_commit "$V1" "PR sửa test")"
MB="$(git -C "$TMP/n1" merge-base main "$X")"
reg "$TMP/n1" build 31 builder-sess && reg "$TMP/n1" review 31 builder-sess
CV_SELF="$(cvid 31 "$X")"
write_cv_record "$TMP/n1" "$CV_SELF" "$X" "$MB" pass builder-sess 31 issue-31-x
run_gate "$TMP/n1"
N1_G=$RC
git -C "$TMP/n1" commit -q --allow-empty -m "self" -m "Test-approved-by: claude-verify $CV_SELF"
pg_approved "$TMP/n1" "main..HEAD"
if [ "$N1_G" = 2 ] && [ "$RC" != 0 ]; then
  ok "N1: builder tự duyệt bị từ chối (gate=2, push_gate=$RC)"
else
  bad "N1: builder tự duyệt lọt: gate=$N1_G pg=$RC out=$OUT"
fi

# N1b: sổ builder rỗng (phiên ngoài board) → từ chối
mk "$TMP/n1b" 32
X="$(pr_commit "$V1" "PR sửa test")"
MB="$(git -C "$TMP/n1b" merge-base main "$X")"
reg "$TMP/n1b" review 32 reviewer-sess
CV_NOB="$(cvid 32 "$X")"
write_cv_record "$TMP/n1b" "$CV_NOB" "$X" "$MB" pass reviewer-sess 32 issue-32-x
run_gate "$TMP/n1b"
[ "$RC" = 2 ] && ok "N1b: sổ builder rỗng → gate từ chối (exit 2)" || bad "N1b: rc=$RC $(tailout)"

# N1c: lượt build engine=antigravity → claude-verify fail closed
mk "$TMP/n1c" 33
X="$(pr_commit "$V1" "PR sửa test")"
MB="$(git -C "$TMP/n1c" merge-base main "$X")"
reg "$TMP/n1c" build 33 agy-b antigravity && reg "$TMP/n1c" review 33 reviewer-sess
CV_AGB="$(cvid 33 "$X")"
write_cv_record "$TMP/n1c" "$CV_AGB" "$X" "$MB" pass reviewer-sess 33 issue-33-x
run_gate "$TMP/n1c"
[ "$RC" = 2 ] && ok "N1c: lượt build engine antigravity → claude-verify từ chối (exit 2)" || bad "N1c: rc=$RC $(tailout)"

# N1d: reviewer giao trước lượt build mới nhất → từ chối
mk "$TMP/n1d" 34
X="$(pr_commit "$V1" "PR sửa test")"
MB="$(git -C "$TMP/n1d" merge-base main "$X")"
reg "$TMP/n1d" build 34 b1 && reg "$TMP/n1d" review 34 old-rev && reg "$TMP/n1d" build 34 b2
CV_OLD="$(cvid 34 "$X")"
write_cv_record "$TMP/n1d" "$CV_OLD" "$X" "$MB" pass old-rev 34 issue-34-x
run_gate "$TMP/n1d"
[ "$RC" = 2 ] && ok "N1d: reviewer giao trước lượt build mới nhất → từ chối (exit 2)" || bad "N1d: rc=$RC $(tailout)"

# N1e: --auto-approve-tests / DEVKIT_AUTO_APPROVE_TESTS=1 vẫn bị từ chối
OUT="$(cd "$TMP/n1b" && DEVKIT_AUTO_APPROVE_TESTS=1 CLAUDE_PROJECT_DIR="$TMP/n1b" python3 "$GATE" --matrix "$TMP/n1b/matrix.json" --lang vi --run-tests --diff main --auto-approve-tests 2>&1)"; RC=$?
[ "$RC" = 2 ] && has "tự duyệt bị từ chối" && ok "N1e: --auto-approve-tests / DEVKIT_AUTO_APPROVE_TESTS vẫn bị từ chối" || bad "N1e: rc=$RC $(tailout)"

# ── N2: Test sửa NGOÀI phạm vi base..head (biên bản viết base = C1 thay vì merge-base) → từ chối
mk "$TMP/n2" 35
C1="$(pr_commit "$V1" "commit 1 sửa test")"
echo "fun other()=35" > "$TMP/n2/src/Other.kt" && git -C "$TMP/n2" commit -qam "commit 2 chỉ sửa code"
C2="$(git -C "$TMP/n2" rev-parse HEAD)"
reg "$TMP/n2" build 35 builder-sess && reg "$TMP/n2" review 35 reviewer-sess
CV_NARROW="$(cvid 35 "$C2")"
write_cv_record "$TMP/n2" "$CV_NARROW" "$C2" "$C1" pass reviewer-sess 35 issue-35-x
run_gate "$TMP/n2"
N2_G=$RC
git -C "$TMP/n2" commit -q --allow-empty -m "narrow" -m "Test-approved-by: claude-verify $CV_NARROW"
pg_approved "$TMP/n2" "main..HEAD"
if [ "$N2_G" = 2 ] && [ "$RC" != 0 ]; then
  ok "N2: test sửa ngoài phạm vi base..head (base muộn hơn merge-base) → từ chối"
else
  bad "N2: phạm vi hẹp lọt: gate=$N2_G pg=$RC out=$OUT"
fi

# N2b: base giả "0"*40 → từ chối cho duyệt test sửa
mk "$TMP/n2b" 36
X="$(pr_commit "$V1" "PR sửa test")"
reg "$TMP/n2b" build 36 builder-sess && reg "$TMP/n2b" review 36 reviewer-sess
CV_ZERO="$(cvid 36 "$X")"
write_cv_record "$TMP/n2b" "$CV_ZERO" "$X" "0000000000000000000000000000000000000000" pass reviewer-sess 36 issue-36-x
run_gate "$TMP/n2b"
[ "$RC" = 2 ] && ok "N2b: biên bản base giả 0*40 → gate từ chối (exit 2)" || bad "N2b: rc=$RC $(tailout)"

# ── N3: Nội dung test bị sửa SAU khi seal (dirty, commit mới, main sửa test) → từ chối
mk "$TMP/n3" 37
X="$(pr_commit "$V1" "PR sửa test")"
reg "$TMP/n3" build 37 builder-sess && reg "$TMP/n3" review 37 reviewer-sess
seal_cv "$TMP/n3" reviewer-sess "$X" issue-37-x
printf "$V2" > "$TMP/n3/tests/t.sh"
run_gate "$TMP/n3"
[ "$RC" = 2 ] && ok "N3a: sửa test dirty sau khi seal → gate từ chối (exit 2)" || bad "N3a: rc=$RC $(tailout)"
git -C "$TMP/n3" commit -qam "sửa test sau seal"
run_gate "$TMP/n3"
N3B_G=$RC
git -C "$TMP/n3" commit -q --allow-empty -m "stale trailer" -m "Test-approved-by: claude-verify $SID"
pg_approved "$TMP/n3" "main..HEAD"
if [ "$N3B_G" = 2 ] && [ "$RC" != 0 ]; then
  ok "N3b: commit sửa test sau seal → gate và push_gate từ chối"
else
  bad "N3b: sửa test sau seal lọt: gate=$N3B_G pg=$RC out=$OUT"
fi

# N3c: main sửa đúng file tests/t.sh sau khi seal → từ chối
mk "$TMP/n3c" 38
X="$(pr_commit "$V1" "PR sửa test")"
reg "$TMP/n3c" build 38 builder-sess && reg "$TMP/n3c" review 38 reviewer-sess
seal_cv "$TMP/n3c" reviewer-sess "$X" issue-38-x
git -C "$TMP/n3c" checkout -q main && printf "$V2" > "$TMP/n3c/tests/t.sh" && git -C "$TMP/n3c" commit -qam "main sửa test"
git -C "$TMP/n3c" update-ref refs/remotes/origin/main HEAD
git -C "$TMP/n3c" checkout -q issue-38-x
run_gate "$TMP/n3c"
[ "$RC" = 2 ] && ok "N3c: main sửa test sau khi seal → gate từ chối (exit 2)" || bad "N3c: rc=$RC $(tailout)"

# ── P8 & N4: Seal mode BẬT (pubkey Ed25519 tin cậy)
SEED="$(printf '%064d' 7)"
BAD_SEED="$(printf '%064d' 9)"
python3 -c 'import base64,sys; sys.path.insert(0,sys.argv[1]); import verdict_seal as v; print(base64.b64encode(v.public_key(bytes.fromhex(sys.argv[2]))).decode())' \
  "$DEVKIT_DIR/bin" "$SEED" > "$TMP/seal.pub"
export DEVKIT_VERDICT_SEAL_PUB="$TMP/seal.pub"

mk "$TMP/s1" 41
X="$(pr_commit "$V1" "PR sửa test")"
MB="$(git -C "$TMP/s1" merge-base main "$X")"
reg "$TMP/s1" build 41 builder-sess && reg "$TMP/s1" review 41 reviewer-sess
CV_NOSIG="$(cvid 41 "$X")"
write_cv_record "$TMP/s1" "$CV_NOSIG" "$X" "$MB" pass reviewer-sess 41 issue-41-x
run_gate "$TMP/s1"
N4A_G=$RC
OUT="$(python3 "$AUDIT_CHECK" --chain-audit "$X" --base main --top "$TMP/s1" 2>&1)"; N4A_CA=$?
if [ "$N4A_G" = 2 ] && [ "$N4A_CA" = 3 ]; then
  ok "N4a: seal mode bật + biên bản không ký → gate exit 2, chain-audit exit 3 (pm-unknown)"
else
  bad "N4a: seal mode không ký: gate=$N4A_G chain-audit=$N4A_CA out=$OUT"
fi

rm -f "$CLAUDE_VERIFY_HOME/records/$CV_NOSIG.json"
CV_BADSIG="$(cvid 42 "$X")"
write_cv_record "$TMP/s1" "$CV_BADSIG" "$X" "$MB" pass reviewer-sess 41 issue-41-x "$BAD_SEED"
run_gate "$TMP/s1"
[ "$RC" = 2 ] && ok "N4b: seal mode bật + chữ ký khoá giả → gate từ chối (exit 2)" || bad "N4b: rc=$RC $(tailout)"

rm -f "$CLAUDE_VERIFY_HOME/records/$CV_BADSIG.json"
CV_GOODSIG="$(cvid 43 "$X")"
write_cv_record "$TMP/s1" "$CV_GOODSIG" "$X" "$MB" pass reviewer-sess 41 issue-41-x "$SEED"
run_gate "$TMP/s1"
P8_G=$RC
git -C "$TMP/s1" commit -q --allow-empty -m "signed cv" -m "Test-approved-by: claude-verify $CV_GOODSIG"
pg_approved "$TMP/s1" "main..HEAD"
if [ "$P8_G" = 0 ] && [ "$RC" = 0 ]; then
  ok "P8: seal mode bật + chữ ký Ed25519 hợp lệ → gate PASS và push_gate.approved True"
else
  bad "P8: seal mode ký đúng: gate=$P8_G pg=$RC out=$OUT"
fi
unset DEVKIT_VERDICT_SEAL_PUB

# ── N5a: CV pass trước, rồi CV fail mới hơn ở cùng head → từ chối
mk "$TMP/n5a" 44
X="$(pr_commit "$V1" "PR sửa test")"
MB="$(git -C "$TMP/n5a" merge-base main "$X")"
reg "$TMP/n5a" build 44 builder-sess && reg "$TMP/n5a" review 44 reviewer-sess
write_cv_record "$TMP/n5a" "$(cvid 44 "$X")" "$X" "$MB" pass reviewer-sess 44 issue-44-x "" "2026-11-23T01:00:00+00:00"
write_cv_record "$TMP/n5a" "$(cvid 45 "$X")" "$X" "$MB" fail reviewer-sess 44 issue-44-x "" "2026-11-23T02:00:00+00:00"
run_gate "$TMP/n5a"
[ "$RC" = 2 ] && ok "N5a: biên bản CV fail mới hơn ở cùng head → gate từ chối (exit 2)" || bad "N5a: rc=$RC $(tailout)"

# ── N5b: Replay bản cũ — CV1 pass (V1), CV2 pass (V2), rồi revert về V1 → từ chối
mk "$TMP/n5b" 46
X1="$(pr_commit "$V1" "V1")"
reg "$TMP/n5b" build 46 builder-sess && reg "$TMP/n5b" review 46 reviewer-sess
seal_cv "$TMP/n5b" reviewer-sess "$X1" issue-46-x
X2="$(pr_commit "$V2" "V2 làm mạnh")"
seal_cv "$TMP/n5b" reviewer-sess "$X2" issue-46-x
pr_commit "$V1" "chép lùi về V1" >/dev/null
run_gate "$TMP/n5b"
[ "$RC" = 2 ] && ok "N5b: replay bản test yếu cũ hơn CV mới nhất → gate từ chối (exit 2)" || bad "N5b: rc=$RC $(tailout)"

# ── N5c: Sai nhánh thẻ (đứng ở issue-49-x nhưng dùng CV của issue-47-x) → từ chối
mk "$TMP/n5c" 47
X="$(pr_commit "$V1" "PR sửa test")"
reg "$TMP/n5c" build 47 builder-sess && reg "$TMP/n5c" review 47 reviewer-sess
seal_cv "$TMP/n5c" reviewer-sess "$X" issue-47-x
git -C "$TMP/n5c" checkout -q -b issue-49-x "$X"
run_gate "$TMP/n5c"
[ "$RC" = 2 ] && ok "N5c: nhánh thẻ khác (issue-49-x dùng CV của issue-47-x) → gate từ chối (exit 2)" || bad "N5c: rc=$RC $(tailout)"

# ── N5d: CLAUDE_VERIFY_HOME lạ không bật DEVKIT_PM_HOME_TEST=1 → từ chối
run_gate "$TMP/p1" DEVKIT_PM_HOME_TEST=0
[ "$RC" = 2 ] && ok "N5d: CLAUDE_VERIFY_HOME ngoài fixture (DEVKIT_PM_HOME_TEST=0) → gate từ chối (exit 2)" || bad "N5d: rc=$RC $(tailout)"

# ── N5e: Trailer ghép sai cặp (antigravity + CV... hoặc claude-verify + T...) → từ chối
mk "$TMP/n5e" 48
X="$(pr_commit "$V1" "PR sửa test")"
reg "$TMP/n5e" build 48 builder-sess && reg "$TMP/n5e" review 48 reviewer-sess
seal_cv "$TMP/n5e" reviewer-sess "$X" issue-48-x
git -C "$TMP/n5e" commit -q --allow-empty -m "mismatch1" -m "Test-approved-by: antigravity $SID"
pg_approved "$TMP/n5e" "main..HEAD"
N5E1=$RC
git -C "$TMP/n5e" commit -q --allow-empty --amend -m "mismatch2" -m "Test-approved-by: claude-verify T7001-ag"
pg_approved "$TMP/n5e" "main..HEAD"
if [ "$N5E1" != 0 ] && [ "$RC" != 0 ]; then
  ok "N5e: trailer ghép sai cặp antigravity+CV / claude-verify+T → từ chối"
else
  bad "N5e: ghép sai cặp lọt: rc1=$N5E1 rc2=$RC"
fi

[ "$FAILS" -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
