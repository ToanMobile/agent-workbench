#!/usr/bin/env bash
# Regression test: hooks/proof_gate.sh (Stop hook) — a reply that opens with XONG needs both
# halves of rules/essentials.md "Every prompt" step 5, from this turn:
#   - a `post-fix-gate --run-tests --full` exit 0 on the CURRENT code (the gate's receipt in
#     .git/postfix-gate/full_pass.json, fingerprint = bin/tree_fp.py), and
#   - a real acceptance PNG: reports/proof-<yyyyMMdd-HHmmss>.png, PNG bytes, > 8 KB, newer
#     than the turn's user message.
# Any other status line is not checked. Never traps the session.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

REPO="$TMP/repo"; mkdir -p "$REPO/src" "$REPO/templates" "$REPO/reports"
( cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt && echo 'exit 0' > result.sh
  mkdir -p .agents && echo '{"profile":"android"}' > .agents/active-profile.json
  printf '.claude/audit-gate/\n' > .gitignore   # as agent-kit init writes it: an excluded path that is ignored
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}
JSON
  git add -A && git commit -qm init && echo "fun ok() = 2" > src/Core.kt )
TR="$TMP/transcript.jsonl"
# The turn started 2 s ago (the user's prompt); gate run and proof must be newer than that.
turn_start() { sleep 1; python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X"}}))' > "$TR"; }
# `--run-tests --full` on the current code; its exit-0 receipt is what XONG needs.
gate_full() { CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --run-tests --full --no-checklist >"$TMP/gate" 2>&1; }
png() { python3 - "$1" "$2" <<'PY'
import sys, zlib, struct, os
path, size = sys.argv[1], int(sys.argv[2])
sig = b"\x89PNG\r\n\x1a\n"
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
data = sig + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)) + chunk(b"IDAT", os.urandom(max(size - 60, 1))) + chunk(b"IEND", b"")
open(path, "wb").write(data)
PY
}
stop() { # <reply text> [stop_hook_active]
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-p","hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":sys.argv[3]=="1"}))' "$TR" "$1" "${2:-0}" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
reset() { rm -f "$REPO/.claude/audit-gate/proof_gate.state"; }

turn_start
stop "CHƯA XONG
Không có thiết bị online."; [ $? = 0 ] && ok "CHƯA XONG: not checked" || fail "CHƯA XONG blocked"

stop "XONG
Đã sửa lỗi X.
Gate exit 0"; rc=$?
[ "$rc" = 2 ] && grep -q "proof-" "$TMP/err" && grep -q -- "--full" "$TMP/err" \
  && ok "XONG with neither full gate nor PNG: blocked, names both" || fail "XONG without proof (rc=$rc)"

# Full gate exit 0 on this code, then the screenshot: the complete handover.
reset; turn_start; gate_full; g=$?
P="reports/proof-$(date +%Y%m%d-%H%M%S).png"; png "$REPO/$P" 20000   # stamp = capture time (proof-capture.py)
stop "**XONG**
Đã sửa lỗi X.
Gate exit 0 · ảnh $P · serial emulator-5554"; rc=$?
[ "$g" = 0 ] && [ "$rc" = 0 ] && ok "full gate exit 0 + fresh real PNG: allowed (the PNG does not invalidate the receipt)" \
  || fail "valid handover blocked (gate=$g rc=$rc err=$(head -3 "$TMP/err"))"

# PNG present, but the code changed after the full run.
reset; turn_start; gate_full
echo "fun ok() = 3" > "$REPO/src/Core.kt"
P2="reports/proof-20260924-101510.png"; png "$REPO/$P2" 20000
stop "XONG
ảnh $P2"; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "code changed after the full gate run: blocked" || fail "stale receipt accepted (rc=$rc err=$(head -3 "$TMP/err"))"

# Full run in an earlier turn only.
reset; gate_full; turn_start
P3="reports/proof-20260924-101520.png"; png "$REPO/$P3" 20000
stop "XONG
ảnh $P3"; rc=$?
[ "$rc" = 2 ] && grep -q "trước lượt" "$TMP/err" && ok "full gate run from an earlier turn: blocked" || fail "old receipt accepted (rc=$rc err=$(head -3 "$TMP/err"))"

# A failing full run leaves no receipt.
reset; echo 'exit 1' > "$REPO/result.sh"; (cd "$REPO" && git commit -qam red && echo "fun ok() = 4" > src/Core.kt)
turn_start; gate_full; g=$?
P4="reports/proof-20260924-101530.png"; png "$REPO/$P4" 20000
stop "XONG
ảnh $P4"; rc=$?
[ "$g" != 0 ] && [ "$rc" = 2 ] && grep -q -- "--full" "$TMP/err" && ok "full gate not exit 0: blocked" || fail "failing gate accepted (gate=$g rc=$rc)"
echo 'exit 0' > "$REPO/result.sh"; (cd "$REPO" && git commit -qam green && echo "fun ok() = 5" > src/Core.kt)

# PNG checks, with a valid full run in the turn.
reset; turn_start; gate_full
S="reports/proof-20260924-101501.png"; png "$REPO/$S" 3000
stop "XONG
ảnh $S"; rc=$?
[ "$rc" = 2 ] && grep -q "8 KB" "$TMP/err" && ok "PNG under 8 KB: blocked" || fail "small PNG not blocked (rc=$rc)"

reset
O="reports/proof-20260101-000000.png"; png "$REPO/$O" 20000; touch -t 202601010000 "$REPO/$O"; turn_start; gate_full
stop "XONG
ảnh $O"; rc=$?
[ "$rc" = 2 ] && grep -q "ảnh cũ" "$TMP/err" && ok "PNG older than the turn: blocked" || fail "old PNG not blocked (rc=$rc err=$(head -2 "$TMP/err"))"

reset; turn_start; gate_full
F="reports/proof-20260924-101502.png"; head -c 20000 /dev/urandom > "$REPO/$F"
stop "XONG
ảnh $F"; rc=$?
[ "$rc" = 2 ] && grep -q "PNG" "$TMP/err" && ok "not PNG bytes: blocked" || fail "fake PNG not blocked (rc=$rc)"

reset; turn_start; gate_full
stop "XONG
ảnh reports/proof-20260924-101599.png"; rc=$?
[ "$rc" = 2 ] && ok "cited PNG missing on disk: blocked" || fail "missing PNG not blocked (rc=$rc)"

# The image is required only when the change touches app source on a profile with a screen.
prof() { echo "{\"profile\":\"$1\"}" > "$REPO/.agents/active-profile.json"; (cd "$REPO" && git add -A && git commit -qm "profile $1"); }
reset; prof android; sleep 2   # the profile commit (it carries src/Core.kt) lands before the turn
mkdir -p "$REPO/docs"; echo "note" > "$REPO/docs/NOTE.md"
turn_start; gate_full; g=$?
stop "XONG
Đã cập nhật tài liệu.
Gate exit 0 · ảnh: không cần (không đổi source app)"; rc=$?
[ "$g" = 0 ] && [ "$rc" = 0 ] && ok "android, only docs changed: full gate exit 0 is enough, no image" \
  || fail "tooling-only change still asked for an image (gate=$g rc=$rc err=$(head -3 "$TMP/err"))"
(cd "$REPO" && git add -A && git commit -qm docs)

reset; prof backend; sleep 2; echo "fun ok() = 6" > "$REPO/src/Core.kt"
turn_start; gate_full; g=$?
stop "XONG
Đã sửa API.
Gate exit 0 · ảnh: không cần (profile backend)"; rc=$?
[ "$g" = 0 ] && [ "$rc" = 0 ] && ok "backend profile: full gate exit 0 is enough, no image" \
  || fail "backend asked for an image (gate=$g rc=$rc err=$(head -3 "$TMP/err"))"
(cd "$REPO" && git add -A && git commit -qm api)

reset; prof android; echo "fun ok() = 7" > "$REPO/src/Core.kt"
turn_start; gate_full
stop "XONG
Gate exit 0"; rc=$?
[ "$rc" = 2 ] && grep -q "ẢNH" "$TMP/err" && ok "android, app source changed, no image: blocked" || fail "app change without image accepted (rc=$rc)"

reset; turn_start; (cd "$REPO" && git add -A && git commit -qm "fix in the turn"); gate_full
stop "XONG
Gate exit 0"; rc=$?
[ "$rc" = 2 ] && grep -q "ẢNH" "$TMP/err" && ok "app source committed during the turn still needs the image" || fail "commit-then-XONG skipped the image (rc=$rc)"

# Review 2026-09-25: the waiver is decided by what is SURELY off-screen, never by an app-extension list.
for f in "app/src/main/res/drawable/logo.png" "Assets/Scenes/Main.unity" "app/src/main/java/acme/ui/tools/Toolbar.kt"; do
  reset; prof android; sleep 2; mkdir -p "$REPO/$(dirname "$f")"; echo "x$RANDOM" > "$REPO/$f"
  turn_start; gate_full; stop "XONG
Gate exit 0"; rc=$?
  [ "$rc" = 2 ] && grep -q "ẢNH" "$TMP/err" && ok "android, $f changed, no image: blocked" || fail "$f waived the image (rc=$rc)"
  (cd "$REPO" && git add -A && git commit -qm "$f")
done
reset; prof voice-assistant; sleep 2; echo "fun ok() = 8" > "$REPO/src/Core.kt"
turn_start; gate_full; stop "XONG
Gate exit 0"; rc=$?
[ "$rc" = 2 ] && grep -q "ẢNH" "$TMP/err" && ok "voice-assistant has a screen: image required" || fail "voice-assistant waived (rc=$rc)"
(cd "$REPO" && git add -A && git commit -qm va)
reset; prof backend; sleep 2; echo "fun ok() = 9" > "$REPO/src/Core.kt"
turn_start; gate_full; stop "XONG
Gate exit 0 · ảnh reports/proof-20260925-000001.png"; rc=$?
[ "$rc" = 2 ] && grep -q "không có file này" "$TMP/err" && ok "waived image, but a cited PNG that does not exist: blocked" || fail "bogus cited PNG passed (rc=$rc)"
reset; turn_start; stop "XONG
Gate exit 0"; rc=$?
[ "$rc" = 2 ] && ! grep -q "proof-capture" "$TMP/err" && ok "backend blocked on the gate only: no screenshot instruction" || fail "backend told to capture (rc=$rc)"
(cd "$REPO" && git add -A && git commit -qm be)

# Committing the gated code in the same turn keeps the receipt: the fingerprint is the content, not HEAD.
reset; prof backend; sleep 2; echo "fun ok() = 10" > "$REPO/src/Core.kt"
turn_start; gate_full; g=$?; (cd "$REPO" && git add -A && git commit -qm "gated change")
stop "XONG
Đã commit.
Gate exit 0 · ảnh: không cần (profile backend)"; rc=$?
[ "$g" = 0 ] && [ "$rc" = 0 ] && ok "full gate, then commit of the same code: XONG allowed" || fail "commit voided the receipt (gate=$g rc=$rc err=$(head -2 "$TMP/err"))"
reset; echo "fun ok() = 11" > "$REPO/src/Core.kt"; (cd "$REPO" && git commit -qam "edit after gate")
stop "XONG
Gate exit 0"; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "a different commit after the gate still voids it" || fail "edited commit accepted (rc=$rc)"

# Review 2 (2026-09-25): "changed in the turn" = everything since HEAD at the turn start, whatever
# moved HEAD (commit, merge, pull, reset); the profile read at the turn start; Markdown / test dirs
# waived only where they cannot be app content.
python3 - "$DEVKIT_DIR/bin" "$TMP/ir" <<'PYT' 2>"$TMP/ir.err" && ok "image_required: merges, profile switch, deep Markdown/test dirs, renames" || fail "image_required: $(tail -3 "$TMP/ir.err")"
import os, subprocess, sys, time
sys.path.insert(0, sys.argv[1]); import tree_fp
base = sys.argv[2]
def repo(name, profile="android"):
    d = os.path.join(base, name); os.makedirs(os.path.join(d, ".agents"))
    g = lambda *a: subprocess.run(["git", "-C", d, *a], check=True, capture_output=True)
    g("init", "-q"); g("config", "user.email", "t@t"); g("config", "user.name", "t")
    open(os.path.join(d, ".agents/active-profile.json"), "w").write('{"profile":"%s"}' % profile)
    os.makedirs(os.path.join(d, "app/src")); open(os.path.join(d, "app/src/Screen.kt"), "w").write("a\n")
    g("add", "-A"); g("commit", "-qm", "init"); time.sleep(1.1)
    return d, g
def write(d, rel, text="x\n"):
    os.makedirs(os.path.dirname(os.path.join(d, rel)) or d, exist_ok=True); open(os.path.join(d, rel), "w").write(text)
cases = []
for how in ("--no-ff", "--ff-only"):
    d, g = repo("merge" + how)
    g("checkout", "-qb", "feat"); write(d, "app/src/Screen.kt", "b\n"); g("commit", "-qam", "ui"); g("checkout", "-q", "-")
    time.sleep(1.1); start = time.time(); time.sleep(1.1)
    g("merge", "-q", how, "feat", "-m", "m")
    cases.append(("merge " + how + " of a UI change", tree_fp.image_required(d, start)[0], True))
d, g = repo("prof"); start = time.time(); time.sleep(1.1)
write(d, ".agents/active-profile.json", '{"profile":"backend"}'); write(d, "app/src/Screen.kt", "c\n")
cases.append(("profile switched to backend in the turn", tree_fp.image_required(d, start)[0], True))
for rel in ("src/content/blog/post.md", "src/pages/tests/index.tsx"):
    d, g = repo("deep" + str(len(cases))); start = time.time(); time.sleep(1.1); write(d, rel)
    cases.append((rel, tree_fp.image_required(d, start)[0], True))
d, g = repo("mv"); start = time.time(); time.sleep(1.1); os.makedirs(os.path.join(d, "tests")); g("mv", "app/src/Screen.kt", "tests/Screen.kt")
cases.append(("git mv of a screen into tests/", tree_fp.image_required(d, start)[0], True))
for rel in ("README.md", "docs/guide.md", "app/src/test/kotlin/FooTest.kt", "tests/test_x.py", "scripts/a.sh", "shared/src/commonTest/kotlin/X.kt"):
    d, g = repo("ok" + str(len(cases))); start = time.time(); time.sleep(1.1); write(d, rel)
    cases.append((rel + " (off-screen)", tree_fp.image_required(d, start)[0], False))
d, g = repo("be", "backend"); start = time.time(); time.sleep(1.1); write(d, "app/src/Screen.kt", "d\n")
cases.append(("backend profile set before the turn", tree_fp.image_required(d, start)[0], False))
bad = [f"{n}: required={got}, want {want}" for n, got, want in cases if got != want]
assert not bad, "; ".join(bad)
PYT

# Review 2: a proof re-dated with `touch` or copied to a new stamp is not this turn's screenshot.
reset; prof backend; sleep 2; echo "fun ok() = 12" > "$REPO/src/Core.kt"; (cd "$REPO" && git commit -qam pre)
reset; prof android; sleep 2
OLD="reports/proof-20260101-000000.png"; png "$REPO/$OLD" 20000
echo "fun ok() = 13" > "$REPO/src/Core.kt"; turn_start; gate_full
touch "$REPO/$OLD"
stop "XONG
ảnh $OLD"; rc=$?
[ "$rc" = 2 ] && grep -q "tên" "$TMP/err" && ok "old stamp re-dated by touch: blocked" || fail "touched old proof accepted (rc=$rc err=$(head -3 "$TMP/err"))"
NEWN="reports/proof-$(date +%Y%m%d-%H%M%S).png"; cp "$REPO/$OLD" "$REPO/$NEWN"
stop "XONG
ảnh $NEWN"; rc=$?
[ "$rc" = 2 ] && grep -q "trùng" "$TMP/err" && ok "old proof copied to a new stamp: blocked as a duplicate" || fail "copied proof accepted (rc=$rc err=$(head -3 "$TMP/err"))"
rm -f "$REPO/$OLD" "$REPO/$NEWN"; (cd "$REPO" && git add -A && git commit -qm c13)

# Review 2: the content fingerprint must not leave objects in the real object store.
head -c 300000 /dev/urandom > "$REPO/blob.bin"
before="$(cd "$REPO" && git count-objects -v | awk '/^(count|size):/{s+=$2} END{print s}')"
python3 "$DEVKIT_DIR/bin/tree_fp.py" "$REPO" >/dev/null
after="$(cd "$REPO" && git count-objects -v | awk '/^(count|size):/{s+=$2} END{print s}')"
[ "$before" = "$after" ] && ok "fingerprint writes no object into .git/objects" || fail "object store grew: $before -> $after"
rm -f "$REPO/blob.bin"

# Loop guard: 2 blocks for the same session, then the stop goes through with a warning.
reset; turn_start
stop "XONG"; r1=$?; stop "XONG" 1; r2=$?; stop "XONG" 1; r3=$?
[ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$r3" = 0 ] && grep -q systemMessage "$TMP/out" \
  && ok "loop guard: releases after 2 blocks with a user-visible warning" || fail "loop guard (r1=$r1 r2=$r2 r3=$r3)"

reset; turn_start
PROOF_GATE=0 stop "XONG"; [ $? = 0 ] && grep -q "PROOF_GATE=0" "$REPO/.claude/audit-gate/proof_gate.log" \
  && ok "PROOF_GATE=0 skips, logged" || fail "escape hatch"

if [ "$FAILS" -ne 0 ]; then echo "proof gate: $FAILS FAILED"; exit 1; fi
echo "proof gate: all checks passed"
