#!/bin/bash
# #870 (tách từ #742, PR A6): hai lỗi mất / trùng dữ liệu bài học của bin/instincts.py.
# (a) `archive --apply` cắt instincts.md (truncate) rồi mới ghi phần giữ lại: lỗi ghi (ENOSPC, tiến trình chết) giữa hai bước
#     làm mất mọi mục chưa chuyển sang archive. Bản sửa ghi bản sao đã fsync `instincts.md.archive-bak` trước khi cắt.
#     Test giả lỗi ghi: `open` trong module trả một lớp bọc cho instincts.md, write() sau truncate() ném OSError.
# (b) `promote` cấp id mới chỉ theo instincts.md của profile, bỏ qua instincts-archive.md bên cạnh ⇒ dùng lại id đã archive.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D" || exit 1
ERRORS=0
fail() { echo "FAIL: $1"; ERRORS=$((ERRORS+1)); }
ok() { echo "OK: $1"; }

NOW=$(date +%s)
iso() { python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime($NOW - int(sys.argv[1])*86400)))" "$1"; }
day() { python3 -c "import time,sys; print(time.strftime('%Y-%m-%d', time.localtime($NOW - int(sys.argv[1])*86400)))" "$1"; }

echo "--- (a) archive --apply: a failed rewrite of instincts.md keeps the old text in .archive-bak ---"
mkdir -p A/.agents A/.claude/audit-gate
{
  printf '# Instincts\n\n---\n\n## 1. Active\n'
  printf '\n### [INSTINCT-001] Seen Trap\n- **Found on:** %s\n- **Symptom:** s 001\n\n---\n' "$(day 90)"
  printf '\n### [INSTINCT-002] Stale Trap\n- **Found on:** %s\n- **Symptom:** s 002\n\n---\n' "$(day 90)"
} > A/.agents/instincts.md
{
  echo "{\"ts\": \"$(iso 60)\", \"session\": \"s\", \"prompt_sha1\": \"x\", \"instinct_ids\": [], \"instinct_refs\": []}"
  echo "{\"ts\": \"$(iso 3)\", \"session\": \"s\", \"prompt_sha1\": \"y\", \"instinct_ids\": [\"INSTINCT-001\"], \"instinct_refs\": [{\"id\": \"INSTINCT-001\", \"file\": \".agents/instincts.md\", \"line\": 7}]}"
} > A/.claude/audit-gate/surfaced.jsonl
cp A/.agents/instincts.md before.md

CLAUDE_PROJECT_DIR="$D/A" python3 -I - "$DEVKIT_ROOT/bin/instincts.py" "$D/A/.agents/instincts.md" > a.out 2>&1 <<'PY'
import importlib.machinery, importlib.util, os, sys
src, target = sys.argv[1], os.path.realpath(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("instincts_under_test", src)
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(mod)

class FailAfterTruncate:
    """Bọc file instincts.md: write() sau truncate() ném OSError, như đĩa đầy hay tiến trình chết giữa hai bước."""
    def __init__(self, f):
        self._f, self._cut = f, False
    def __enter__(self):
        self._f.__enter__()
        return self
    def __exit__(self, *exc):
        return self._f.__exit__(*exc)
    def truncate(self, *a):
        self._cut = True
        return self._f.truncate(*a)
    def write(self, s):
        if self._cut:
            raise OSError(28, "No space left on device (test)")
        return self._f.write(s)
    def __getattr__(self, name):
        return getattr(self._f, name)

real_open = open
def fake_open(path, *a, **k):
    f = real_open(path, *a, **k)
    return FailAfterTruncate(f) if os.path.realpath(str(path)) == target else f
mod.open = fake_open
rc = mod.main(["archive", "--days", "30", "--apply"])
print("rc=%s" % rc)
PY
grep -q '^rc=2' a.out && ok "archive --apply reports the write error (rc=2)" || fail "archive did not report the write error: $(tail -3 a.out)"
BAK=A/.agents/instincts.md.archive-bak
if [ -f "$BAK" ] && cmp -s before.md "$BAK"; then ok "old instincts.md text survives in .archive-bak"
else fail "the old text is lost: instincts.md is $(wc -c < A/.agents/instincts.md | tr -d ' ') bytes and no .archive-bak holds it"; fi
grep -q 'INSTINCT-002' A/.agents/instincts-archive.md 2>/dev/null && ok "the stale entry reached the archive first" \
  || fail "INSTINCT-002 is not in the archive"

echo "--- (c) a re-run after the failure refuses instead of reporting success on the 0-byte file ---"
CLAUDE_PROJECT_DIR="$D/A" python3 -I "$DEVKIT_ROOT/bin/instincts.py" archive --days 30 --apply > c.out 2>&1; RC=$?
if [ "$RC" -eq 2 ] && grep -q 'archive-bak' c.out; then ok "re-run refuses (rc=2) and names the leftover .archive-bak"
else fail "re-run after the failure: rc=$RC, expected 2 naming .archive-bak: $(tail -2 c.out)"; fi
cmp -s before.md "$BAK" && ok ".archive-bak still holds the old text" || fail ".archive-bak changed or vanished after the re-run"

echo "--- (d) a later archive with a stale entry does not overwrite or delete the leftover .archive-bak ---"
printf '\n### [INSTINCT-003] Later Stale\n- **Found on:** %s\n- **Symptom:** s 003\n\n---\n' "$(day 90)" >> A/.agents/instincts.md
CLAUDE_PROJECT_DIR="$D/A" python3 -I "$DEVKIT_ROOT/bin/instincts.py" archive --days 30 --apply > d.out 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "archive refuses (rc=2) while .archive-bak is left" || fail "archive ran over the leftover .archive-bak: rc=$RC"
cmp -s before.md "$BAK" && ok ".archive-bak is not overwritten or deleted" || fail "the only copy of the old text in .archive-bak is gone"
grep -q 'INSTINCT-003' A/.agents/instincts.md && ok "instincts.md is untouched" || fail "INSTINCT-003 left instincts.md"

echo "--- (e) add while .archive-bak is left skips the ids it holds ---"
mkdir -p F/.agents
: > F/.agents/instincts.md
printf '# Instincts\n\n---\n\n### [INSTINCT-001] One\n- **Rule:** r\n\n---\n\n### [INSTINCT-009] Nine\n- **Rule:** r\n' > F/.agents/instincts.md.archive-bak
CLAUDE_PROJECT_DIR="$D/F" python3 -I "$DEVKIT_ROOT/bin/instincts.py" add "Fresh Trap" --rule "r" --file "$D/F/.agents/instincts.md" > e.out 2>&1 \
  || fail "add exit $?: $(tail -3 e.out)"
NEWID="$(grep -o '### \[INSTINCT-[0-9]*\] Fresh Trap' F/.agents/instincts.md | grep -o '[0-9][0-9]*' | head -1)"
if [ -n "$NEWID" ] && [ "$((10#$NEWID))" -gt 9 ]; then ok "add takes id $NEWID after the ids in .archive-bak"
else fail "add id '$NEWID' reuses an id held by .archive-bak"; fi

echo "--- (f) a failed .archive-bak write changes nothing: no archive append, no partial copy ---"
mkdir -p G/.agents G/.claude/audit-gate
cp before.md G/.agents/instincts.md
cp A/.claude/audit-gate/surfaced.jsonl G/.claude/audit-gate/surfaced.jsonl
CLAUDE_PROJECT_DIR="$D/G" python3 -I - "$DEVKIT_ROOT/bin/instincts.py" "$D/G/.agents/instincts.md.archive-bak" > f.out 2>&1 <<'PY2'
import importlib.machinery, importlib.util, os, sys
src, bak = sys.argv[1], os.path.realpath(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("instincts_under_test", src)
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(mod)

class FailWrite:
    """Bọc file bản sao (.archive-bak hoặc file tạm của nó): write() ném OSError như đĩa đầy."""
    def __init__(self, f):
        self._f = f
    def __enter__(self):
        self._f.__enter__()
        return self
    def __exit__(self, *exc):
        return self._f.__exit__(*exc)
    def write(self, s):
        raise OSError(28, "No space left on device (test)")
    def __getattr__(self, name):
        return getattr(self._f, name)

real_open = open
def fake_open(path, *a, **k):
    f = real_open(path, *a, **k)
    return FailWrite(f) if os.path.realpath(str(path)).startswith(bak) else f
mod.open = fake_open
rc = mod.main(["archive", "--days", "30", "--apply"])
print("rc=%s" % rc)
PY2
grep -q '^rc=2' f.out && ok "a failed copy write reports rc=2" || fail "copy write failure not reported: $(tail -3 f.out)"
cmp -s before.md G/.agents/instincts.md && ok "instincts.md is unchanged" || fail "instincts.md changed although the copy failed"
grep -q 'INSTINCT-002' G/.agents/instincts-archive.md 2>/dev/null && fail "INSTINCT-002 was appended to the archive although the copy failed (a re-run duplicates it)" \
  || ok "the archive got nothing"
ls G/.agents | grep -q 'archive-bak' && fail "a partial copy is left: $(ls G/.agents | grep archive-bak)" || ok "no .archive-bak or temp file is left"

echo "--- (g) a successful archive --apply removes its copy ---"
CLAUDE_PROJECT_DIR="$D/G" python3 -I "$DEVKIT_ROOT/bin/instincts.py" archive --days 30 --apply > g.out 2>&1 || fail "archive exit $?: $(tail -3 g.out)"
grep -q 'INSTINCT-002' G/.agents/instincts-archive.md 2>/dev/null && ok "INSTINCT-002 moved to the archive" || fail "INSTINCT-002 not archived"
ls G/.agents | grep -q 'archive-bak' && fail "copy left after a successful archive" || ok "no copy left after success"

echo "--- (b) promote skips ids taken by the profile's instincts-archive.md ---"
mkdir -p K/profiles/android P/.agents/local
printf '# Android\n\n### [INSTINCT-001] Live Trap\n- **Rule:** r\n' > K/profiles/android/instincts.md
printf '# Archive\n\n---\n\n### [INSTINCT-050] Archived Trap\n- **Rule:** x\n' > K/profiles/android/instincts-archive.md
printf '# Queue\n\n---\n\n### [INSTINCT-007] Archive Id Trap\n- **Rule:** R9\n' > P/.agents/local/upstream-queue.md
python3 -I "$DEVKIT_ROOT/bin/instincts.py" promote --from "$D/P" --profile android --kit "$D/K" > b.out 2>&1 \
  || fail "promote exit $?: $(tail -3 b.out)"
NEWID="$(grep -o '### \[INSTINCT-[0-9]*\] Archive Id Trap' K/profiles/android/instincts.md | grep -o '[0-9][0-9]*' | head -1)"
if [ -n "$NEWID" ] && [ "$((10#$NEWID))" -gt 50 ]; then ok "promoted id $NEWID comes after the archived INSTINCT-050"
else fail "promoted id '$NEWID' reuses an id of instincts-archive.md"; fi

if [ $ERRORS -gt 0 ]; then echo "$ERRORS FAILED"; exit 1; fi
echo "ALL PASS"
