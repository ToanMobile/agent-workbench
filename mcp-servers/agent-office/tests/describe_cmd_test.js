'use strict';
// node tests/describe_cmd_test.js — chạy thật describeCmd cắt từ web/index.html: lệnh shell thành câu tự nhiên, không chép nguyên lệnh.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'web', 'index.html'), 'utf8');
const grab = (re, what) => { const m = html.match(re); assert.ok(m, 'không tìm thấy ' + what + ' trong index.html'); return m[0]; };
const src = [
  grab(/function clip\(s, n\) \{[^\n]*\n/, 'clip'),
  grab(/const baseName = [^\n]*\n/, 'baseName'),
  grab(/const GIT_VERB = \{[\s\S]*?\};\n/, 'GIT_VERB'),
  grab(/const prettyName = [^\n]*\n/, 'prettyName'),
  grab(/function describeCmd\(cmd\) \{[\s\S]*?\n\}\n/, 'describeCmd'),
].join('\n');
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src + '\nthis.describeCmd = describeCmd;', ctx);
const d = ctx.describeCmd;

const cases = [
  ['python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --brief', 'chạy gate kiểm thử'],
  ['python3 -m unittest tests.test_agent_workload 2>&1 | tail -5', 'chạy bộ test agent workload'],
  ['git push origin main', 'đẩy code lên GitHub'],
  ['git status --short', 'xem trạng thái git'],
  ['git diff -U0 server.py', 'xem phần code đã đổi'],
  ['grep -n "run_impacted" -r .', 'tìm trong code “run_impacted”'],
  ['sed -n 1,20p server.py', 'đọc file server.py'],
  ['cd /x && gh pr view 12', 'làm việc với pull request'],
  ['sleep 5', 'chờ một lúc'],
  ['python3 -c "import os; print(1)"', 'chạy một đoạn code python3'],
  ['node -e "console.log(1)"', 'chạy một đoạn code node'],
  ['ssh deploy@prod.internal.example.com uptime', 'chạy lệnh ssh'],
  ['rsync -e ssh ./build user@host:/x', 'chạy lệnh rsync'],
  ['A=1 MYVAR=s3cr3tvalue mytool --x', 'chạy lệnh mytool'],
  ['X="a b" foo', 'chạy lệnh foo'],
  ['git constructor', 'dùng git constructor'],
];
assert.ok(!/s3cr3t|hunter2/.test(d('FOO=1 DB_PASS_X=hunter2hunter2 ./run.sh')));
for (const [cmd, want] of cases) assert.strictEqual(d(cmd), want, cmd);
// lệnh lạ: không chép cả dòng lệnh dài
assert.ok(!d('FOO=1 /opt/bin/weirdtool --flag a b c d e f g').includes('--flag'));
console.log('describe_cmd_test OK');
