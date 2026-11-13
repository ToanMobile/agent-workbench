#!/usr/bin/env bash
# ────────────────────────────────────────────────────────
# test_proof_gate_hour_edge.sh — the loop guard of a session with NO turn start survives an hour edge (#1127).
#
# With no turn start (a peer-only session, no transcript) hooks/proof_gate.sh budgets [block, block, release] per HOUR: the state
# key is `<session>@h<hour bucket>`. Runs that straddled an hour edge (00:00 UTC is one) changed key under the run, the budget
# restarted and the row came out [2, 2, 2, 2] instead of [2, 2, release, release]: test_turn_start_reverse.sh F went red when CI
# crossed 00:00 UTC. The budget now carries over: a run counts against the earlier hour's key too.
# PROOF_GATE_NOW pins the clock (epoch seconds), so the edge is hit on purpose and not by luck.
#   A. four runs around a mid-day hour edge (17:00 UTC), clock pinned: [block, block, release, release]
#   B. four runs around 00:00 UTC, clock pinned: [block, block, release, release]
#   C. control, no edge: four runs on the real clock give the same row
# Usage: bash tests/gates/test_proof_gate_hour_edge.sh   Exit 0 = all hold. bash 3.2 compatible.
# ────────────────────────────────────────────────────────
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
KIT="$(cd "$(dirname "$0")/../.." && pwd)"
export HOOK="$KIT/hooks/proof_gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export REPO="$TMP/repo"
mkdir -p "$REPO/.agents"
git -C "$REPO" init -q .
printf '{"profile":"backend"}' > "$REPO/.agents/active-profile.json"   # backend: no image needed, only the gate half is under test
printf '.claude/audit-gate/\n' > "$REPO/.gitignore"
printf 'x\n' > "$REPO/f.txt"
git -C "$REPO" add -A
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m init

python3 - <<'PY'
import json, os, subprocess, sys

HOOK, REPO = os.environ["HOOK"], os.environ["REPO"]
REPORT4 = ("1. Đã fix: lỗi X, RED→GREEN.\n2. Chặn bug cũ: REG-1 PASS.\n3. Nguy cơ bug mới: đã rà caller.\n"
           "4. An toàn mã nguồn: secret 0, placeholder 0.")
XONG = "XONG\nĐã sửa lỗi X.\nGate exit 0 · ảnh: không cần (profile backend)\n" + REPORT4
FAILS = 0


def check(cond, what, detail=""):
    global FAILS
    print(("✔ " if cond else "✖ ") + what + ("" if cond else " — " + detail))
    if not cond:
        FAILS += 1


def stop(session, now=None):
    """One Stop hook run with no transcript (no turn start). 2 = block, 'release' = let through with a system message."""
    env = dict(os.environ, CLAUDE_PROJECT_DIR=REPO)
    env.pop("PROOF_GATE_NOW", None)
    if now is not None:
        env["PROOF_GATE_NOW"] = repr(float(now))
    r = subprocess.run(["bash", HOOK], input=json.dumps({"session_id": session, "last_assistant_message": XONG}),
                       capture_output=True, text=True, timeout=60, env=env)
    if r.returncode == 0 and "systemMessage" in r.stdout:
        return "release"
    return r.returncode


WANT = [2, 2, "release", "release"]
for session, edge in (("edge-mid", 1900000000 // 3600 * 3600), ("edge-midnight", 1900000000 // 86400 * 86400)):
    row = [stop(session, now=edge + dt) for dt in (-2, -1, 1, 2)]
    check(row == WANT, "%s: the block budget survives the hour edge (pinned clock)" % session, "row %r" % (row,))
row = [stop("edge-none") for _ in range(4)]
check(row == WANT, "control: four runs on the real clock give [block, block, release, release]", "row %r" % (row,))
sys.exit(1 if FAILS else 0)
PY
