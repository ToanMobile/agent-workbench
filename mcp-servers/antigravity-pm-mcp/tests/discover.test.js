// #1405: discover phai ho tro daemon file ~/.gemini/<app_data_dir>/daemon/hub_*.json (Antigravity moi khong truyen --csrf_token qua argv)
// dong thoi giu duong --csrf_token cu va chan token tu nguon agent co the ghi (symlink, path traversal, group/world-writable).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { discover, agentapiPath, forgetCache, AntigravityUnavailable } from '../src/discover.js';
import { tmpDir, cleanup } from './helpers.js';

const KEYS = [
  'HOME',
  'ANTIGRAVITY_PM_PS',
  'ANTIGRAVITY_PM_AGENTAPI',
  'ANTIGRAVITY_AGENTAPI_EXE',
  'ANTIGRAVITY_LS_ADDRESS',
  'ANTIGRAVITY_CSRF_TOKEN',
];

function setupEnv(t) {
  const saved = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
  const dir = tmpDir('agpm-1405-discover-');
  const home = path.join(dir, 'home');
  fs.mkdirSync(path.join(home, '.gemini'), { recursive: true, mode: 0o755 });
  process.env.HOME = home;
  delete process.env.ANTIGRAVITY_LS_ADDRESS;
  delete process.env.ANTIGRAVITY_CSRF_TOKEN;
  delete process.env.ANTIGRAVITY_AGENTAPI_EXE;
  delete process.env.ANTIGRAVITY_PM_AGENTAPI;
  forgetCache();
  t.after(() => {
    forgetCache();
    for (const k of KEYS) {
      if (saved[k] === undefined) delete process.env[k];
      else process.env[k] = saved[k];
    }
    cleanup(dir);
  });
  return { dir, home };
}

function writeFakePs(dir, lines) {
  const psPath = path.join(dir, 'ps');
  const body = lines.map((l) => `printf '%s\\n' ${JSON.stringify(l)}`).join('\n');
  // Hoi gio bat dau (`-o lstart= -p <pid>`): tien trinh gia bat dau tu 1970, cu hon moi file hub_*.json cua test.
  const lstart = `case "$*" in *lstart=*) echo 'Thu Jan  1 00:00:01 1970'; exit 0 ;; esac`;
  fs.writeFileSync(psPath, `#!/bin/sh\n${lstart}\n${body}\n`, { mode: 0o755 });
  process.env.ANTIGRAVITY_PM_PS = psPath;
  return psPath;
}

function writeFakeAgentapi(dir, { expectAddr, expectToken, logFile }) {
  const bin = path.join(dir, 'agentapi');
  const script = `#!/usr/bin/env node
const fs = require('node:fs');
const addr = process.env.ANTIGRAVITY_LS_ADDRESS || '';
const tok = process.env.ANTIGRAVITY_CSRF_TOKEN || '';
if (${JSON.stringify(logFile)}) fs.appendFileSync(${JSON.stringify(logFile)}, JSON.stringify({ addr, hasTok: Boolean(tok), matched: tok === ${JSON.stringify(expectToken)} }) + '\\n');
if (addr === ${JSON.stringify(expectAddr)} && tok === ${JSON.stringify(expectToken)}) {
  process.stdout.write('{"response": {}, "error": "rpc error: code = NotFound desc = not_found: trajectory not found"}');
  process.exit(1);
}
process.stderr.write('rpc error: code = Unauthenticated desc = missing CSRF token');
process.exit(1);
`;
  fs.writeFileSync(bin, script, { mode: 0o755 });
  process.env.ANTIGRAVITY_PM_AGENTAPI = bin;
  return bin;
}

test('#1405 AC1: discover tim duoc language_server argv moi (--read_host_bridge_token_from_stdin, khong --csrf_token) qua daemon hub_*.json', async (t) => {
  const { dir, home } = setupEnv(t);
  const secret = crypto.randomUUID();
  const staleSecret = crypto.randomUUID();
  const pid = 78760;
  const httpPort = 63286;
  const daemonDir = path.join(home, '.gemini', 'antigravity', 'daemon');
  fs.mkdirSync(daemonDir, { recursive: true, mode: 0o700 });
  fs.writeFileSync(
    path.join(daemonDir, `hub_${httpPort}.json`),
    JSON.stringify({ pid, httpsPort: 63285, httpPort, lsVersion: '2.34.0', csrfToken: secret }),
    { mode: 0o600 },
  );
  // Them file hub cu cua pid da chet de dam bao chon dung pid dang chay
  fs.writeFileSync(
    path.join(daemonDir, 'hub_54827.json'),
    JSON.stringify({ pid: 32864, httpsPort: 54826, httpPort: 54827, lsVersion: '2.34.0', csrfToken: staleSecret }),
    { mode: 0o600 },
  );
  writeFakePs(dir, [
    `${pid} /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --override_ide_name antigravity --subclient_type hub --override_ide_version 2.34.0 --app_data_dir antigravity --host_bridge_url=http://127.0.0.1:63281 --read_host_bridge_token_from_stdin`,
  ]);
  const logFile = path.join(dir, 'calls.jsonl');
  writeFakeAgentapi(dir, { expectAddr: `127.0.0.1:${httpPort}`, expectToken: secret, logFile });

  const conn = await discover();
  assert.equal(conn.pid, pid);
  assert.equal(conn.address, `127.0.0.1:${httpPort}`);
  assert.equal(conn.secret, secret);
  assert.equal(conn.source, 'probe');
  const calls = fs.readFileSync(logFile, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  assert.equal(calls.some((c) => c.addr === `127.0.0.1:${httpPort}` && c.matched), true);
});

test('#1405 AC1: van giu duong --csrf_token cu trong argv cua language_server', async (t) => {
  const { dir } = setupEnv(t);
  const secret = crypto.randomUUID();
  const srv = net.createServer();
  await new Promise((resolve) => srv.listen(0, '127.0.0.1', resolve));
  t.after(() => srv.close());
  const port = srv.address().port;

  writeFakePs(dir, [
    `${process.pid} /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --csrf_token=${secret}`,
  ]);
  writeFakeAgentapi(dir, { expectAddr: `127.0.0.1:${port}`, expectToken: secret, logFile: '' });

  const conn = await discover();
  assert.equal(conn.pid, process.pid);
  assert.equal(conn.address, `127.0.0.1:${port}`);
  assert.equal(conn.secret, secret);
});

test('#1405 bao loi khi chi co hub_*.json cua pid khac (khong khop pid dang chay)', async (t) => {
  const { dir, home } = setupEnv(t);
  const daemonDir = path.join(home, '.gemini', 'antigravity', 'daemon');
  fs.mkdirSync(daemonDir, { recursive: true, mode: 0o700 });
  fs.writeFileSync(
    path.join(daemonDir, 'hub_54827.json'),
    JSON.stringify({ pid: 999999, httpsPort: 54826, httpPort: 54827, lsVersion: '2.34.0', csrfToken: crypto.randomUUID() }),
    { mode: 0o600 },
  );
  writeFakePs(dir, [
    '78760 /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --app_data_dir antigravity --read_host_bridge_token_from_stdin',
  ]);
  writeFakeAgentapi(dir, { expectAddr: '127.0.0.1:54827', expectToken: 'x', logFile: '' });

  await assert.rejects(() => discover(), (e) => e instanceof AntigravityUnavailable && /language_server/.test(e.message));
});

test('#1405 bao mat: tu choi --app_data_dir tro ra ngoai, symlink va file/thu muc ghi duoc boi group/other', async (t) => {
  const { dir, home } = setupEnv(t);
  const secret = crypto.randomUUID();
  const evilDir = path.join(dir, 'evil-daemon');
  fs.mkdirSync(evilDir, { recursive: true, mode: 0o700 });
  fs.writeFileSync(
    path.join(evilDir, 'hub_63286.json'),
    JSON.stringify({ pid: 78760, httpPort: 63286, csrfToken: secret }),
    { mode: 0o600 },
  );
  writeFakeAgentapi(dir, { expectAddr: '127.0.0.1:63286', expectToken: secret, logFile: '' });

  // 1. Path traversal trong --app_data_dir
  writeFakePs(dir, [
    `78760 /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --app_data_dir ../../evil-daemon --read_host_bridge_token_from_stdin`,
  ]);
  await assert.rejects(() => discover(), AntigravityUnavailable);

  // 2. Symlink thu muc daemon
  const appDir = path.join(home, '.gemini', 'antigravity');
  fs.mkdirSync(appDir, { recursive: true, mode: 0o755 });
  const daemonLink = path.join(appDir, 'daemon');
  fs.symlinkSync(evilDir, daemonLink);
  writeFakePs(dir, [
    '78760 /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --app_data_dir antigravity --read_host_bridge_token_from_stdin',
  ]);
  await assert.rejects(() => discover(), AntigravityUnavailable);
  fs.rmSync(daemonLink);

  // 3. Symlink file hub_*.json
  fs.mkdirSync(daemonLink, { recursive: true, mode: 0o700 });
  const hubFile = path.join(daemonLink, 'hub_63286.json');
  fs.symlinkSync(path.join(evilDir, 'hub_63286.json'), hubFile);
  await assert.rejects(() => discover(), AntigravityUnavailable);
  fs.rmSync(hubFile);

  // 4. File world-writable (0o666)
  fs.writeFileSync(hubFile, JSON.stringify({ pid: 78760, httpPort: 63286, csrfToken: secret }), { mode: 0o666 });
  fs.chmodSync(hubFile, 0o666);
  await assert.rejects(() => discover(), AntigravityUnavailable);
});

test('#1405 agentapiPath bo qua ANTIGRAVITY_AGENTAPI_EXE neu tro vao CLI agy, roi ve agentapi that', (t) => {
  const { dir, home } = setupEnv(t);
  const agyBin = path.join(dir, 'agy');
  const realAgentapi = path.join(home, '.gemini', 'antigravity', 'bin', 'agentapi');
  fs.mkdirSync(path.dirname(realAgentapi), { recursive: true });
  fs.writeFileSync(agyBin, '#!/bin/sh\nexit 2\n', { mode: 0o755 });
  fs.writeFileSync(realAgentapi, '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  process.env.ANTIGRAVITY_AGENTAPI_EXE = agyBin;

  assert.equal(agentapiPath(), realAgentapi);
});
