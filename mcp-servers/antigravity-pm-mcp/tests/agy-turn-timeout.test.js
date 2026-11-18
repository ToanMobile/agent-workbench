// #1230: luot agy da in init roi im lang / chay mai khong dung bi giet ca nhom + loi ro ghi vao tep dau ra; luot binh thuong khong bi dung.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { newConversation } from '../src/agentapi.js';
import { homeStateDir } from '../src/util.js';
import { tmpProject, tmpDir, cleanup } from './helpers.js';

const ARGON = 'gemini-4-argon-high';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };
const KEYS = ['ANTIGRAVITY_PM_AGY', 'ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS', 'PM_AGY_TURN_MAX_MS', 'PM_AGY_SILENT_MAX_MS', 'FAKE_MODE'];
const FAKE = `#!/usr/bin/env node
const mode = process.env.FAKE_MODE;
const init = { event: 'init', conversation_id: 'aaaa1230-2222-3333-4444-555555555555', init: { cwd: process.cwd() } };
console.log(JSON.stringify(init));
if (mode === 'silent') setInterval(() => {}, 1000);
else if (mode === 'chatty') setInterval(() => console.log(JSON.stringify({ event: 'tick' })), 200);
else { console.log(JSON.stringify({ event: 'result', status: 'SUCCESS' })); }
`;

async function run(t, mode, env) {
  const dir = tmpDir('agpm-1230-');
  const bin = path.join(dir, 'agy');
  fs.writeFileSync(bin, FAKE, { mode: 0o755 });
  const prev = { ...process.env };
  Object.assign(process.env, { ANTIGRAVITY_PM_AGY: bin, ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS: '1', FAKE_MODE: mode, ...env });
  const project = tmpProject({ defaultModel: ARGON });
  let pid = null;
  t.after(() => {
    if (pid) { try { process.kill(-pid, 'SIGKILL'); } catch { /* da het */ } }
    for (const k of KEYS) { if (prev[k] === undefined) delete process.env[k]; else process.env[k] = prev[k]; }
    fs.rmSync(path.join(homeStateDir(), 'agy-conversations.json'), { force: true });
    cleanup(project); cleanup(dir);
  });
  const r = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  pid = r.parsed.pid;
  return { pid, out: r.parsed.out };
}

async function waitDead(pid, ms) {
  const t0 = Date.now();
  while (alive(pid) && Date.now() - t0 < ms) await sleep(50);
  return !alive(pid);
}

test('#1230 A: agy init xong roi im lang bi giet sau han im lang, loi ro trong tep dau ra', { timeout: 15000 }, async (t) => {
  const { pid, out } = await run(t, 'silent', { PM_AGY_SILENT_MAX_MS: '700' });
  assert.ok(await waitDead(pid, 4000), 'agy im lang van song sau han im lang');
  assert.match(fs.readFileSync(out, 'utf8'), /agy produced no output for 700 ms/);
});

test('#1230 B: agy in deu nhung qua han cung bi giet, loi ro trong tep dau ra', { timeout: 15000 }, async (t) => {
  const { pid, out } = await run(t, 'chatty', { PM_AGY_TURN_MAX_MS: '1200', PM_AGY_SILENT_MAX_MS: '0' });
  assert.ok(await waitDead(pid, 5000), 'agy in deu van song sau han cung');
  assert.match(fs.readFileSync(out, 'utf8'), /agy turn timed out after 1200 ms/);
});

test('#1230 C: luot binh thuong xong trong han: khong loi, ket qua con nguyen', { timeout: 15000 }, async (t) => {
  const { out } = await run(t, 'normal', { PM_AGY_TURN_MAX_MS: '1500', PM_AGY_SILENT_MAX_MS: '1500' });
  await sleep(2200);
  const text = fs.readFileSync(out, 'utf8');
  assert.match(text, /SUCCESS/);
  assert.doesNotMatch(text, /agy turn timed out|agy produced no output/);
});
