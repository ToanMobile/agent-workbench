#!/usr/bin/env bash
# #632 B: with seal mode on (trusted pubkey installed), a hand-written antigravity-pm audit pass with no valid seal approves
# nothing: push_gate.audited_head / audited_heads / audit_scope / scoped_audit_runs (pass) and super-board-audit-check
# --chain-audit (None = cannot check, not False). A valid seal approves, and audit_scope returns the SIGNED base/edited, not
# the unsigned auditBase/edited of task.json. With seal mode off (no key) the old behaviour stays (5 app repos not locked).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPO_ROOT="$(cd "$DEVKIT_DIR/.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
export DEVKIT_PM_HOME_TEST=1
mkdir -p "$TMP/repo" && cd "$TMP/repo" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
mkdir tests && echo 'assert 1' > tests/test_a.sh && git add . && git commit -qm c1
BASE="$(git rev-parse HEAD)"
git checkout -q -b pr && echo 'true' > tests/test_a.sh && git commit -qam weaken
WEAK="$(git rev-parse HEAD)"
echo doc > README && git add README && git commit -qm harmless
HEAD_SHA="$(git rev-parse HEAD)"
AUDIT_CHECK="$REPO_ROOT/.claude/bin/super-board-audit-check.py"
python3 - "$DEVKIT_DIR/bin" "$TMP" "$HEAD_SHA" "$BASE" "$WEAK" "$AUDIT_CHECK" <<'PY'
import base64, importlib.util, json, os, subprocess, sys
sys.path.insert(0, sys.argv[1])
import push_gate as pg
tmp, head, base, weak, audit_check = sys.argv[2:7]
repo = os.path.join(tmp, "repo")
fails = []
def check(name, cond):
    print(("✔ " if cond else "✖ ") + name); cond or fails.append(name)

tid = "T0001-seal"
d = os.path.join(tmp, "pm", "projects", "p", "tasks", tid); os.makedirs(d)
# Hand-written record: what an agent on the same uid can forge today.
json.dump({"id": tid, "project": os.path.realpath(repo),
           "verdicts": {"audit": {"verdict": "pass", "auditedHead": head, "reviewer": "antigravity"}},
           "dispatches": [{"kind": "audit", "agent": "antigravity", "at": "2026-11-15T00:00:00Z", "verdict": "pass",
                           "auditedHead": head, "auditBase": base, "edited": ["tests/test_a.sh"]}]},
          open(os.path.join(d, "task.json"), "w"))

# seal mode OFF: old behaviour
os.environ.pop("DEVKIT_VERDICT_SEAL_PUB", None)
if not os.path.lexists("/usr/local/etc/devkit/verdict-seal.pub"):
    check("mode off: unsealed record still counts (no lock-out before install)", pg.audited_head(repo, tid) == head)

# seal mode ON with a test key
import verdict_seal as vs
key = b"\x07" * 32
open(os.path.join(tmp, "seal.pub"), "w").write(base64.b64encode(vs.public_key(key)).decode())
os.environ["DEVKIT_VERDICT_SEAL_PUB"] = os.path.join(tmp, "seal.pub")
check("unsealed: audited_head None", pg.audited_head(repo, tid) is None)
check("unsealed: audited_heads []", pg.audited_heads(repo) == [])
check("unsealed: audit_scope None", pg.audit_scope(repo, tid) is None)
check("unsealed: no pass in scoped_audit_runs", not [r for r in pg.scoped_audit_runs(repo) if r[2] == "pass"])
spec = importlib.util.spec_from_file_location("ac", audit_check); ac = importlib.util.module_from_spec(spec); spec.loader.exec_module(ac)
check("unsealed: chain_audit None (cannot check), not False", ac.chain_audit(head, base, top=repo) is None)

tree = subprocess.run(["git", "-C", repo, "rev-parse", head + "^{tree}"], capture_output=True, text=True).stdout.strip()
def seal(b, edited, verdict="pass"):
    p = json.dumps({"v": 1, "head": head, "tree": tree, "base": b, "edited": edited, "verdict": verdict, "ts": "t", "nonce": "n"},
                   sort_keys=True, separators=(",", ":"))
    os.makedirs(os.path.dirname(vs.seal_path(head)), exist_ok=True)
    json.dump({"payload": p, "sig": base64.b64encode(vs.sign(key, p.encode())).decode()}, open(vs.seal_path(head), "w"))

seal(base, ["tests/test_a.sh"])
check("sealed: audited_head == head", pg.audited_head(repo, tid) == head)
check("sealed: audited_heads has it", pg.audited_heads(repo) == [(tid, head)])
check("sealed: audit_scope = signed scope", pg.audit_scope(repo, tid) == (base, ["tests/test_a.sh"]))
check("sealed: chain_audit True", ac.chain_audit(head, base, top=repo) is True)
# Finding 1: sealed audit of only the harmless commit (base = weakening commit): the signed base wins over task.json's base,
# and it is not an ancestor of merge-base(main, head), so the gate's scope check refuses it.
# (Plan review v2: the helper can be pointed at a fake repo whose trunk is the weakening commit, so the root refuses it.)
seal(weak, ["README"])
check("seal with base past merge-base(trunk, head): audited_head None", pg.audited_head(repo, tid) is None)
check("seal with base past merge-base(trunk, head): audit_scope None", pg.audit_scope(repo, tid) is None)
check("seal with base past merge-base(trunk, head): audited_heads []", pg.audited_heads(repo) == [])
# Signed scope wins over task.json, and seal mode needs no auditBase in the dispatch (pm_verdict writes verdict only there).
t = json.load(open(os.path.join(d, "task.json")))
t["dispatches"][0].pop("auditBase"); t["dispatches"][0].pop("verdict"); t["dispatches"][0]["edited"] = ["other"]
json.dump(t, open(os.path.join(d, "task.json"), "w"))
seal(base, ["tests/test_a.sh"])
check("signed scope used, task.json scope ignored", pg.audit_scope(repo, tid) == (base, ["tests/test_a.sh"]))
seal(base, ["tests/test_a.sh"], verdict="fail")
check("sealed fail: audited_head None", pg.audited_head(repo, tid) is None)
print("ALL OK" if not fails else f"FAILS={len(fails)}")
sys.exit(1 if fails else 0)
PY
