// #657: may ban (load1 > 100) thi ps tra loi cham > 1,5 s: procTag khong duoc coi cham la loi (ETIMEDOUT), chi ps hong that moi nem.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { sameProcess, psTimeoutMs } from '../src/agentapi.js';
import { tmpDir, cleanup } from './helpers.js';

const KEYS = ['ANTIGRAVITY_PM_PS', 'ANTIGRAVITY_PM_PS_TIMEOUT_MS'];
function slowPs(t, secs) {
  const saved = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
  const dir = tmpDir('agpm-657-ps-');
  t.after(() => { cleanup(dir); for (const k of KEYS) { if (saved[k] === undefined) delete process.env[k]; else process.env[k] = saved[k]; } });
  const wrapper = path.join(dir, 'ps-slow.sh');
  fs.writeFileSync(wrapper, `#!/bin/sh\nsleep ${secs}\nexec /bin/ps "$@"\n`, { mode: 0o755 });
  process.env.ANTIGRAVITY_PM_PS = wrapper;
  delete process.env.ANTIGRAVITY_PM_PS_TIMEOUT_MS;
}

test('procTag: ps cham 2 s nhung co tra loi => van tra dau van tay (khong nem ETIMEDOUT)', (t) => {
  const tag = execFileSync('/bin/ps', ['-o', 'lstart=', '-p', String(process.pid)], { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' } }).trim();
  slowPs(t, 2);
  assert.equal(sameProcess(process.pid, tag), true);
});

test('procTag: ps cham qua timeout chinh duoc (ANTIGRAVITY_PM_PS_TIMEOUT_MS) van nem loi ro rang', (t) => {
  slowPs(t, 3);
  process.env.ANTIGRAVITY_PM_PS_TIMEOUT_MS = '300';
  assert.throws(() => sameProcess(process.pid, 'x'), /ETIMEDOUT/);
});

test('psTimeoutMs: mac dinh 5 s, env hop le duoc dung, gia tri qua lon bi kep o tran 7 s (giu bat bien khoa), rac => mac dinh', (t) => {
  const saved = process.env.ANTIGRAVITY_PM_PS_TIMEOUT_MS;
  t.after(() => { if (saved === undefined) delete process.env.ANTIGRAVITY_PM_PS_TIMEOUT_MS; else process.env.ANTIGRAVITY_PM_PS_TIMEOUT_MS = saved; });
  delete process.env.ANTIGRAVITY_PM_PS_TIMEOUT_MS;
  assert.equal(psTimeoutMs(), 5000);
  process.env.ANTIGRAVITY_PM_PS_TIMEOUT_MS = '3000'; assert.equal(psTimeoutMs(), 3000);
  process.env.ANTIGRAVITY_PM_PS_TIMEOUT_MS = '60000'; assert.equal(psTimeoutMs(), 7000);
  process.env.ANTIGRAVITY_PM_PS_TIMEOUT_MS = 'abc'; assert.equal(psTimeoutMs(), 5000);
});
