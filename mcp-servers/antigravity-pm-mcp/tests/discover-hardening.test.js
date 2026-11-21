// #1405 (viec con lai sau review PR #1411):
//  a. ANTIGRAVITY_PM_PS khong duoc nhan duong dan bat ky: chi /bin/ps, /usr/bin/ps, hoac file thuong cua chinh user (khong symlink,
//     file va thu muc cha khong cho group/other ghi). Khong hop le thi KHONG chay no va KHONG roi ve ps that.
//  b. hub_*.json: doc qua fd da kiem (khong lstat roi doc lai theo duong dan), va doi chieu gio bat dau cua pid:
//     file ghi TRUOC khi pid hien tai bat dau la file cu cua tien trinh khac (pid bi dung lai) => tu choi; khong doc duoc gio bat dau => tu choi.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import net from 'node:net';
import { discover, forgetCache, AntigravityUnavailable } from '../src/discover.js';
import { tmpDir, cleanup } from './helpers.js';

const KEYS = [
  'HOME',
  'ANTIGRAVITY_PM_PS',
  'ANTIGRAVITY_PM_AGENTAPI',
  'ANTIGRAVITY_AGENTAPI_EXE',
  'ANTIGRAVITY_LS_ADDRESS',
  'ANTIGRAVITY_CSRF_TOKEN',
];
const PID = 78760;
const PORT = 63286;
const LS_LINE = `${PID} /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --app_data_dir antigravity --read_host_bridge_token_from_stdin`;
const START = 'Sat Nov 21 05:27:44 2026';           // dang `ps -o lstart=` voi LC_ALL=C TZ=UTC
const START_MS = Date.UTC(2026, 10, 21, 5, 27, 44);

function setupEnv(t) {
  const saved = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
  const dir = tmpDir('agpm-1405-harden-');
  const home = path.join(dir, 'home');
  fs.mkdirSync(path.join(home, '.gemini', 'antigravity', 'daemon'), { recursive: true, mode: 0o700 });
  process.env.HOME = home;
  for (const k of KEYS.slice(1)) delete process.env[k];
  forgetCache();
  t.after(() => {
    forgetCache();
    for (const k of KEYS) {
      if (saved[k] === undefined) delete process.env[k];
      else process.env[k] = saved[k];
    }
    cleanup(dir);
  });
  return { dir, home, daemonDir: path.join(home, '.gemini', 'antigravity', 'daemon') };
}

/** ps gia: tra `lstart` khi duoc hoi `-o lstart=`, con lai in bang tien trinh; ghi dau vet moi lan bi chay. */
function writeFakePs(file, { lines, lstart = START, lstartRc = 0, marker = '' }) {
  const q = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;
  const body = lines.map((l) => `printf '%s\\n' ${q(l)}`).join('\n');
  fs.writeFileSync(file, `#!/bin/sh
${marker ? `echo run >> ${q(marker)}` : ':'}
case "$*" in
  *lstart=*) ${lstart ? `printf '%s\\n' ${q(lstart)}` : ':'}; exit ${lstartRc} ;;
esac
${body}
`, { mode: 0o755 });
  fs.chmodSync(file, 0o755);
  return file;
}

function writeFakeAgentapi(dir, { expectAddr, expectToken }) {
  const bin = path.join(dir, 'agentapi');
  fs.writeFileSync(bin, `#!/usr/bin/env node
const addr = process.env.ANTIGRAVITY_LS_ADDRESS || '';
const tok = process.env.ANTIGRAVITY_CSRF_TOKEN || '';
if (addr === ${JSON.stringify(expectAddr)} && tok === ${JSON.stringify(expectToken)}) {
  process.stdout.write('{"response": {}, "error": "rpc error: code = NotFound desc = not_found: trajectory not found"}');
  process.exit(1);
}
process.stderr.write('rpc error: code = Unauthenticated desc = missing CSRF token');
process.exit(1);
`, { mode: 0o755 });
  process.env.ANTIGRAVITY_PM_AGENTAPI = bin;
  return bin;
}

function writeHub(daemonDir, secret, mtimeMs) {
  const file = path.join(daemonDir, `hub_${PORT}.json`);
  fs.writeFileSync(file, JSON.stringify({ pid: PID, httpPort: PORT, csrfToken: secret }), { mode: 0o600 });
  fs.utimesSync(file, mtimeMs / 1000, mtimeMs / 1000);
  return file;
}

const psRejected = (e) => e instanceof AntigravityUnavailable && /ANTIGRAVITY_PM_PS/.test(e.message);

test('#1405a: ANTIGRAVITY_PM_PS chi nhan file cua chinh user, khong symlink, khong cho group/other ghi; khong hop le thi khong chay', async (t) => {
  const { dir } = setupEnv(t);
  const secret = crypto.randomUUID();
  const srv = net.createServer();
  await new Promise((resolve) => srv.listen(0, '127.0.0.1', resolve));
  t.after(() => srv.close());
  const port = srv.address().port;
  const marker = path.join(dir, 'ps-ran');
  const ran = () => fs.existsSync(marker);
  const lines = [`${process.pid} /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --csrf_token=${secret}`];
  writeFakeAgentapi(dir, { expectAddr: `127.0.0.1:${port}`, expectToken: secret });

  // 1. file cho group/other ghi (nguoi khac thay ruot duoc)
  const loose = writeFakePs(path.join(dir, 'ps-loose'), { lines, marker });
  fs.chmodSync(loose, 0o777);
  process.env.ANTIGRAVITY_PM_PS = loose;
  await assert.rejects(() => discover({ force: true }), psRejected);
  assert.equal(ran(), false, 'ps ghi duoc boi group/other khong duoc chay');

  // 2. symlink tro toi mot ps hop le
  const good = writeFakePs(path.join(dir, 'ps-good'), { lines, marker });
  const link = path.join(dir, 'ps-link');
  fs.symlinkSync(good, link);
  process.env.ANTIGRAVITY_PM_PS = link;
  await assert.rejects(() => discover({ force: true }), psRejected);
  assert.equal(ran(), false, 'ps la symlink khong duoc chay');

  // 3. thu muc cha cho group/other ghi (nguoi khac doi ten/thay file duoc)
  const openDir = path.join(dir, 'open');
  fs.mkdirSync(openDir);
  fs.chmodSync(openDir, 0o777);
  process.env.ANTIGRAVITY_PM_PS = writeFakePs(path.join(openDir, 'ps'), { lines, marker });
  await assert.rejects(() => discover({ force: true }), psRejected);
  assert.equal(ran(), false, 'ps trong thu muc ghi duoc boi group/other khong duoc chay');

  // 4. duong dan tuong doi / khong ton tai: tu choi, khong roi ve /bin/ps that cua may
  for (const bad of ['ps-good', '/nonexistent/ps']) {
    process.env.ANTIGRAVITY_PM_PS = bad;
    await assert.rejects(() => discover({ force: true }), psRejected);
  }
  assert.equal(ran(), false);

  // 5. doi chung: file hop le cua chinh user van duoc dung
  process.env.ANTIGRAVITY_PM_PS = good;
  const conn = await discover({ force: true });
  assert.equal(conn.secret, secret);
  assert.equal(ran(), true);
});

test('#1405b: hub_*.json ghi truoc gio bat dau cua pid (pid bi dung lai) bi tu choi; ghi sau thi nhan', async (t) => {
  const { dir, daemonDir } = setupEnv(t);
  const secret = crypto.randomUUID();
  process.env.ANTIGRAVITY_PM_PS = writeFakePs(path.join(dir, 'ps'), { lines: [LS_LINE] });
  writeFakeAgentapi(dir, { expectAddr: `127.0.0.1:${PORT}`, expectToken: secret });

  writeHub(daemonDir, secret, START_MS - 1000);
  await assert.rejects(() => discover({ force: true }), (e) => e instanceof AntigravityUnavailable && /language_server/.test(e.message));

  writeHub(daemonDir, secret, START_MS + 2000);
  const conn = await discover({ force: true });
  assert.equal(conn.pid, PID);
  assert.equal(conn.secret, secret);
});

test('#1405b: khong doc duoc gio bat dau cua pid (ps tra rac, hoac pid vua thoat) thi khong tin hub_*.json', async (t) => {
  const { dir, daemonDir } = setupEnv(t);
  const secret = crypto.randomUUID();
  writeFakeAgentapi(dir, { expectAddr: `127.0.0.1:${PORT}`, expectToken: secret });
  writeHub(daemonDir, secret, START_MS + 2000);

  process.env.ANTIGRAVITY_PM_PS = writeFakePs(path.join(dir, 'ps-junk'), { lines: [LS_LINE], lstart: LS_LINE });
  await assert.rejects(() => discover({ force: true }), AntigravityUnavailable);

  process.env.ANTIGRAVITY_PM_PS = writeFakePs(path.join(dir, 'ps-gone'), { lines: [LS_LINE], lstart: '', lstartRc: 1 });
  await assert.rejects(() => discover({ force: true }), AntigravityUnavailable);
});

test('#1405b TOCTOU: file hub bi doi thanh symlink sau buoc kiem khong duoc doc theo duong dan', async (t) => {
  const { dir, daemonDir } = setupEnv(t);
  const secret = crypto.randomUUID();
  const evilSecret = crypto.randomUUID();
  const evil = path.join(dir, 'evil.json');
  fs.writeFileSync(evil, JSON.stringify({ pid: PID, httpPort: PORT, csrfToken: evilSecret }), { mode: 0o600 });
  fs.utimesSync(evil, (START_MS + 2000) / 1000, (START_MS + 2000) / 1000);
  process.env.ANTIGRAVITY_PM_PS = writeFakePs(path.join(dir, 'ps'), { lines: [LS_LINE] });
  const hub = writeHub(daemonDir, secret, START_MS + 2000);
  // agentapi gia nhan CA HAI khoa: neu discover doc phai file bi trao thi no se tra ve khoa cua ke tan cong
  const bin = path.join(dir, 'agentapi');
  fs.writeFileSync(bin, `#!/bin/sh
printf '%s' '{"response": {}, "error": "rpc error: code = NotFound desc = not_found"}'
exit 1
`, { mode: 0o755 });
  process.env.ANTIGRAVITY_PM_AGENTAPI = bin;

  // Mo phong cua so dua: ngay truoc moi lan doc file hub THEO DUONG DAN (sau khi da lstat), ke tan cong thay no bang symlink.
  const realRead = fs.readFileSync;
  let swapped = 0;
  fs.readFileSync = function patched(target, ...rest) {
    if (typeof target === 'string' && target === hub) {
      fs.rmSync(hub);
      fs.symlinkSync(evil, hub);
      swapped += 1;
    }
    return realRead.call(fs, target, ...rest);
  };
  t.after(() => { fs.readFileSync = realRead; });

  const conn = await discover({ force: true });
  assert.notEqual(conn.secret, evilSecret, 'khoa lay tu file bi trao sau buoc kiem');
  assert.equal(conn.secret, secret);
  assert.equal(swapped, 0, 'file hub khong duoc doc lai theo duong dan sau khi da kiem');
});
