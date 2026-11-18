#!/usr/bin/env bash
# super-collect dedupe: một issue đã đóng dạng NOT_PLANNED (chủ repo đã bác) trùng fingerprint thì không
# được tạo lại thẻ. Trước bản sửa: truy vấn lịch sử issue (super-board-github-read.py --issue-history) chỉ lấy
# number/state/body, nên filer coi mọi hit đã đóng là "recurrence" và mở lại ý tưởng đã bác ở mỗi lượt collect.
# Hit đóng dạng COMPLETED vẫn là recurrence (lỗi tái phát sau khi sửa) — phần đó không được đổi.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
FILER="$ROOT/.claude/skills/super-collect/scripts/super-collect-file.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; fails=$((fails + 1)); }

# 1. Truy vấn lịch sử issue phải xin stateReason.
python3 - "$READ" <<'PY' || fails=$((fails + 1))
import importlib.util, sys
spec = importlib.util.spec_from_file_location('ghread', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
seen = []
def fake_read(args, kind, *a, **k):
    seen.append((args, kind))
    return None, [{'data': {'repository': {'issues': {'nodes': []}}}}]
m.read = fake_read
sys.argv = ['x', '--issue-history', 'o/r']
m.main()
query = next(a for a in seen[0][0] if a.startswith('query='))
if 'stateReason' in query:
    print('✔ issue-history query asks for stateReason')
else:
    print('✖ issue-history query lacks stateReason:', query); sys.exit(1)
PY

# 2. Filer: bin giả cho các helper của board.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/super-board-github-read.py" <<'PY'
import json, os, sys
a = sys.argv[1:]
if '--check' in a: sys.exit(0)
if '--issue-history' in a: print(open(os.environ['FAKE_HISTORY']).read()); sys.exit(0)
if 'fields' in a: print(json.dumps({'fields': [{'name': 'Status', 'id': 'F', 'options': [{'name': 'Backlog', 'id': 'B'}]}]})); sys.exit(0)
sys.exit(0)
PY
cat > "$BIN/super-board-collect-state.py" <<'PY'
import hashlib, os, sys
a = sys.argv[1:]
if '--lock' in a:
    repo = a[a.index('--repo') + 1]
    os.environ['SB_COLLECT_LOCK_HELD'] = hashlib.sha256(repo.lower().encode()).hexdigest()
    cmd = a[a.index('--') + 1:]
    os.execvp('bash', ['bash'] + cmd)
sys.exit(0)
PY
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/super-qa-file-bug.sh"
printf '#!/usr/bin/env bash\necho filed >> "%s/filed"\necho 99\n' "$TMP" > "$BIN/super-review-file-refactor.sh"
chmod +x "$BIN"/*.sh
printf '{"project":{"owner":"o","number":1,"title":"t"},"repo":{"remote":"git@github.com:o/r.git"}}\n' > "$TMP/cfg.json"
printf '## Problem\nx\n## Context\ny\n## Fix\nz\n' > "$TMP/body.md"
FP='arch|reader|shallow-module'

run_filer() { # $1 = history json, rest = extra args
  printf '%s' "$1" > "$TMP/history.json"; shift
  FAKE_HISTORY="$TMP/history.json" SUPER_BOARD_BIN="$BIN" bash "$FILER" --config "$TMP/cfg.json" --type refactor \
    --source architecture --title "Reader module too shallow" --body-file "$TMP/body.md" --fingerprint "$FP" "$@"
}
hist() { printf '[{"number":%s,"state":"CLOSED","stateReason":"%s","body":"x %s y"}]' "$1" "$2" "$FP"; }

out=$(run_filer "$(hist 7 NOT_PLANNED)" 2>&1); rc=$?
case "$out" in "out-of-scope|#7|"*) [ "$rc" -eq 0 ] && ok "dry-run: NOT_PLANNED hit → out-of-scope" || bad "dry-run rc=$rc";;
  *) bad "dry-run NOT_PLANNED hit printed: $out";; esac

rm -f "$TMP/filed"
out=$(run_filer "$(hist 7 NOT_PLANNED)" --yes 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$(echo "$out" | tail -1)" = 7 ] && [ ! -e "$TMP/filed" ]; then ok "--yes: NOT_PLANNED hit files nothing, prints #7"
else bad "--yes NOT_PLANNED: rc=$rc out=$out filed=$([ -e "$TMP/filed" ] && echo yes || echo no)"; fi

out=$(run_filer "$(hist 8 COMPLETED)" 2>&1)
case "$out" in "recurrence|#8|"*) ok "dry-run: COMPLETED hit stays recurrence";; *) bad "COMPLETED hit printed: $out";; esac

# Several closed hits: the NEWEST closed issue decides (GraphQL returns oldest first).
two() { printf '[{"number":%s,"state":"CLOSED","stateReason":"%s","body":"%s"},{"number":%s,"state":"CLOSED","stateReason":"%s","body":"%s"}]' \
  "$1" "$2" "$FP" "$3" "$4" "$FP"; }
out=$(run_filer "$(two 5 COMPLETED 9 NOT_PLANNED)" 2>&1)
case "$out" in "out-of-scope|#9|"*) ok "older COMPLETED + newer NOT_PLANNED -> out-of-scope #9";; *) bad "COMPLETED#5+NOT_PLANNED#9 printed: $out";; esac
out=$(run_filer "$(two 5 NOT_PLANNED 9 COMPLETED)" 2>&1)
case "$out" in "recurrence|#9|"*) ok "older NOT_PLANNED + newer COMPLETED -> recurrence #9";; *) bad "NOT_PLANNED#5+COMPLETED#9 printed: $out";; esac

# An open hit always wins: duplicate, even when an older issue was rejected.
out=$(run_filer "[{\"number\":3,\"state\":\"CLOSED\",\"stateReason\":\"NOT_PLANNED\",\"body\":\"$FP\"},{\"number\":4,\"state\":\"OPEN\",\"stateReason\":null,\"body\":\"$FP\"}]" 2>&1)
case "$out" in "duplicate|#4|"*) ok "open hit + rejected closed hit -> duplicate #4";; *) bad "open+NOT_PLANNED printed: $out";; esac

exit $((fails > 0))
