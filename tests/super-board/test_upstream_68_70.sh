#!/usr/bin/env bash
# Port từ upstream EricTechPro/super-board #68 và #70 (20/10):
# 1. #68 super-review-file-refactor.sh: bỏ tiền tố `<emoji> [<kind>] <scope>: ` nếu caller lỡ truyền vào --title
#    để không bị nhân đôi tiêu đề; giữ nguyên tiêu đề bắt đầu bằng từ ASCII (vd `Map [x] fields: keep order`).
# 2. #68 super-board-collect-state.py: hỗ trợ đường chạy không có fcntl (fallback msvcrt + file .token ngẫu nhiên).
# 3. #70 super-board-codex-lane.sh: kiểm tra toàn bộ JSON kết quả theo schema (chặn prUrl sai kiểu, key thừa,
#    priorFindings thiếu trường hoặc dùng bool thay vì int); khớp schema với STAGE_SCHEMA của super-board-wave.js.
# 4. #70 super-board-codex-wave.sh: 2 nhánh halt sớm (verification-readiness exit 9, skills-readiness exit 10)
#    trả đủ khóa prUrl và priorFindings như summary của workflow.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REFACTOR="$ROOT/.claude/bin/super-review-file-refactor.sh"
COLLECT_STATE="$ROOT/.claude/bin/super-board-collect-state.py"
CODEX_LANE="$ROOT/.claude/bin/super-board-codex-lane.sh"
CODEX_WAVE="$ROOT/.claude/bin/super-board-codex-wave.sh"
WAVE_JS="$ROOT/.claude/workflows/super-board-wave.js"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-upstream-6870.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/repo/.claude/skills" "$TMP/bare"

# --- 1. #68: super-review-file-refactor.sh không nhân đôi tiền tố refactor ---
cat > "$TMP/cfg.json" <<'JSON'
{
  "project": {"owner": "o", "number": 1},
  "repo": {"remote": "https://github.com/o/r.git"},
  "verify_commands": ["true"],
  "usage_fallback": "codex"
}
JSON
cat > "$TMP/body.md" <<'MD'
## Problem
Shallow seam.

## Context
- **Where:** `src/cart.py`

## Fix
Deepen module.
MD

cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" graphql "*) echo '[{"data":{"repository":{"issues":{"totalCount":0,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}]' ;;
  *" issue view "*) echo '{"number":7,"title":"t","body":"b","labels":[{"name":"bug"}]}' ;;
  *" label create "*) exit 0 ;;
  *" issue create "*)
    while [ $# -gt 0 ]; do
      if [ "$1" = "--title" ]; then
        printf '%s' "$2" > "$FAKE_DIR/last_title.txt"
        break
      fi
      shift
    done
    echo "https://github.com/o/r/issues/42"
    ;;
  *" project item-add "*) echo '{"id":"PVTI_1"}' ;;
  *" project view "*) echo '{"id":"PVT_1"}' ;;
  *" project field-list "*) echo '{"fields":[{"name":"Status","id":"PVTF_1","options":[{"name":"Backlog","id":"OPT_1"},{"name":"Ready","id":"OPT_2"}]}]}' ;;
  *" project item-edit "*) exit 0 ;;
  *) echo "unexpected gh: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0

bash "$REFACTOR" --config "$TMP/cfg.json" \
  --title "♻️ [refactor] cart: extract checkout seam" \
  --body-file "$TMP/body.md" \
  --fingerprint "cart|seam-1" >/dev/null 2>&1
got_title="$(cat "$TMP/last_title.txt" 2>/dev/null || true)"
[ "$got_title" = "♻️ [refactor] cart: extract checkout seam" ] \
  && ok "#68 refactor filer: bỏ tiền tố ♻️ [refactor] <scope>: bị lặp trong --title" \
  || fail "#68 refactor filer: got '$got_title', want '♻️ [refactor] cart: extract checkout seam'"

bash "$REFACTOR" --config "$TMP/cfg.json" \
  --title "Map [x] fields: keep order" \
  --body-file "$TMP/body.md" \
  --fingerprint "cart|seam-2" >/dev/null 2>&1
got_title2="$(cat "$TMP/last_title.txt" 2>/dev/null || true)"
[ "$got_title2" = "♻️ [refactor] cart: Map [x] fields: keep order" ] \
  && ok "#68 refactor filer: giữ nguyên tiêu đề bắt đầu bằng từ ASCII có [x] và dấu hai chấm" \
  || fail "#68 refactor filer ASCII: got '$got_title2', want '♻️ [refactor] cart: Map [x] fields: keep order'"

# --- 2. #68: super-board-collect-state.py chạy được khi không có fcntl (shim msvcrt + .token) ---
python3 - "$COLLECT_STATE" "$TMP" <<'PY'
import importlib.util, os, subprocess, sys, types
collect_py, tmp = sys.argv[1], sys.argv[2]
os.environ['SB_COLLECT_STATE_DIR'] = os.path.join(tmp, 'collect-state')

# Nạp subprocess trước khi cài shim msvcrt giả để tránh đụng probe _winapi của Python 3.12+
_ = subprocess.Popen
fake_msvcrt = types.ModuleType('msvcrt')
fake_msvcrt.LK_NBLCK = 2
def _locking(fd, mode, nbytes):
    return None
fake_msvcrt.locking = _locking
sys.modules['fcntl'] = None
sys.modules['msvcrt'] = fake_msvcrt

spec = importlib.util.spec_from_file_location('collect_state', collect_py)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert mod.fcntl is None, 'expected fcntl=None fallback'

key, lock_path, _ = mod.paths('o/r')
filer = os.path.join(tmp, 'filer.sh')
with open(filer, 'w') as f:
    f.write('#!/usr/bin/env bash\n'
            '[ -n "${SB_COLLECT_LOCK_TOKEN:-}" ] && [ -f "' + str(lock_path.with_suffix('.token')) + '" ]\n')
os.chmod(filer, 0o755)
fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
rc = mod.run_locked(fd, key, lock_path, [filer])
os.close(fd)
assert rc == 0, f'run_locked expected 0, got {rc}'
assert not lock_path.with_suffix('.token').exists(), 'token file must be cleaned up after run_locked'

# Token giả mạo phải bị từ chối
lock_path.with_suffix('.token').write_text('real-secret-token')
os.environ['SB_COLLECT_LOCK_HELD'] = key
os.environ['SB_COLLECT_LOCK_TOKEN'] = 'forged-token'
assert not mod.lock_held(key, lock_path), 'forged token must not be accepted'
os.environ['SB_COLLECT_LOCK_TOKEN'] = 'real-secret-token'
assert mod.lock_held(key, lock_path), 'matching token must be accepted'
lock_path.with_suffix('.token').unlink(missing_ok=True)
PY
[ $? -eq 0 ] && ok "#68 collect-state: fallback msvcrt + token file khi không có fcntl hoạt động đúng" \
  || fail "#68 collect-state: lỗi ở nhánh không có fcntl (msvcrt + token file)"

# --- 3. #70: super-board-codex-lane.sh validate toàn bộ schema & khớp STAGE_SCHEMA ---
python3 - "$CODEX_LANE" "$WAVE_JS" <<'PY'
import ast, json, re, subprocess, sys
from pathlib import Path

lane_text = Path(sys.argv[1]).read_text()
wave_text = Path(sys.argv[2]).read_text()
source = lane_text.split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]
wanted = {'counts', 'properties', 'schema', 'JSON_TYPES'}
nodes = [node for node in ast.parse(source).body
         if (isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id in wanted for t in node.targets))
         or (isinstance(node, ast.FunctionDef) and node.name == 'conforms')]
ns = {}
exec(compile(ast.Module(body=nodes, type_ignores=[]), 'codex-lane', 'exec'), ns)
assert 'conforms' in ns, 'missing conforms() in super-board-codex-lane.sh'
conforms, schema = ns['conforms'], ns['schema']

base = {'status': 'advanced', 'column': 'QA', 'detail': 'ok', 'prUrl': None, 'branch': 'issue-1', 'priorFindings': None}
assert conforms(base, schema), 'valid base payload rejected'
assert not conforms({**base, 'prUrl': 123}, schema), 'non-string prUrl must be rejected'
assert not conforms({**base, 'extra': 1}, schema), 'extra key must be rejected'
assert not conforms({**base, 'priorFindings': {'fixed': 1, 'noLongerApplies': 0}}, schema), 'missing notFixed must be rejected'
assert not conforms({**base, 'priorFindings': {'fixed': True, 'notFixed': 0, 'noLongerApplies': 0}}, schema), 'bool count must be rejected'
assert conforms({**base, 'priorFindings': {'fixed': 1, 'notFixed': 0, 'noLongerApplies': 2}}, schema), 'valid priorFindings rejected'

# Khớp schema của codex-lane với STAGE_SCHEMA trong super-board-wave.js
match = re.search(r'^const STAGE_SCHEMA = (\{.*?^\})$', wave_text, re.S | re.M)
assert match, 'STAGE_SCHEMA not found in super-board-wave.js'
stage = json.loads(subprocess.check_output(['node', '-e', 'process.stdout.write(JSON.stringify(' + match.group(1) + '))'], text=True))
lane_props, stage_props = schema['properties'], stage['properties']
assert lane_props['status']['enum'] == stage_props['status']['enum'], 'status enum mismatch'
assert sorted(lane_props) == sorted(stage_props), 'top-level property mismatch'
findings = next(opt for opt in lane_props['priorFindings']['anyOf'] if opt['type'] == 'object')
assert sorted(findings['properties']) == sorted(stage_props['priorFindings']['properties']), 'priorFindings property mismatch'
assert set(stage['required']) <= set(schema['required']), 'required keys mismatch'
PY
[ $? -eq 0 ] && ok "#70 codex-lane: conforms() chặn prUrl sai kiểu, key thừa, priorFindings thiếu trường hoặc kiểu bool" \
  || fail "#70 codex-lane: thiếu hoặc sai conforms() khi validate schema"

# --- 4. #70: super-board-codex-wave.sh trả đủ prUrl và priorFindings ở 2 nhánh halt sớm ---
git -C "$TMP/repo" init -q
git -C "$TMP/bare" init -q
for s in super-board super-build super-qa super-review; do
  mkdir -p "$TMP/repo/.claude/skills/$s"
  printf -- '---\nname: %s\ndescription: stub\n---\n' "$s" > "$TMP/repo/.claude/skills/$s/SKILL.md"
done
cat > "$TMP/unready.json" <<'JSON'
{
  "project": {"owner": "o", "number": 1},
  "repo": {"remote": "https://github.com/o/r.git"},
  "verify_commands": []
}
JSON
CARDS='[{"number":7,"status":"Ready","title":"t","labels":["bug"]}]'

check_wave_keys() {
  python3 - "$WAVE_JS" "$1" "$2" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
block = re.search(r'const summary = .*?return \{\n(.*?)\n\s*\}\n', text, re.S)
assert block, 'summary block not found'
keys = set(re.findall(r'^\s*(\w+):', block.group(1), re.M))
data = json.load(open(sys.argv[2]))
for card in data['cards']:
    missing, extra = sorted(keys - set(card)), sorted(set(card) - keys)
    assert not missing and not extra, f"{sys.argv[3]}: missing={missing} extra={extra}"
PY
}

(cd "$TMP/repo" && bash "$CODEX_WAVE" --config "$TMP/unready.json" --cards "$CARDS" --codex >"$TMP/out_ready.json" 2>/dev/null)
rc=$?
[ "$rc" -eq 9 ] && check_wave_keys "$TMP/out_ready.json" "halted-readiness" \
  && ok "#70 codex-wave: halt sớm verification-readiness (exit 9) có đủ prUrl và priorFindings" \
  || fail "#70 codex-wave: halt sớm verification-readiness thiếu prUrl/priorFindings (rc=$rc)"

(cd "$TMP/bare" && bash "$CODEX_WAVE" --config "$TMP/cfg.json" --cards "$CARDS" --codex >"$TMP/out_skills.json" 2>/dev/null)
rc=$?
[ "$rc" -eq 10 ] && check_wave_keys "$TMP/out_skills.json" "halted-skills" \
  && ok "#70 codex-wave: halt sớm skills-readiness (exit 10) có đủ prUrl và priorFindings" \
  || fail "#70 codex-wave: halt sớm skills-readiness thiếu prUrl/priorFindings (rc=$rc)"

echo
[ "$FAILS" -eq 0 ] && { echo "test_upstream_68_70: PASS"; exit 0; } || { echo "test_upstream_68_70: FAIL ($FAILS)"; exit 1; }
