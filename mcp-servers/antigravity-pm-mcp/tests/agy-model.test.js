// Model cu the (vd gemini-4-argon-high) khong di qua `agentapi` (chi nhan flash_lite|flash|pro) ma qua CLI `agy --model`.
// agy that khong co trong test: ANTIGRAVITY_PM_AGY tro vao script gia ghi lai moi lan duoc goi.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  MODELS, isAgyModel, agyPath, newConversation, sendMessage, getConversationMetadata, conversationProgress, transcriptErrors, agyTurnStatus,
} from '../src/agentapi.js';
import { TOOLS_BY_NAME } from '../src/tools.js';
import { AntigravityUnavailable } from '../src/discover.js';
import { homeStateDir } from '../src/util.js';
import { DEFAULT_CONFIG } from '../src/config.js';
import { cleanup } from './helpers.js';

const FAKE = `#!/usr/bin/env node
const fs = require('node:fs');
const a = process.argv.slice(2);
const i = a.indexOf('--conversation');
const id = i >= 0 ? a[i + 1] : (process.env.FAKE_AGY_ID || 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
fs.appendFileSync(process.env.FAKE_AGY_LOG, JSON.stringify({ args: a, cwd: process.cwd(), pid: process.pid }) + '\\n');
if (process.env.FAKE_AGY_NO_INIT) process.exit(3);
setTimeout(() => console.log(JSON.stringify({ event: 'init', conversation_id: id, init: { cwd: process.env.FAKE_AGY_INIT_CWD || process.cwd() } })), Number(process.env.FAKE_AGY_INIT_DELAY_MS || 0));
const hold = Number(process.env.FAKE_AGY_HOLD_MS || 0) + Number(process.env.FAKE_AGY_INIT_DELAY_MS || 0);
setTimeout(() => { console.log(JSON.stringify({ event: 'result', result: { conversation_id: id, status: 'SUCCESS' } })); }, hold);
`;

function fakeAgy(t, env = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-agy-'));
  const bin = path.join(dir, 'agy');
  fs.writeFileSync(bin, FAKE, { mode: 0o755 });
  const log = path.join(dir, 'calls.jsonl');
  const prev = { ...process.env };
  process.env.ANTIGRAVITY_PM_AGY = bin;
  process.env.FAKE_AGY_LOG = log;
  process.env.ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS = '1';   // cac test khac khong dung toi chinh sach IDE that cua may; test chot chan tu dat lai
  for (const [k, v] of Object.entries(env)) process.env[k] = v;
  t.after(() => {
    for (const k of ['ANTIGRAVITY_PM_AGY', 'FAKE_AGY_LOG', 'FAKE_AGY_ID', 'FAKE_AGY_HOLD_MS', 'FAKE_AGY_INIT_DELAY_MS', 'FAKE_AGY_NO_INIT', 'FAKE_AGY_INIT_CWD', 'ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS', 'ANTIGRAVITY_PM_PROJECTS_DIR', 'HOME']) {
      if (prev[k] === undefined) delete process.env[k]; else process.env[k] = prev[k];
    }
    cleanup(dir);
  });
  const calls = () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l)) : []);
  return { dir, bin, calls };
}

const ARGON = 'gemini-4-argon-high';

test('MODELS: them model cu the cua agy, giu 3 bac cua agentapi; chi model agy moi qua agy', () => {
  assert.ok(MODELS.includes(ARGON));
  for (const tier of ['flash_lite', 'flash', 'pro']) { assert.ok(MODELS.includes(tier)); assert.equal(isAgyModel(tier), false); }
  assert.equal(isAgyModel(ARGON), true);
  assert.equal(isAgyModel('gemini-9-nope'), false);
});

test('schema pm_task_create nhan Argon (enum lay tu MODELS)', () => {
  assert.deepEqual(TOOLS_BY_NAME.get('pm_task_create').inputSchema.properties.model.enum, MODELS);
});

test('newConversation voi Argon: goi agy --model, cwd = thu muc project, KHONG qua agentapi, ghi so dang ky', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: '11111111-2222-3333-4444-555555555555' });
  const project = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-agy-proj-'));
  t.after(() => cleanup(project));
  const r = await newConversation({ prompt: 'lam viec A', model: ARGON, cwd: project, projectId: 'p1', title: 't' });
  assert.equal(r.conversationId, '11111111-2222-3333-4444-555555555555');
  const [call] = fake.calls();
  assert.deepEqual(call.args.slice(0, 2), ['--print', 'lam viec A']);
  assert.ok(call.args.join(' ').includes(`--model ${ARGON}`));
  assert.ok(call.args.includes('--output-format') && call.args.includes('stream-json'));
  assert.ok(call.args.includes('--dangerously-skip-permissions'));
  assert.equal(fs.realpathSync(call.cwd), fs.realpathSync(project));
  const reg = JSON.parse(fs.readFileSync(path.join(homeStateDir(), 'agy-conversations.json'), 'utf8'));
  assert.equal(reg[r.conversationId].model, ARGON);
  assert.equal(fs.realpathSync(reg[r.conversationId].cwd), fs.realpathSync(project));
});

test('newConversation voi model agy ma thieu cwd thi bao loi, khong doan thu muc', async (t) => {
  fakeAgy(t);
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON }), /cwd/);
});

test('model la: tu choi, khong am tham doi sang model khac', async (t) => {
  const fake = fakeAgy(t);
  await assert.rejects(newConversation({ prompt: 'x', model: 'gemini-9-nope', cwd: os.tmpdir() }), /khong hop le/);
  assert.equal(fake.calls().length, 0);
});

test('khong co agy: nem AntigravityUnavailable, KHONG roi ve flash', async (t) => {
  fakeAgy(t);
  process.env.ANTIGRAVITY_PM_AGY = path.join(os.tmpdir(), 'agpm-khong-co', 'agy');
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON, cwd: os.tmpdir() }), (e) => e instanceof AntigravityUnavailable);
});

test('hoi thoai agy: metadata lay workspace tu so dang ky (IDE khong biet hoi thoai nay)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: '22222222-2222-3333-4444-555555555555' });
  const project = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-agy-proj-'));
  t.after(() => cleanup(project));
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  const md = await getConversationMetadata(conversationId);
  assert.equal(md.found, true);
  assert.equal(fs.realpathSync(md.workspace), fs.realpathSync(project));
});

test('sendMessage vao hoi thoai agy: agy --conversation ID --model <model da luu>; dang chay luot cu thi tu choi', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: '33333333-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '1500' });
  const project = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-agy-proj-'));
  t.after(() => cleanup(project));
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  // luot dau con chay (giu 1,5 s): gui tiep se chong luot => bao loi ro rang
  await assert.rejects(sendMessage({ conversationId, content: 'nhac' }), /dang chay/);
  await new Promise((r) => setTimeout(r, 2200)); // luot dau ket thuc
  await sendMessage({ conversationId, content: 'lam tiep' });
  const calls = fake.calls();
  const last = calls[calls.length - 1];
  assert.deepEqual(last.args.slice(0, 4), ['--conversation', conversationId, '--print', 'lam tiep']);
  assert.ok(last.args.join(' ').includes(`--model ${ARGON}`), 'resume khong co --model se chay model mac dinh (da do 14/10)');
  assert.equal(fs.realpathSync(last.cwd), fs.realpathSync(project));
});

test('conversationProgress va transcriptErrors doc ca thu muc cua agy (~/.gemini/antigravity-cli)', (t) => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-agy-home-'));
  const prevHome = process.env.HOME;
  process.env.HOME = home;
  t.after(() => { process.env.HOME = prevHome; cleanup(home); });
  const id = '44444444-2222-3333-4444-555555555555';
  fs.mkdirSync(path.join(home, '.gemini/antigravity-cli/conversations'), { recursive: true });
  fs.writeFileSync(path.join(home, `.gemini/antigravity-cli/conversations/${id}.db`), 'x');
  const logs = path.join(home, `.gemini/antigravity-cli/brain/${id}/.system_generated/logs`);
  fs.mkdirSync(logs, { recursive: true });
  fs.writeFileSync(path.join(logs, 'transcript.jsonl'), '{"type":"USER_INPUT","created_at":"2026-10-14T00:00:00Z"}\n{"type":"ERROR_MESSAGE","created_at":"2026-10-14T00:01:00Z"}\n');
  const prog = conversationProgress(id);
  assert.equal(prog.found, true);
  const te = transcriptErrors(id);
  assert.equal(te.found, true);
  assert.equal(te.errorCount, 1);
  assert.equal(te.lastStepIsError, true);
});

test('model mac dinh cua PM la Argon (khong con flash/pro), va nam trong MODELS', () => {
  assert.equal(DEFAULT_CONFIG.defaultModel, ARGON);
  assert.ok(MODELS.includes(DEFAULT_CONFIG.defaultModel));
});

test('gui tin vao hoi thoai agy dang chay: loi noi ro pid va cach go (agy thoat = luot dung)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: '55555555-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '1500' });
  const project = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-agy-proj-'));
  t.after(() => cleanup(project));
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  await assert.rejects(sendMessage({ conversationId, content: 'nhac' }), /pid \d+.*kill/s);
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const mkProject = (t) => { const d = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-agy-proj-')); t.after(() => cleanup(d)); return d; };

test('hai lan gui dong thoi vao cung hoi thoai: chi MOT agy duoc sinh (giu cho truoc moi await)', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: '66666666-2222-3333-4444-555555555555' });
  const project = mkProject(t);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  await sleep(800); // luot dau xong
  const r = await Promise.allSettled([sendMessage({ conversationId, content: 'A' }), sendMessage({ conversationId, content: 'B' })]);
  assert.equal(r.filter((x) => x.status === 'fulfilled').length, 1, JSON.stringify(r.map((x) => x.status)));
  assert.match(String(r.find((x) => x.status === 'rejected').reason.message), /dang (chay|mo)/);
  assert.equal(fake.calls().filter((c) => c.args.includes('--conversation')).length, 1);
});

test('pid bi dung lai boi tien trinh la khong chan gui tin (dau van tay khac) va khong bao kill tien trinh la', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: '77777777-2222-3333-4444-555555555555' });
  const project = mkProject(t);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  await sleep(800);
  const stranger = (await import('node:child_process')).spawn('sleep', ['30'], { stdio: 'ignore' });
  t.after(() => stranger.kill());
  const file = path.join(homeStateDir(), 'agy-conversations.json');
  const reg = JSON.parse(fs.readFileSync(file, 'utf8'));
  reg[conversationId].pid = stranger.pid;            // pid cua mot tien trinh KHAC dang song...
  reg[conversationId].pidTag = 'Thu Jan  1 00:00:00 1970'; // ...nhung khong phai tien trinh agy da ghi
  fs.writeFileSync(file, JSON.stringify(reg));
  assert.equal(agyTurnStatus(conversationId).running, false);
  await sendMessage({ conversationId, content: 'lam tiep' });
  assert.equal(fake.calls().filter((c) => c.args.includes('--conversation')).length, 1);
});

test('luot dang chay: loi khuyen kill ca NHOM (kill -- -pid), khong chi pid', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: '88888888-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '1500' });
  const project = mkProject(t);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  assert.equal(agyTurnStatus(conversationId).running, true);
  await assert.rejects(sendMessage({ conversationId, content: 'nhac' }), /kill -- -\d+/);
});

test('so dang ky hong: bao loi to va KHONG ghi de (khong mat model + cwd cua hoi thoai dang chay)', async (t) => {
  fakeAgy(t);
  const file = path.join(homeStateDir(), 'agy-conversations.json');
  fs.writeFileSync(file, '{"a": {"model": "x"');
  // doc de CHON DUONG chiu loi (khong keo sap duong IDE, xem tests/agy-round2.test.js); ghi / mo luot moi van no to
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) }), /agy-conversations\.json hong/);
  assert.equal(fs.readFileSync(file, 'utf8'), '{"a": {"model": "x"', 'file hong phai con nguyen de nguoi dung sua');
  fs.rmSync(file);
});

test('so dang ky: qua 500 muc thi bo muc DUNG LAU NHAT (lastSentAt), khong phai muc tao som nhat', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: '99999999-2222-3333-4444-555555555555' });
  const file = path.join(homeStateDir(), 'agy-conversations.json');
  const reg = {};
  for (let i = 0; i < 505; i++) reg[`c${i}`] = { model: ARGON, cwd: os.tmpdir(), at: new Date(2020, 0, 1, 0, 0, i).toISOString() };
  reg.c0.lastSentAt = new Date().toISOString();   // tao som nhat nhung vua duoc dung
  fs.writeFileSync(file, JSON.stringify(reg));
  await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  const after = JSON.parse(fs.readFileSync(file, 'utf8'));
  assert.equal(Object.keys(after).length, 500);
  assert.ok(after.c0, 'muc vua dung phai o lai');
  assert.ok(!after.c1 && !after.c5, 'muc cu nhat chua dung phai bi bo');
  assert.ok(after['99999999-2222-3333-4444-555555555555']);
});

test('chot quyen: chi truyen --dangerously-skip-permissions khi IDE da cho tu chay lenh (EAGER/TURBO), khong thi loi to va khong spawn', async (t) => {
  const fake = fakeAgy(t);
  delete process.env.ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS;
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-agy-home-'));
  t.after(() => cleanup(home));
  process.env.HOME = home;
  process.env.ANTIGRAVITY_PM_PROJECTS_DIR = path.join(home, 'projects');   // so dang ky project that cua may khong lot vao
  fs.mkdirSync(process.env.ANTIGRAVITY_PM_PROJECTS_DIR);
  const project = mkProject(t);
  const setGlobal = (policy) => {
    fs.mkdirSync(path.join(home, '.gemini/config'), { recursive: true });
    fs.writeFileSync(path.join(home, '.gemini/config/config.json'), JSON.stringify({ userSettings: policy ? { autoExecutionPolicy: policy } : {} }));
  };
  // khong dat chinh sach nao
  setGlobal(null);
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON, cwd: project }), /EAGER\/TURBO/);
  // chinh sach chung la tu duyet tung lenh
  setGlobal('CASCADE_COMMANDS_AUTO_EXECUTION_OFF');
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON, cwd: project }), /AUTO_EXECUTION_OFF/);
  assert.equal(fake.calls().length, 0, 'bi chan thi KHONG duoc spawn agy');
  // chinh sach chung EAGER
  setGlobal('CASCADE_COMMANDS_AUTO_EXECUTION_EAGER');
  process.env.FAKE_AGY_ID = 'abababab-2222-3333-4444-555555555555';
  await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  assert.ok(fake.calls()[0].args.includes('--dangerously-skip-permissions'));
  // chinh sach cua RIENG project (khong tu chay) thang chinh sach chung
  fs.writeFileSync(path.join(process.env.ANTIGRAVITY_PM_PROJECTS_DIR, 'p1.json'), JSON.stringify({
    id: 'p1', name: 'P1', workspaces: [{ folderUri: `file://${fs.realpathSync(project)}` }], settings: { autoExecutionPolicy: 'CASCADE_COMMANDS_AUTO_EXECUTION_OFF' },
  }));
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON, cwd: project }), /project "P1"/);
});

test('workspace cua hoi thoai agy lay tu su kien init cua agy (cwd that), khong chi lap lai cwd ma PM truyen vao', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'cdcdcdcd-2222-3333-4444-555555555555', FAKE_AGY_INIT_CWD: '/nowhere/else' });
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  assert.equal((await getConversationMetadata(conversationId)).workspace, '/nowhere/else');
});

test('thu muc project da bi doi ten: loi noi dung nguyen nhan, khong phai "spawn agy ENOENT"', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'efefefef-2222-3333-4444-555555555555' });
  const project = mkProject(t);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  await sleep(800);
  cleanup(project);
  await assert.rejects(sendMessage({ conversationId, content: 'x' }), /khong con ton tai/);
});

test('file chay cua agy (chua toan bo stream cua luot) chi chu so huu doc duoc (0600)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: '12121212-2222-3333-4444-555555555555' });
  const r = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  assert.equal(fs.statSync(r.parsed.out).mode & 0o077, 0);
  assert.equal(fs.statSync(path.dirname(r.parsed.out)).mode & 0o077, 0);
});

test('file chay agy cu hon 7 ngay duoc don khi mo luot moi', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: '13131313-2222-3333-4444-555555555555' });
  const runs = path.join(homeStateDir(), 'agy-runs');
  fs.mkdirSync(runs, { recursive: true });
  const old = path.join(runs, 'old.jsonl'); const fresh = path.join(runs, 'fresh.jsonl');
  fs.writeFileSync(old, 'x'); fs.writeFileSync(fresh, 'x');
  const past = new Date(Date.now() - 8 * 24 * 3600 * 1000);
  fs.utimesSync(old, past, past);
  await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  assert.ok(!fs.existsSync(old) && fs.existsSync(fresh));
});

test('PM bi SIGTERM trong luc cho init: tien trinh agy cung bi don (khong de agent skip-permissions chay ma PM khong biet)', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_INIT_DELAY_MS: '8000', FAKE_AGY_ID: '14141414-2222-3333-4444-555555555555' });
  const project = mkProject(t);
  const src = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../src/agentapi.js');
  const { spawn } = await import('node:child_process');
  const pm = spawn(process.execPath, ['--input-type=module', '-e',
    `import { newConversation } from ${JSON.stringify(src)};
     newConversation({ prompt: 'x', model: ${JSON.stringify(ARGON)}, cwd: ${JSON.stringify(project)} }).catch(() => {});
     setTimeout(() => process.kill(process.pid, 'SIGTERM'), 1500);`], { stdio: 'ignore' });
  await new Promise((r) => pm.once('exit', r));
  await sleep(600);
  const [call] = fake.calls();
  assert.ok(call && call.pid, 'agy gia phai da duoc spawn');
  t.after(() => { try { process.kill(call.pid, 'SIGKILL'); } catch { /* da chet */ } });
  assert.throws(() => process.kill(call.pid, 0), /ESRCH/, 'agy van song sau khi PM bi SIGTERM');
});

test('mo luot that bai (agy thoat khong co init): nha cho giu, lan gui sau khong bi chan nham', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: '15151515-2222-3333-4444-555555555555' });
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  await sleep(800);
  process.env.FAKE_AGY_NO_INIT = '1';
  await assert.rejects(sendMessage({ conversationId, content: 'hong' }), /init/);
  delete process.env.FAKE_AGY_NO_INIT;
  assert.equal(agyTurnStatus(conversationId).starting, false);
  await sendMessage({ conversationId, content: 'lan hai' });
  assert.equal(fake.calls().filter((c) => c.args.includes('--conversation')).length, 2);
});

test('moi truong test KHONG tim thay agy that (helpers.js): test tang tool khong the sinh agent Argon that', () => {
  assert.equal(agyPath(), null);
});
