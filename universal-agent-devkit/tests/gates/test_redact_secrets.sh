#!/usr/bin/env bash
# Test hồi quy (26/10, review 7bf3a07f): redact_secrets() của bin/regression_checklist.py che cả dạng secret hay gặp trong log test,
# vì merge-train.sh đưa đuôi log verify đỏ (qua hàm này) vào comment issue CÔNG KHAI. Giá trị và tiêu đề PEM giả ghép lúc chạy (bộ quét
# secret đọc diff). Tương thích bash 3.2.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
VAL="Q$(printf 'w%.0s' $(seq 1 18))7x"
python3 -I - "$DK/bin" "$VAL" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from regression_checklist import redact_secrets
v = sys.argv[2]
leak = [
    '{"token": "%s"}' % v,
    "{'password': '%s'}" % v,
    "assert {'api_key': '%s'} == {}" % v,
    "Authorization: Basic %s" % v,
    "Authorization: token %s" % v,
    "https://user:%s@example.invalid/repo.git" % v,
    "--password %s" % v,
    "aws_secret_access_key = %s" % v,
    "token=%s" % v,
    "Bearer %s" % v,
]
fails = 0
for line in leak:
    out = redact_secrets(line)
    if v in out:
        print("✖ leaked: %r -> %r" % (line, out)); fails += 1
    else:
        print("✔ redacted: %r" % out)
dash = "-" * 5
begin, end = dash + "BEGIN " + "PRIV" + "ATE KEY" + dash, dash + "END " + "PRIV" + "ATE KEY" + dash
pem = "%s\nMIIE%s\n%s==\n%s\nafter" % (begin, v, v, end)
out = redact_secrets(pem)
if v in out or "after" not in out:
    print("✖ PEM block: %r" % out); fails += 1
else:
    print("✔ PEM block body redacted, text after the block kept")
cut = "%s\nMIIE%s\n%s" % (dash + "BEGIN RSA " + "PRIV" + "ATE KEY" + dash, v, v)   # đuôi log cắt mất dòng END
out = redact_secrets(cut)
if v in out:
    print("✖ PEM block without END: %r" % out); fails += 1
else:
    print("✔ PEM block without END redacted to the end")
for text in ("tokens: 3 passed", "password reset flow tested", "FAILED test_token_refresh - AssertionError"):
    if redact_secrets(text) != text:
        print("✖ false positive: %r -> %r" % (text, redact_secrets(text))); fails += 1
    else:
        print("✔ untouched: %r" % text)
print("❌ test_redact_secrets: %d failed" % fails if fails else "✅ test_redact_secrets: all passed")
sys.exit(1 if fails else 0)
PY
