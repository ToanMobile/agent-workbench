#!/usr/bin/env bash
# Lượt run 2026-11-09 22:59 dừng ở pre-flight (exit 79): `issues-closed` từ chối cả danh sách vì một issue đóng
# với stateReason DUPLICATE ("closed issue reason missing"). DUPLICATE là giá trị hợp lệ của GitHub
# (IssueStateReason) nên bộ kiểm phải nhận; giá trị lạ hoặc thiếu khoá vẫn phải bị từ chối.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"

python3 - "$READ" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('ghread', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
row = lambda r: {'number': 7, 'title': 't', 'body': '', 'stateReason': r}
fails = 0
for reason in ('COMPLETED', 'NOT_PLANNED', 'DUPLICATE', 'REOPENED', None):
    try:
        m.validate(json.dumps([row(reason)]), 'issues-closed'); print('✔ accepts', reason)
    except ValueError as e:
        print('✖ rejects', reason, '-', e); fails += 1
for bad in ([row('BOGUS')], [{'number': 7, 'title': 't', 'body': ''}]):
    try:
        m.validate(json.dumps(bad), 'issues-closed'); print('✖ accepts invalid', bad); fails += 1
    except ValueError:
        print('✔ rejects invalid', bad[0].get('stateReason', '<no key>'))
sys.exit(1 if fails else 0)
PY
