// #734: PM chay trong phien Claude (MCP stdio) nen thua env cua phien. agy va moi lenh cua agent (--dangerously-skip-permissions)
// KHONG duoc nhan bien messaging cua phien; bien agy can (the luot ANTIGRAVITY_PM_RUN, PATH, HOME) van phai co.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { newConversation } from '../src/agentapi.js';
import { homeStateDir } from '../src/util.js';
import { tmpProject, tmpDir, cleanup } from './helpers.js';

const ARGON = 'gemini-4-argon-high';
const PICK = ['CLAUDE_CODE_MESSAGING_TOKEN', 'CLAUDE_CODE_MESSAGING_SOCKET', 'ANTIGRAVITY_PM_RUN', 'PATH', 'HOME'];
// agy gia: chi ghi CAC BIEN CAN XET luc exec (khong ghi ca env ra dia), roi in init + result va thoat
const FAKE = `#!/usr/bin/env node
const pick = ${JSON.stringify(PICK)};
require('node:fs').writeFileSync(process.env.FAKE_AGY_ENV_FILE, JSON.stringify(Object.fromEntries(pick.filter((k) => k in process.env).map((k) => [k, process.env[k]]))));
const id = '73473473-2222-3333-4444-555555555555';
console.log(JSON.stringify({ event: 'init', conversation_id: id, init: { cwd: process.cwd() } }));
console.log(JSON.stringify({ event: 'result', result: { conversation_id: id, status: 'SUCCESS' } }));
`;
// env thu dich: phien Claude dat hai bien nay cho MCP server (gia tri gia, sinh theo ten bien)
const HOSTILE = Object.fromEntries(PICK.slice(0, 2).map((k) => [k, `gia-${k.toLowerCase()}-${process.pid}`]));
const KEYS = ['ANTIGRAVITY_PM_AGY', 'ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS', 'FAKE_AGY_ENV_FILE', ...Object.keys(HOSTILE)];

test('#734 agy KHONG nhan bien messaging cua phien Claude; van nhan ANTIGRAVITY_PM_RUN, PATH, HOME; env cua PM khong doi', async (t) => {
  const dir = tmpDir('agpm-734-');
  const bin = path.join(dir, 'agy');
  fs.writeFileSync(bin, FAKE, { mode: 0o755 });
  const envFile = path.join(dir, 'env.json');
  const prev = { ...process.env };
  Object.assign(process.env, { ANTIGRAVITY_PM_AGY: bin, ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS: '1', FAKE_AGY_ENV_FILE: envFile }, HOSTILE);
  const project = tmpProject({ defaultModel: ARGON });
  t.after(() => {
    for (const k of KEYS) { if (prev[k] === undefined) delete process.env[k]; else process.env[k] = prev[k]; }
    fs.rmSync(path.join(homeStateDir(), 'agy-conversations.json'), { force: true });
    cleanup(dir);
    cleanup(project);
  });

  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  // agy gia ghi file TRUOC khi in init, va newConversation chi tra ve sau khi thay init => file da co
  const seen = JSON.parse(fs.readFileSync(envFile, 'utf8'));
  for (const k of Object.keys(HOSTILE)) assert.ok(!(k in seen), `agy khong duoc nhan bien ${k} cua phien Claude`);
  const reg = JSON.parse(fs.readFileSync(path.join(homeStateDir(), 'agy-conversations.json'), 'utf8'));
  assert.equal(seen.ANTIGRAVITY_PM_RUN, path.basename(reg[conversationId].out, '.jsonl'), 'the luot (#697) van phai xuong agy');
  assert.equal(seen.PATH, process.env.PATH);
  assert.equal(seen.HOME, process.env.HOME);
  for (const [k, v] of Object.entries(HOSTILE)) assert.equal(process.env[k], v, `PM chi loc env cua agy, khong xoa ${k} cua chinh no`);
});
