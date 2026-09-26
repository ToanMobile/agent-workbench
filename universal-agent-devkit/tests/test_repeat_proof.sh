#!/usr/bin/env bash
# Regression test: a bug measured on the car (automotive, GeelyEx2 2026-09-26: "tôi tự test
# tay 5–6 lần liên tục vẫn còn fail") is PASS only with a repeat-run proof newer than its
# fix proof — ≥3 measured runs passed and none failed (scripts/tools/xe-chay-lap.py
# ket-qua.json: [{kich_ban, lan, dat, khong_do_duoc, …}]). A green test alone is NEEDS_CAR.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/proj/.agents" "$TMP/proj/reports/xe-lap/a" "$TMP/proj/reports/xe-lap/b" \
         "$TMP/proj/reports/xe-lap/c" "$TMP/proj/reports/xe-lap/d"

run() { # ok|fail list for one scenario → ket-qua.json in dir $1
  python3 - "$@" <<'PY'
import json, sys
d, runs = sys.argv[1], sys.argv[2:]
out = [{"kich_ban": "VM-cold", "lan": i + 1, "dat": r == "ok", "khong_do_duoc": r == "kdd"}
       for i, r in enumerate(runs)]
json.dump(out, open(d + "/ket-qua.json", "w"))
PY
}
run "$TMP/proj/reports/xe-lap/a" ok ok ok ok ok
run "$TMP/proj/reports/xe-lap/b" ok ok fail ok ok
run "$TMP/proj/reports/xe-lap/c" ok kdd ok
run "$TMP/proj/reports/xe-lap/d" ok ok ok
touch -t 202001010000 "$TMP/proj/reports/xe-lap/d/ket-qua.json"   # older than the fix proof

DEVKIT_DIR="$DEVKIT_DIR" P="$TMP/proj" python3 - <<'PY'
import contextlib, io, json, os, sys, time
sys.path.insert(0, os.path.join(os.environ["DEVKIT_DIR"], "bin"))
import regression_checklist as rc
from pathlib import Path
P = Path(os.environ["P"])
fails = 0
def check(name, want, got):
    global fails
    print(("✔ " if want == got else "✖ ") + name + ("" if want == got else f": {got}, expected {want}"))
    fails += want != got

now = time.time()
data = rc.load(P)
data["items"]["REG-1"] = {"id": "REG-1", "kind": "test", "command": "true",
                          "last": {"status": "PASS", "ts": now, "at": rc._now()}}
data["items"]["BUG-1"] = {"id": "BUG-1", "kind": "bug", "title": "split screen", "tests": ["REG-1"],
                          "fixed": True, "state": "confirmed",
                          "red_proof": {"status": "PROVEN", "ts": now - 60}}
data["items"]["BUG-2"] = dict(data["items"]["BUG-1"], id="BUG-2", title="other")
rc.save(P, data)

def status(bid):
    d = rc.load(P)
    return rc.effective_status(d, d["items"][bid])

def cli(*argv):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        try:
            code = rc.main(["--project", str(P)] + list(argv))
        except SystemExit as e:   # argparse: unknown option / command
            code = e.code
    return code, buf.getvalue()

check("green test + PROVEN, not a car bug → PASS", "PASS", status("BUG-1"))
check("add --on-car flags the row", 0, cli("add", "split screen", "--id", "BUG-1", "--fixed", "--on-car")[0])
check("car bug without a repeat run → NEEDS_CAR", "NEEDS_CAR", status("BUG-1"))
code, out = cli("repeat", "BUG-1", str(P / "reports/xe-lap/b/ket-qua.json"))
check("a failed run in the repeat → NEEDS_CAR", "NEEDS_CAR", status("BUG-1"))
check("  … and the command says so (exit 1)", 1, code)
cli("repeat", "BUG-1", str(P / "reports/xe-lap/c/ket-qua.json"))
check("2 measured passes (1 unmeasured) → NEEDS_CAR", "NEEDS_CAR", status("BUG-1"))
cli("repeat", "BUG-1", str(P / "reports/xe-lap/d/ket-qua.json"))
check("3 passes older than the fix proof → NEEDS_CAR", "NEEDS_CAR", status("BUG-1"))
code, out = cli("repeat", "BUG-1", str(P / "reports/xe-lap/a/ket-qua.json"))
check("5/5 passes after the fix → PASS", "PASS", status("BUG-1"))
check("  … exit 0", 0, code)
check("repeat on a row without on_car flags it too (failed run: exit 1)", 1,
      cli("repeat", "BUG-2", str(P / "reports/xe-lap/b/ket-qua.json"))[0])
check("  … BUG-2 → NEEDS_CAR", "NEEDS_CAR", status("BUG-2"))
check("unknown scenario → error", 1, cli("repeat", "BUG-1", str(P / "reports/xe-lap/a/ket-qua.json"),
                                         "--scenario", "NOPE")[0])
d = rc.load(P); rc.render(P, d)
check("dashboard lists NEEDS_CAR with the command", True,
      "agent-kit bugs repeat" in (P / ".agents/CHECKLIST.md").read_text(encoding="utf-8"))
# The checklist journal (restore after an out-of-band rollback) must see a lost car flag or
# repeat proof: without on_car the row silently turns PASS (review 2026-09-26).
good = rc.load(P)
cur = json.loads(json.dumps(good))
cur["items"]["BUG-1"].pop("on_car")
check("losses() names a lost on_car", True, any("on_car" in x for x in rc.losses(good, cur, ())))
cur = json.loads(json.dumps(good))
cur["items"]["BUG-1"]["repeat_proof"] = dict(cur["items"]["BUG-1"]["repeat_proof"], ts=1.0)
check("losses() names an older repeat_proof", True, any("repeat_proof" in x for x in rc.losses(good, cur, ())))
cur["items"]["BUG-1"]["on_car"] = False
rc.merge_snapshot(good, cur, ())
check("restore brings back the newer repeat_proof", good["items"]["BUG-1"]["repeat_proof"]["ts"],
      cur["items"]["BUG-1"]["repeat_proof"]["ts"])
check("restore brings back on_car", True, cur["items"]["BUG-1"].get("on_car"))
sys.exit(1 if fails else 0)
PY
