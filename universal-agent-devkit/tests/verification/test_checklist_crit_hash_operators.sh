#!/usr/bin/env bash
# Regression test (issue #18): _crit_hash() ran norm_title(), whose \w+ regex drops "<", ">", "=", so the opposite criteria
# "Độ trễ < 300ms" and "Độ trễ > 300ms" shared a hash and a reversed criterion kept its PASS. The hash must keep comparison
# operators; a REQ locked with the old hash must still match (no forced --reason).
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$DEVKIT_DIR/bin" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import regression_checklist as rc

fails = 0
def check(ok, name):
    global fails
    print(("✔ " if ok else "✖ ") + name)
    fails += 0 if ok else 1

h = rc._crit_hash
check(h(["Độ trễ < 300ms"]) != h(["Độ trễ > 300ms"]), "< and > give different hashes")
check(h(["Độ trễ <= 300ms"]) != h(["Độ trễ < 300ms"]), "<= and < give different hashes")
check(h(["x == 1"]) != h(["x != 1"]), "== and != give different hashes")
check(h(["Độ  trễ < 300ms"]) == h(["độ trễ < 300ms"]), "case and spacing still do not count")

# backward compatibility: a REQ locked under the old hash is not reported as changed
data = {"items": {}}
rid, _ = rc.register_req(data, "Latency", ["Độ trễ < 300ms"], req_id=None)
data["items"][rid]["criteria_hash"] = rc._crit_hash_legacy(["Độ trễ < 300ms"])
try:
    rc.register_req(data, "Latency", ["Độ trễ < 300ms"])
    check(data["items"][rid]["criteria_hash"] == h(["Độ trễ < 300ms"]), "legacy-hash REQ re-registered unchanged: hash upgraded, no --reason")
except ValueError as e:
    check(False, "legacy-hash REQ re-registered unchanged raised: %s" % e)
try:
    rc.register_req(data, "Latency", ["Độ trễ > 300ms"])
    check(False, "a reversed criterion needs --reason")
except ValueError:
    check(True, "a reversed criterion needs --reason")

print("✅ test_checklist_crit_hash_operators: all passed" if not fails else "❌ test_checklist_crit_hash_operators: %d failed" % fails)
sys.exit(1 if fails else 0)
PY
