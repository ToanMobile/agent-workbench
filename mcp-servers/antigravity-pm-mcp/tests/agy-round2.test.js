// Vong 2 review (14/10/2026: principal-code-reviewer + OpenCodeReview Opus 5.5) cua duong agy. Moi test o day khoa MOT loi da do duoc.
// agy that khong bao gio duoc goi: ANTIGRAVITY_PM_AGY tro vao script gia (hoac vao file khong co, xem tests/helpers.js).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import { newConversation, sendMessage, getConversationMetadata, agyTurnStatus } from '../src/agentapi.js';
import { AntigravityUnavailable } from '../src/discover.js';
import { loadConfig } from '../src/config.js';
import { resolveProject } from '../src/projects.js';
import { updateTask, loadTask } from '../src/tasks.js';
import { TOOLS_BY_NAME } from '../src/tools.js';
import { homeStateDir } from '../src/util.js';
import * as util from '../src/util.js';
import { tmpProject, tmpGlobalConfig, cleanup, writeFile, NO_AGY } from './helpers.js';

const ARGON = 'gemini-4-argon-high';
const FAKE = `#!/usr/bin/env node
const fs = require('node:fs');
const a = process.argv.slice(2);
const i = a.indexOf('--conversation');
const id = i >= 0 ? a[i + 1] : (process.env.FAKE_AGY_ID || 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
fs.appendFileSync(process.env.FAKE_AGY_LOG, JSON.stringify({ args: a, cwd: process.cwd(), pid: process.pid }) + '\\n');
if (process.env.FAKE_AGY_CORRUPT_REGISTRY) fs.writeFileSync(process.env.FAKE_AGY_CORRUPT_REGISTRY, '{"x":');   // so dang ky hong GIUA luc agy chay
// FAKE_AGY_SPACED_JSON: dong stream-json co khoang trang sau ":" va "," ({"event": "init", ...}) thay vi JSON gon
const out = (o) => console.log(process.env.FAKE_AGY_SPACED_JSON ? JSON.stringify(o).replace(/":/g, '": ').replace(/,"/g, ', "') : JSON.stringify(o));
setTimeout(() => out({ event: 'init', conversation_id: id, init: { cwd: process.env.FAKE_AGY_INIT_CWD || process.cwd() } }), Number(process.env.FAKE_AGY_INIT_DELAY_MS || 0));
setTimeout(() => out({ event: 'result', result: { conversation_id: id, status: 'SUCCESS' } }), Number((i >= 0 && process.env.FAKE_AGY_HOLD_RESUME_MS) || process.env.FAKE_AGY_HOLD_MS || 0) + Number(process.env.FAKE_AGY_INIT_DELAY_MS || 0));
`;
const KEYS = ['FAKE_AGY_SPACED_JSON', 'FAKE_AGY_HOLD_RESUME_MS', 'ANTIGRAVITY_PM_PING_WAIT_MS', 'FAKE_AGY_INIT_CWD', 'FAKE_AGY_CORRUPT_REGISTRY', 'ANTIGRAVITY_PM_PS', 'ANTIGRAVITY_LS_ADDRESS', 'ANTIGRAVITY_CSRF_TOKEN', 'ANTIGRAVITY_PM_AGY', 'FAKE_AGY_LOG', 'FAKE_AGY_ID', 'FAKE_AGY_HOLD_MS', 'FAKE_AGY_INIT_DELAY_MS', 'ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS', 'ANTIGRAVITY_PM_PROJECTS_DIR', 'HOME'];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const SRC = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../src/agentapi.js');

function fakeAgy(t, env = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-r2-'));
  const bin = path.join(dir, 'agy');
  fs.writeFileSync(bin, FAKE, { mode: 0o755 });
  const log = path.join(dir, 'calls.jsonl');
  const prev = { ...process.env };
  Object.assign(process.env, { ANTIGRAVITY_PM_AGY: bin, FAKE_AGY_LOG: log, ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS: '1' }, env);
  t.after(() => {
    for (const k of KEYS) { if (prev[k] === undefined) delete process.env[k]; else process.env[k] = prev[k]; }
    fs.rmSync(path.join(homeStateDir(), 'agy-conversations.json'), { force: true });   // chung cho ca file test: mot test do bo day khong duoc keo test sau
    cleanup(dir);
  });
  return { dir, bin, log, calls: () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l)) : []) };
}
const mkProject = (t, config = {}) => { const d = tmpProject(config); t.after(() => cleanup(d)); return d; };
const call = async (name, args) => { const out = await TOOLS_BY_NAME.get(name).handler(args); return typeof out === 'string' ? { text: out } : out; };
const registryFile = () => path.join(homeStateDir(), 'agy-conversations.json');
const newTask = async (dir) => {
  const created = await call('pm_task_create', { project: dir, title: 'a', brief: 'b', definitionOfDone: ['c'] });
  return /T\d{4}-[a-z0-9-]+/.exec(created.text)[0];
};
const setConversation = (dir, taskId, conversationId) => {
  const cfg = loadConfig(dir);
  updateTask(cfg, loadTask(cfg, taskId), (tk) => { tk.conversationId = conversationId; });
};

// ---------------------------------------------------------------- dau van tay tien trinh (F2)

test('dau van tay tien trinh khong phu thuoc TZ/locale cua PM: PM thu hai (TZ=UTC) van thay luot dang chay', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'a1a1a1a1-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '6000' });
  const project = mkProject(t);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  const probe = `import { agyTurnStatus } from ${JSON.stringify(SRC)}; console.log(JSON.stringify(agyTurnStatus(${JSON.stringify(conversationId)})));`;
  const out = execFileSync(process.execPath, ['--input-type=module', '-e', probe], { env: { ...process.env, TZ: 'UTC', LC_ALL: 'fr_FR.UTF-8' }, encoding: 'utf8' });
  assert.equal(JSON.parse(out.trim().split('\n').pop()).running, true, `PM thu hai (TZ=UTC) bao agy khong chay: ${out}`);
});

test('khong doc duoc dau van tay (khong co ps): NEM LOI to, khong coi la "luot da xong" roi sinh agy thu hai', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'a2a2a2a2-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '6000' });
  const project = mkProject(t);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  const probe = `import { sendMessage } from ${JSON.stringify(SRC)};
    sendMessage({ conversationId: ${JSON.stringify(conversationId)}, content: 'chong' }).then(() => console.log('SENT'), (e) => console.log('REJECTED ' + e.message.slice(0, 80)));`;
  const out = execFileSync(process.execPath, ['--input-type=module', '-e', probe], { env: { ...process.env, ANTIGRAVITY_PM_PS: '/nonexistent/ps' }, encoding: 'utf8' });
  assert.match(out, /REJECTED .*dau van tay/, `gui duoc khi khong doc duoc dau van tay: ${out}`);
});

// ---------------------------------------------------------------- hai tien trinh PM (F4)

test('hai tien trinh PM gui cung luc vao mot hoi thoai: chi MOT agy (khoa file, khong chi bien trong bo nho)', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'a3a3a3a3-2222-3333-4444-555555555555' });
  const project = mkProject(t);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  await sleep(900);
  const start = Date.now() + 1500;
  const probe = `import { sendMessage } from ${JSON.stringify(SRC)};
    const wait = ${start} - Date.now(); await new Promise((r) => setTimeout(r, Math.max(0, wait)));
    sendMessage({ conversationId: ${JSON.stringify(conversationId)}, content: 'x' }).then(() => console.log('SENT'), () => console.log('REJECTED'));`;
  const run = () => new Promise((resolve) => {
    let out = '';
    const c = spawn(process.execPath, ['--input-type=module', '-e', probe], { env: process.env });
    c.stdout.on('data', (d) => { out += d; });
    c.on('exit', () => resolve(out.trim()));
  });
  const results = await Promise.all([run(), run()]);
  assert.equal(results.filter((r) => r === 'SENT').length, 1, JSON.stringify(results));
  assert.equal(fake.calls().filter((c) => c.args.includes('--conversation')).length, 1);
});

// ---------------------------------------------------------------- so dang ky (OCR 1, F5, F6, F12)

test('so dang ky hong: newConversation that bai TRUOC khi spawn (khong de agy mo coi chay khong ai theo doi)', async (t) => {
  const fake = fakeAgy(t);
  fs.writeFileSync(registryFile(), '{"a": ');
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) }), /agy-conversations\.json hong/);
  assert.equal(fake.calls().length, 0, 'agy da bi spawn truoc khi biet so dang ky hong');
  fs.rmSync(registryFile());
});

test('sendMessage ghi pid agy THAT ngay sau spawn: PM chet giua luc cho init thi luot sau van thay agy dang chay', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'a4a4a4a4-2222-3333-4444-555555555555' });
  const project = mkProject(t);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  await sleep(900);
  process.env.FAKE_AGY_INIT_DELAY_MS = '4000';
  process.env.FAKE_AGY_HOLD_MS = '6000';
  const pending = sendMessage({ conversationId, content: 'cho init' }).catch(() => {});
  await sleep(1200);   // agy da spawn, chua in init
  const st = agyTurnStatus(conversationId);
  const spawned = fake.calls().filter((c) => c.args.includes('--conversation')).pop();
  assert.equal(st.pid, spawned.pid, 'registry phai giu pid agy that, khong phai pid cua PM');
  assert.equal(st.running, true);
  await pending;
});

test('muc thieu model/cwd (bi duoi roi ghi lai): loi ro, khong phai "undefined khong con ton tai"', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'a5a5a5a5-2222-3333-4444-555555555555' });
  fs.writeFileSync(registryFile(), JSON.stringify({ stub: { at: new Date().toISOString() } }));
  await assert.rejects(sendMessage({ conversationId: 'stub', content: 'x' }), /thieu model\/cwd/);
  fs.rmSync(registryFile());
});

test('mo luot that bai (thu muc mat): ten loi GOC con nguyen va cho giu duoc nha', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'a6a6a6a6-2222-3333-4444-555555555555' });
  const project = mkProject(t);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  await sleep(900);
  fs.rmSync(project, { recursive: true, force: true });
  await assert.rejects(sendMessage({ conversationId, content: 'x' }), /khong con ton tai/);
  assert.equal(agyTurnStatus(conversationId).starting, false, 'cho giu phai duoc nha');
});

// ---------------------------------------------------------------- cwd khong ton tai (rev1 #11)

test('newConversation voi cwd khong ton tai: loi noi dung nguyen nhan, khong phai ENOENT lstat tho', async (t) => {
  fakeAgy(t);
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON, cwd: path.join(os.tmpdir(), 'agpm-khong-co-thu-muc') }), /khong con ton tai/);
});

// ---------------------------------------------------------------- chot quyen (OCR 6, F7)

test('chot quyen khop CHINH XAC: ten policy chi chua EAGER/TURBO o giua khong tinh', async (t) => {
  const fake = fakeAgy(t);
  delete process.env.ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS;
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-r2-home-'));
  t.after(() => cleanup(home));
  process.env.HOME = home;
  process.env.ANTIGRAVITY_PM_PROJECTS_DIR = path.join(home, 'projects');
  fs.mkdirSync(process.env.ANTIGRAVITY_PM_PROJECTS_DIR);
  fs.mkdirSync(path.join(home, '.gemini/config'), { recursive: true });
  fs.writeFileSync(path.join(home, '.gemini/config/config.json'), JSON.stringify({ userSettings: { autoExecutionPolicy: 'NOT_EAGER_AT_ALL_REQUEST_REVIEW' } }));
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) }), /EAGER\/TURBO/);
  assert.equal(fake.calls().length, 0);
});

test('project long nhau: chinh sach cua project GAN NHAT quyet dinh, khong phu thuoc thu tu readdir', (t) => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-r2-home-'));
  t.after(() => cleanup(home));
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-r2-mono-'));
  t.after(() => cleanup(root));
  const inner = path.join(root, 'apps');
  fs.mkdirSync(path.join(inner, 'web'), { recursive: true });
  const prev = process.env.ANTIGRAVITY_PM_PROJECTS_DIR;
  process.env.ANTIGRAVITY_PM_PROJECTS_DIR = path.join(home, 'projects');
  t.after(() => { if (prev === undefined) delete process.env.ANTIGRAVITY_PM_PROJECTS_DIR; else process.env.ANTIGRAVITY_PM_PROJECTS_DIR = prev; });
  fs.mkdirSync(process.env.ANTIGRAVITY_PM_PROJECTS_DIR);
  for (const [name, dir, policy] of [['0-first', root, 'EAGER'], ['a-outer', root, 'EAGER'], ['b-inner', inner, 'OFF']]) {
    fs.writeFileSync(path.join(process.env.ANTIGRAVITY_PM_PROJECTS_DIR, `${name}.json`), JSON.stringify({
      id: name, name, workspaces: [{ folderUri: `file://${fs.realpathSync(dir)}` }], settings: { autoExecutionPolicy: policy },
    }));
  }
  assert.equal(resolveProject(path.join(inner, 'web')).id, 'b-inner');
});

// ---------------------------------------------------------------- tang tool (F3, F1, OCR 10/11)

test('pm_dispatch plan_review voi Argon: KHONG can project da dang ky trong IDE, va chay agy o thu muc project', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'b1b1b1b1-2222-3333-4444-555555555555' });
  process.env.ANTIGRAVITY_PM_PROJECTS_DIR = path.join(os.tmpdir(), 'agpm-r2-khong-co-so-project');   // so dang ky IDE rong
  const dir = mkProject(t, { defaultModel: ARGON });
  const taskId = await newTask(dir);
  await call('pm_plan', { project: dir, taskId, content: '# x\n1. lam\n2. test', files: ['src/a.js'] });
  const out = await call('pm_dispatch', { project: dir, taskId, kind: 'plan_review' });
  assert.match(out.text, /conversationId=/);
  const [c] = fake.calls();
  assert.equal(fs.realpathSync(c.cwd), fs.realpathSync(dir));
});

test('pm_dispatch audit: agy chay o thu muc project (cwd khong bi bo)', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'b2b2b2b2-2222-3333-4444-555555555555' });
  const dir = mkProject(t, { defaultModel: ARGON });
  const taskId = await newTask(dir);
  await call('pm_dispatch', { project: dir, taskId, kind: 'audit' });
  const [c] = fake.calls();
  assert.equal(fs.realpathSync(c.cwd), fs.realpathSync(dir));
});

test('pm_status nudge khi luot agy DANG CHAY (nhanh lam viec): khong reject ca tool, noi ro, khong khuyen kill pid cua PM', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'b3b3b3b3-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '3000' });
  const dir = mkProject(t, { defaultModel: ARGON });
  const taskId = await newTask(dir);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: dir });
  setConversation(dir, taskId, conversationId);
  const out = await call('pm_status', { project: dir, taskId, nudge: true });
  assert.match(out.text, /Luot agy: DANG CHAY/);
  assert.match(out.text, /Khong nhac duoc agent/);
  assert.ok(!out.text.includes(`kill -- -${process.pid}`), 'khuyen kill pid cua chinh PM');
});

test('pm_status khi PM dang MO luot (starting) va hoi thoai im lau: khong khuyen kill pid cua PM, noi dang khoi dong', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'b6b6b6b6-2222-3333-4444-555555555555' });
  const dir = mkProject(t, { defaultModel: ARGON, stallMinutes: 5 });
  const taskId = await newTask(dir);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: dir });
  setConversation(dir, taskId, conversationId);
  await sleep(900);
  // hoi thoai im 30 phut: db cua agy trong HOME gia co mtime cu => pm_status vao nhanh "stalled"
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-r2-home-'));
  t.after(() => cleanup(home));
  fs.mkdirSync(path.join(home, '.gemini/antigravity-cli/conversations'), { recursive: true });
  const dbFile = path.join(home, `.gemini/antigravity-cli/conversations/${conversationId}.db`);
  fs.writeFileSync(dbFile, 'x');
  const old = new Date(Date.now() - 30 * 60000);
  fs.utimesSync(dbFile, old, old);
  process.env.HOME = home;
  const reg = JSON.parse(fs.readFileSync(registryFile(), 'utf8'));
  Object.assign(reg[conversationId], { pid: process.pid, pidTag: execFileSync('/bin/ps', ['-o', 'lstart=', '-p', String(process.pid)], { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' } }).trim(), starting: true });
  fs.writeFileSync(registryFile(), JSON.stringify(reg));
  const out = await call('pm_status', { project: dir, taskId });
  assert.ok(!out.text.includes(`kill -- -${process.pid}`), out.text);
  assert.match(out.text, /dang mo luot moi/);
});

test('pm_status khong doc duoc dau van tay (khong co ps): in "KHONG biet" cho luot agy, KHONG reject ca tool', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'b7b7b7b7-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '3000' });
  const dir = mkProject(t, { defaultModel: ARGON });
  const taskId = await newTask(dir);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: dir });
  setConversation(dir, taskId, conversationId);
  process.env.ANTIGRAVITY_PM_PS = '/nonexistent/ps';
  const out = await call('pm_status', { project: dir, taskId });
  assert.match(out.text, /Luot agy: KHONG biet/);
  assert.ok(!/DA KET THUC/.test(out.text), 'trang thai "khong biet" bi in nhu "da ket thuc"');
});

test('pm_status nudge nhanh PLAN (hoi thoai phan bien la agy dang chay): khong reject ca tool', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'b4b4b4b4-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '3000' });
  const dir = mkProject(t, { defaultModel: ARGON });
  const taskId = await newTask(dir);
  await call('pm_plan', { project: dir, taskId, content: '# x\n1. lam\n2. test', files: ['src/a.js'] });
  await call('pm_dispatch', { project: dir, taskId, kind: 'plan_review' });
  const out = await call('pm_status', { project: dir, taskId, nudge: true });
  assert.ok(out.text.includes(taskId));
});

test('loi that (khong phai "dang chay") khi nudge agy van NO to, kem goi y (khong bi nuot)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'b5b5b5b5-2222-3333-4444-555555555555' });
  const dir = mkProject(t, { defaultModel: ARGON });
  const taskId = await newTask(dir);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: dir });
  await sleep(900);
  setConversation(dir, taskId, conversationId);
  process.env.ANTIGRAVITY_PM_AGY = NO_AGY;   // agy bien mat giua chung
  await assert.rejects(call('pm_status', { project: dir, taskId, nudge: true }), /agy/);
});

test('registry agy hong: pm_status cua task IDE (flash) van chay, khong bi keo sap', async (t) => {
  fakeAgy(t);
  const dir = mkProject(t, { defaultModel: 'flash' });
  const taskId = await newTask(dir);
  setConversation(dir, taskId, 'cccccccc-2222-3333-4444-555555555555');
  fs.writeFileSync(registryFile(), '{"broken": ');
  const out = await call('pm_status', { project: dir, taskId });
  assert.ok(out.text.includes(taskId));
  assert.match(out.text, /agy-conversations\.json hong/, 'so dang ky agy hong phai hien o pm_status (khong chi o stderr)');
  fs.rmSync(registryFile());
});

test('registry agy hong: gui tin va metadata cua hoi thoai IDE khong bi chan boi file cua agy', async (t) => {
  fakeAgy(t, { ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });   // IDE gia: cong dong, khong cham IDE that
  fs.writeFileSync(registryFile(), '{"broken": ');
  // loi cua DUONG IDE (khong phai loi ghi/doc so dang ky cua duong agy) + goi y nguyen nhan that: so dang ky hong
  const ide = (e) => /^agentapi /.test(e.message) && /LUU Y: so dang ky agy/.test(e.message);   // bat dau bang loi cua agentapi (khong phai loi doc so dang ky) + goi y
  await assert.rejects(getConversationMetadata('dddddddd-2222-3333-4444-555555555555'), ide);
  await assert.rejects(sendMessage({ conversationId: 'dddddddd-2222-3333-4444-555555555555', content: 'x' }), ide);
  fs.rmSync(registryFile());
});

// ---------------------------------------------------------------- cau hinh giaoDefault (F3/F10)

test('giaoDefault duoc loader chap nhan o file chung va file project (project de len), khong canh bao "khoa la"', (t) => {
  const g = tmpGlobalConfig({ giaoDefault: true });
  t.after(() => g.restore());
  const dir = mkProject(t, {});
  let cfg = loadConfig(dir);
  assert.equal(cfg.giaoDefault, true);
  assert.deepEqual(cfg.warnings.filter((w) => /giaoDefault/.test(w)), []);
  writeFile(path.join(dir, '.antigravity-pm.json'), JSON.stringify({ giaoDefault: false }));
  cfg = loadConfig(dir);
  assert.equal(cfg.giaoDefault, false);
});

test('ghi so dang ky that bai SAU khi mo luot: dung agy vua mo (khong de agent chay ma PM khong theo doi) va noi ro', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'e1e1e1e1-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '20000', FAKE_AGY_CORRUPT_REGISTRY: registryFile() });
  const project = mkProject(t);
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON, cwd: project }), /da dung agy pid \d+/);
  const [call1] = fake.calls();
  t.after(() => { try { process.kill(call1.pid, 'SIGKILL'); } catch { /* da chet */ } });
  await sleep(500);
  assert.throws(() => process.kill(call1.pid, 0), /ESRCH/, 'agy van song sau khi khong ghi duoc so dang ky');
  fs.rmSync(registryFile(), { force: true });
});

test('khong co agy: loi la AntigravityUnavailable BAT KE chinh sach quyen that cua may (kiem agy truoc, chot quyen sau)', async (t) => {
  fakeAgy(t);
  process.env.ANTIGRAVITY_PM_AGY = NO_AGY;
  delete process.env.ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS;
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-r2-home-'));
  t.after(() => cleanup(home));
  process.env.HOME = home;   // khong co ~/.gemini/config => chinh sach "chua dat": chot quyen se tu choi neu no chay truoc
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) }), (e) => e instanceof AntigravityUnavailable);
});

test('don so dang ky (>500): KHONG xoa muc co luot agy dang chay, du la muc cu nhat', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'c1c1c1c1-2222-3333-4444-555555555555' });
  const sleeper = spawn('sleep', ['60'], { stdio: 'ignore' });
  t.after(() => sleeper.kill());
  const tag = execFileSync('/bin/ps', ['-o', 'lstart=', '-p', String(sleeper.pid)], { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' } }).trim();
  const reg = {};
  for (let i = 0; i < 505; i++) reg[`c${i}`] = { model: ARGON, cwd: os.tmpdir(), at: new Date(2020, 0, 1, 0, 0, i).toISOString() };
  Object.assign(reg.c0, { pid: sleeper.pid, pidTag: tag });   // cu nhat va DANG CHAY
  fs.writeFileSync(registryFile(), JSON.stringify(reg));
  await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  const after = JSON.parse(fs.readFileSync(registryFile(), 'utf8'));
  assert.ok(after.c0, 'muc co luot agy dang chay bi don mat');
  assert.ok(!after.c1, 'muc cu nhat KHONG chay phai bi don');
  fs.rmSync(registryFile());
});

test('pm_doctor ping agy: workspace khong ton tai khong lam sap ping (van cho luot, gui tin, cho luot 2)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'c2c2c2c2-2222-3333-4444-555555555555', FAKE_AGY_INIT_CWD: '/nowhere/else', ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  const dir = mkProject(t, { defaultModel: ARGON });
  const out = await call('pm_doctor', { project: dir, ping: true });
  assert.match(out.text, /mo MOT luot agy that/, 'ping phai noi no chay agent that');
  assert.match(out.text, /Luot 1: xong/, out.text);
  assert.match(out.text, /Gui tin tiep \(agy --conversation --model\): OK/, out.text);
  assert.match(out.text, /Luot 2: xong/, out.text);
});

test('gui tin khi agy bien mat va chinh sach quyen khong dat: van la AntigravityUnavailable (kiem agy truoc, ca duong gui tin)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'c3c3c3c3-2222-3333-4444-555555555555' });
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  await sleep(900);
  process.env.ANTIGRAVITY_PM_AGY = NO_AGY;
  delete process.env.ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS;
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-r2-home-'));
  t.after(() => cleanup(home));
  process.env.HOME = home;
  await assert.rejects(sendMessage({ conversationId, content: 'x' }), (e) => e instanceof AntigravityUnavailable);
});

test('loi "dang chay luot" mang ma AGY_TURN_BUSY (tool khong do bang cau chu tieng Viet)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'd1d1d1d1-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '3000' });
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  await assert.rejects(sendMessage({ conversationId, content: 'nhac' }), (e) => e.code === 'AGY_TURN_BUSY');
});

test('PM khong doc duoc dau van tay (ps) luc mo hoi thoai moi: tu choi ro rang, KHONG sap server, agy vua mo bi dung', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'd2d2d2d2-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '20000' });
  process.env.ANTIGRAVITY_PM_PS = '/nonexistent/ps';
  await assert.rejects(newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) }), /dau van tay/);
  const [c] = fake.calls();
  t.after(() => { try { process.kill(c.pid, 'SIGKILL'); } catch { /* da chet */ } });
  await sleep(500);
  assert.throws(() => process.kill(c.pid, 0), /ESRCH/, 'agy van song khi PM khong theo doi duoc no');
});

test('cho giu "starting" qua han (PM nha cho that bai, PM van song): khong chan gui tin mai mai', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'd3d3d3d3-2222-3333-4444-555555555555' });
  const project = mkProject(t);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  await sleep(900);
  const reg = JSON.parse(fs.readFileSync(registryFile(), 'utf8'));
  const tag = execFileSync('/bin/ps', ['-o', 'lstart=', '-p', String(process.pid)], { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' } }).trim();
  Object.assign(reg[conversationId], { pid: process.pid, pidTag: tag, starting: true, reservation: true, reservedAt: new Date(Date.now() - 10 * 60000).toISOString() });
  fs.writeFileSync(registryFile(), JSON.stringify(reg));
  await sendMessage({ conversationId, content: 'sau khi cho het han' });
  assert.equal(fake.calls().filter((c) => c.args.includes('--conversation')).length, 1);
});

test('cho giu "starting" con TUOI van chan (khong het han som)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'd4d4d4d4-2222-3333-4444-555555555555' });
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  await sleep(900);
  const reg = JSON.parse(fs.readFileSync(registryFile(), 'utf8'));
  const tag = execFileSync('/bin/ps', ['-o', 'lstart=', '-p', String(process.pid)], { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' } }).trim();
  Object.assign(reg[conversationId], { pid: process.pid, pidTag: tag, starting: true, reservation: true, reservedAt: new Date().toISOString() });
  fs.writeFileSync(registryFile(), JSON.stringify(reg));
  await assert.rejects(sendMessage({ conversationId, content: 'x' }), (e) => e.code === 'AGY_TURN_BUSY');
});

// ---------------------------------------------------------------- vong 4 (reviewer 3 + OCR lan 2)

test('cho giu qua han CHI ap cho cho giu cua PM; muc co pid agy THAT + starting thi khong het han (agy van chay du PM da chet)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'f1f1f1f1-2222-3333-4444-555555555555' });
  const project = mkProject(t);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  await sleep(900);
  const sleeper = spawn('sleep', ['60'], { stdio: 'ignore' });   // "agy that" dang chay: pid + dau van tay dung
  t.after(() => sleeper.kill());
  const tag = execFileSync('/bin/ps', ['-o', 'lstart=', '-p', String(sleeper.pid)], { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' } }).trim();
  const reg = JSON.parse(fs.readFileSync(registryFile(), 'utf8'));
  Object.assign(reg[conversationId], { pid: sleeper.pid, pidTag: tag, starting: true, reservation: false, reservedAt: new Date(Date.now() - 10 * 60000).toISOString() });
  fs.writeFileSync(registryFile(), JSON.stringify(reg));
  await assert.rejects(sendMessage({ conversationId, content: 'x' }), (e) => e.code === 'AGY_TURN_BUSY');
});

test('pm_status nudge khi ps hong (khong biet luot agy): in "KHONG biet", bo qua nudge, KHONG reject ca tool', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'f2f2f2f2-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '3000' });
  const dir = mkProject(t, { defaultModel: ARGON });
  const taskId = await newTask(dir);
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: dir });
  setConversation(dir, taskId, conversationId);
  process.env.ANTIGRAVITY_PM_PS = '/nonexistent/ps';
  const out = await call('pm_status', { project: dir, taskId, nudge: true });
  assert.match(out.text, /Luot agy: KHONG biet/);
  assert.match(out.text, /Khong nhac duoc/);
});

test('pm_doctor noi dung agy co duoc --dangerously-skip-permissions hay khong (chinh sach that, khong phai regex long)', async (t) => {
  fakeAgy(t, { ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  delete process.env.ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS;
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-r2-home-'));
  t.after(() => cleanup(home));
  process.env.HOME = home;
  fs.mkdirSync(path.join(home, '.gemini/config'), { recursive: true });
  fs.writeFileSync(path.join(home, '.gemini/config/config.json'), JSON.stringify({ userSettings: { autoExecutionPolicy: 'CASCADE_COMMANDS_AUTO_EXECUTION_OFF' } }));
  const dir = mkProject(t, { defaultModel: ARGON });
  const out = await call('pm_doctor', { project: dir });
  assert.match(out.text, /agy --dangerously-skip-permissions: KHONG DUOC/, out.text);
  fs.writeFileSync(path.join(home, '.gemini/config/config.json'), JSON.stringify({ userSettings: { autoExecutionPolicy: 'CASCADE_COMMANDS_AUTO_EXECUTION_EAGER' } }));
  const out2 = await call('pm_doctor', { project: dir });
  assert.match(out2.text, /agy --dangerously-skip-permissions: DUOC/, out2.text);
});

test('don so dang ky: ps loi o MOT muc cu thi giu muc do va di tiep, KHONG lam hong luot agy vua mo (khong stopUntracked)', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'a7a7a7a7-2222-3333-4444-555555555555' });
  const wrapper = path.join(fake.dir, 'ps-wrapper.sh');
  fs.writeFileSync(wrapper, '#!/bin/sh\nif [ "$4" = "999999" ]; then echo boom >&2; exit 2; fi\nexec /bin/ps "$@"\n', { mode: 0o755 });
  process.env.ANTIGRAVITY_PM_PS = wrapper;
  const reg = {};
  for (let i = 0; i < 505; i++) reg[`c${i}`] = { model: ARGON, cwd: os.tmpdir(), at: new Date(2020, 0, 1, 0, 0, i).toISOString() };
  Object.assign(reg.c0, { pid: 999999, pidTag: 'khong the biet' });   // cu nhat; ps loi khi hoi ve no
  fs.writeFileSync(registryFile(), JSON.stringify(reg));
  const r = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  assert.ok(r.conversationId);
  const after = JSON.parse(fs.readFileSync(registryFile(), 'utf8'));
  assert.ok(after.c0, 'muc khong xac dinh duoc phai o lai');
  assert.ok(after[r.conversationId]);
  fs.rmSync(registryFile());
});

test('pm_plan_review: luot agy DA THOAT ma chua co plan-review.json: noi ro (khong bao "chua co" nhu dang chay)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'a8a8a8a8-2222-3333-4444-555555555555' });
  const dir = mkProject(t, { defaultModel: ARGON });
  const taskId = await newTask(dir);
  await call('pm_plan', { project: dir, taskId, content: '# x\n1. lam\n2. test', files: ['src/a.js'] });
  await call('pm_dispatch', { project: dir, taskId, kind: 'plan_review' });
  await sleep(900);   // agy gia thoat ngay, khong ghi plan-review.json
  const out = await call('pm_status', { project: dir, taskId });
  assert.match(out.text, /plan-review\.json: chua co .*luot agy DA KET THUC/, out.text);
});

test('pm_doctor ping agy: luot con chay sau khi cho het gio thi PING TU DUNG no (khong de agent chay khong giam sat)', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'a9a9a9a9-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '300000', ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  process.env.ANTIGRAVITY_PM_PING_WAIT_MS = '1500';   // test: khong cho 90 s
  t.after(() => { delete process.env.ANTIGRAVITY_PM_PING_WAIT_MS; });
  const dir = mkProject(t, { defaultModel: ARGON });
  const out = await call('pm_doctor', { project: dir, ping: true });
  assert.match(out.text, /da dung agy pid \d+/, out.text);
  const [c] = fake.calls();
  t.after(() => { try { process.kill(c.pid, 'SIGKILL'); } catch { /* da chet */ } });
  await sleep(500);
  assert.throws(() => process.kill(c.pid, 0), /ESRCH/);
});

test('pm_doctor bao so dang ky agy hong', async (t) => {
  fakeAgy(t, { ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  fs.writeFileSync(registryFile(), '{"broken": ');
  const dir = mkProject(t, { defaultModel: ARGON });
  const out = await call('pm_doctor', { project: dir });
  assert.match(out.text, /SO DANG KY AGY HONG/, out.text);
  fs.rmSync(registryFile());
});

test('registry agy hong + nudge, task model AGY: khong biet luot nao dang chay => bo qua nudge, noi ro, KHONG reject ca tool, bao hong MOT lan', async (t) => {
  fakeAgy(t);
  const dir = mkProject(t, { defaultModel: ARGON });
  const taskId = await newTask(dir);
  setConversation(dir, taskId, 'cccccccc-2222-3333-4444-555555555555');
  fs.writeFileSync(registryFile(), '{"broken": ');
  const out = await call('pm_status', { project: dir, taskId, nudge: true });
  assert.match(out.text, /Khong nhac duoc agent: khong biet trang thai luot agy/);
  assert.equal((out.text.match(/agy-conversations\.json hong/g) || []).length, 1, out.text);
  fs.rmSync(registryFile());
});

test('registry agy hong + nudge, task model IDE (flash): nudge KHONG bi chan boi file cua agy (di sang IDE, loi la loi cua IDE)', async (t) => {
  fakeAgy(t, { ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  const dir = mkProject(t, { defaultModel: 'flash' });
  const taskId = await newTask(dir);
  setConversation(dir, taskId, 'cccccccc-2222-3333-4444-555555555555');
  fs.writeFileSync(registryFile(), '{"broken": ');
  await assert.rejects(call('pm_status', { project: dir, taskId, nudge: true }), (e) => /^agentapi /.test(e.message));   // loi IDE that (cong dong), khong phai "khong biet luot agy"
  fs.rmSync(registryFile());
});

test('ping: loi giua chung sau khi mo luot (ps hong o vong cho) van DUNG agy cua ping (finally), khong de chay khong giam sat', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'b8b8b8b8-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '300000', ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  const counter = path.join(fake.dir, 'ps-count');
  const wrapper = path.join(fake.dir, 'ps-flaky.sh');
  // ps that works for the first 2 calls (agyStart's fingerprint + the first status), then fails: the wait loop throws after the agent is up
  fs.writeFileSync(wrapper, `#!/bin/sh\nn=$(cat "${counter}" 2>/dev/null || echo 0)\nn=$((n+1))\necho $n > "${counter}"\nif [ $n -gt 2 ]; then echo boom >&2; exit 2; fi\nexec /bin/ps "$@"\n`, { mode: 0o755 });
  process.env.ANTIGRAVITY_PM_PS = wrapper;
  const dir = mkProject(t, { defaultModel: ARGON });
  const out = await call('pm_doctor', { project: dir, ping: true });
  assert.match(out.text, /PING AGY THAT BAI/, out.text);
  const [c] = fake.calls();
  t.after(() => { try { process.kill(c.pid, 'SIGKILL'); } catch { /* da chet */ } });
  await sleep(500);
  assert.throws(() => process.kill(c.pid, 0), /ESRCH/, 'agy cua ping van song sau khi ping that bai');
});

test('don so dang ky: so lan hoi ps bi chan tren (khong giu khoa vai chuc giay khi nhieu muc ps cham)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'b9b9b9b9-2222-3333-4444-555555555555' });
  const dirW = fs.mkdtempSync(path.join(os.tmpdir(), 'agpm-r2-ps-'));
  t.after(() => cleanup(dirW));
  const counter = path.join(dirW, 'count');
  const wrapper = path.join(dirW, 'ps-count.sh');
  fs.writeFileSync(wrapper, `#!/bin/sh\necho x >> "${counter}"\nexec /bin/ps "$@"\n`, { mode: 0o755 });
  process.env.ANTIGRAVITY_PM_PS = wrapper;
  const reg = {};
  const sleepers = [];
  for (let i = 0; i < 520; i++) reg[`c${i}`] = { model: ARGON, cwd: os.tmpdir(), at: new Date(2020, 0, 1, 0, 0, i).toISOString() };
  for (let i = 0; i < 20; i++) {   // 20 muc cu nhat deu "dang chay": pruning phai dung sau vai lan hoi, khong hoi het
    const sl = spawn('sleep', ['60'], { stdio: 'ignore' });
    sleepers.push(sl);
    const tag = execFileSync('/bin/ps', ['-o', 'lstart=', '-p', String(sl.pid)], { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' } }).trim();
    Object.assign(reg[`c${i}`], { pid: sl.pid, pidTag: tag });
  }
  t.after(() => sleepers.forEach((x) => x.kill()));
  fs.writeFileSync(registryFile(), JSON.stringify(reg));
  await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  const calls = fs.readFileSync(counter, 'utf8').trim().split('\n').length;
  assert.ok(calls <= 12, `ps duoc goi ${calls} lan trong luc don so dang ky (phai bi chan tren)`);
  fs.rmSync(registryFile());
});

test('ping: luot 2 (gui tin) con chay khi het gio thi PING DUNG ca agy cua luot 2, khong chi luot 1', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'bababaab-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '0', FAKE_AGY_HOLD_RESUME_MS: '300000', ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  process.env.ANTIGRAVITY_PM_PING_WAIT_MS = '1500';
  const dir = mkProject(t, { defaultModel: ARGON });
  const out = await call('pm_doctor', { project: dir, ping: true });
  const calls = fake.calls();
  const resumed = calls.find((c) => c.args.includes('--conversation'));
  assert.ok(resumed, `khong thay luot 2: ${out.text}`);
  t.after(() => { try { process.kill(resumed.pid, 'SIGKILL'); } catch { /* da chet */ } });
  await sleep(500);
  assert.throws(() => process.kill(resumed.pid, 0), /ESRCH/, 'agy cua luot 2 van song sau khi ping ket thuc');
});

test('so dang ky hong va goi IDE that bai: loi kem nguyen nhan THAT (so dang ky), khong chi "trajectory not found"', async (t) => {
  fakeAgy(t, { ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  fs.writeFileSync(registryFile(), '{"broken": ');
  await assert.rejects(sendMessage({ conversationId: 'eeeeeeee-2222-3333-4444-555555555555', content: 'x' }), /LUU Y: so dang ky agy .*agy-conversations\.json/);
  fs.rmSync(registryFile());
});

test('khoa so dang ky con TUOI cua PM khac: khong cuop, bao loi ro sau ~3 s (khong tu y xoa)', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'bcbcbcbc-2222-3333-4444-555555555555' });
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  await sleep(900);
  const lock = `${registryFile()}.lock`;
  fs.writeFileSync(lock, 'pm-khac');   // moi tao: chu khoa dang lam viec
  t.after(() => fs.rmSync(lock, { force: true }));
  await assert.rejects(sendMessage({ conversationId, content: 'x' }), /khoa so dang ky agy .* bi giu qua 3 s/);
  assert.equal(fs.readFileSync(lock, 'utf8'), 'pm-khac', 'khoa cua PM khac bi xoa');
  assert.equal(fake.calls().filter((c) => c.args.includes('--conversation')).length, 0);
});

test('khoa so dang ky MO COI (cu hon han): duoc lay lai va gui tin di tiep', async (t) => {
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'bdbdbdbd-2222-3333-4444-555555555555' });
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  await sleep(900);
  const lock = `${registryFile()}.lock`;
  fs.writeFileSync(lock, 'pm-da-chet');
  const old = new Date(Date.now() - 5 * 60000);
  fs.utimesSync(lock, old, old);
  t.after(() => fs.rmSync(lock, { force: true }));
  await sendMessage({ conversationId, content: 'sau khi lay lai khoa cu' });
  assert.equal(fake.calls().filter((c) => c.args.includes('--conversation')).length, 1);
});

// ---------------------------------------------------------------- vong 5: OpenCodeReview 14/10 con mo (workflow-improvements I.4)

test('killGroup (util.js): SIGKILL ca nhom tien trinh (con + chau), khong nem: loi duoc TRA VE cho noi goi', async (t) => {
  assert.equal(typeof util.killGroup, 'function', 'thieu util.killGroup');
  const leader = spawn('/bin/sh', ['-c', 'sleep 30 & sleep 30'], { detached: true, stdio: 'ignore' });
  t.after(() => { try { process.kill(-leader.pid, 'SIGKILL'); } catch { /* da chet */ } });
  await sleep(300);
  assert.equal(util.killGroup(leader.pid), null);
  await sleep(500);
  assert.throws(() => process.kill(-leader.pid, 0), /ESRCH/, 'nhom van con tien trinh song (sleep chau)');
  const orig = process.kill;
  process.kill = () => { throw Object.assign(new Error('kill ESRCH'), { code: 'ESRCH' }); };   // stub gia lap "nhom da het": pid 4242 duoi day chi di vao stub nay
  let got;
  try { got = util.killGroup(4242); } finally { process.kill = orig; }
  assert.equal(got?.code, 'ESRCH');
});

test('killGroup (util.js): pid 0, 1, am hoac khong phai so KHONG bao gio duoc gui tin hieu (kill(-0) = nhom cua chinh server, kill(-1) = moi tien trinh), loi duoc tra ve', () => {
  const orig = process.kill;
  const sent = [];
  process.kill = (pid, sig) => { sent.push([pid, sig]); throw Object.assign(new Error('kill ESRCH'), { code: 'ESRCH' }); };   // stub: khong tin hieu that nao roi di
  const got = {};
  try { for (const pid of [0, 1, -5, NaN, undefined, null, '0', '1']) got[String(pid)] = util.killGroup(pid); } finally { process.kill = orig; }
  assert.deepEqual(sent, [], `da gui tin hieu toi: ${JSON.stringify(sent)}`);
  for (const [pid, e] of Object.entries(got)) assert.ok(e instanceof Error, `killGroup(${pid}) khong tra ve loi`);
});

test('test gia lap "khong co agy" khong tro ANTIGRAVITY_PM_AGY vao duong dan doan duoc trong /tmp dung chung (file dat san o do se bi chay voi skip-permissions)', () => {
  const testsDir = path.dirname(new URL(import.meta.url).pathname);
  const hits = [];
  for (const f of fs.readdirSync(testsDir).filter((n) => n.endsWith('.js'))) {
    fs.readFileSync(path.join(testsDir, f), 'utf8').split('\n').forEach((line, i) => {
      if (/ANTIGRAVITY_PM_AGY\s*=\s*path\.join\(\s*os\.tmpdir\(\)/.test(line)) hits.push(`${f}:${i + 1}`);
    });
  }
  assert.deepEqual(hits, [], `duong dan agy doan duoc: ${hits.join(', ')} (dung NO_AGY trong helpers.js)`);
});

test('"SIGKILL ca nhom tien trinh" chi con o MOT cho (util.killGroup), khong chep lai trong src/', () => {
  const srcDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../src');
  const hits = [];
  for (const f of fs.readdirSync(srcDir).filter((n) => n.endsWith('.js'))) {
    fs.readFileSync(path.join(srcDir, f), 'utf8').split('\n').forEach((line, i) => { if (/process\.kill\(\s*-/.test(line)) hits.push(`${f}:${i + 1}`); });
  }
  assert.equal(hits.length, 1, `process.kill(-...) o ${hits.length} cho: ${hits.join(', ')}`);
  assert.match(hits[0], /^util\.js:/);
});

test('ping tu don: pid cua luot agy da thoat va bi tien trinh la dung lai thi KHONG giet nhom do (so dau van tay ps, khong chi kill -0)', async (t) => {
  // Hai luot ping chay xong (giu 400 ms de ghi duoc dau van tay that), roi pid cua chung "song lai" o kill -0 (gia lap pid bi dung lai).
  // Stub: kill(pid, 0) voi pid cua agy gia => "con song"; SIGKILL nhom toi cac pid do chi GHI LAI, khong bao gio gui that.
  const fake = fakeAgy(t, { FAKE_AGY_ID: 'cececece-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '400', ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  const dir = mkProject(t, { defaultModel: ARGON });
  const orig = process.kill;
  const groupKills = [];
  process.kill = function stub(pid, sig) {
    const agyPids = new Set(fake.calls().map((c) => c.pid));
    if (!agyPids.has(Math.abs(pid))) return orig.call(process, pid, sig);
    if (pid < 0) { groupKills.push(-pid); return true; }
    return true;   // kill -0: "pid van song" (da bi tien trinh khac dung lai)
  };
  let out;
  try { out = await call('pm_doctor', { project: dir, ping: true }); } finally { process.kill = orig; }
  assert.match(out.text, /Luot 2: xong/, out.text);
  assert.deepEqual(groupKills, [], `ping da SIGKILL nhom cua pid khong con la agy cua no: ${groupKills.join(', ')}\n${out.text}`);
});

/**
 * Hai PM cung thay MOT khoa cu. Gia lap PM A lay lai xong (xoa khoa cu, tao khoa moi cua A) dung giua luc PM nay (B) danh gia "cu" va
 * thao tac khong dao nguoc dau tien tren duong dan khoa (xoa / doi ten). B khong duoc xoa khoa cua A va vao doan gang cung luc.
 * linkError: fs.linkSync nem ma loi nay (he tep khong co hard link).
 */
async function pmBAfterPmATakesOver(t, id, linkError = null) {
  const fake = fakeAgy(t, { FAKE_AGY_ID: id });
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  await sleep(900);
  const lock = `${registryFile()}.lock`;
  fs.writeFileSync(lock, 'pm-da-chet');
  const old = new Date(Date.now() - 5 * 60000);
  fs.utimesSync(lock, old, old);
  t.after(() => fs.rmSync(lock, { force: true }));
  const orig = { rmSync: fs.rmSync, renameSync: fs.renameSync, linkSync: fs.linkSync };
  let injected = false;
  const pmATakesOver = (p) => {
    if (injected || p !== lock) return;
    injected = true;
    orig.rmSync.call(fs, lock, { force: true });
    fs.writeFileSync(lock, 'pm-A', { flag: 'wx' });
  };
  fs.rmSync = function rmSync(p, ...rest) { pmATakesOver(p); return orig.rmSync.call(fs, p, ...rest); };
  fs.renameSync = function renameSync(from, ...rest) { pmATakesOver(from); return orig.renameSync.call(fs, from, ...rest); };
  if (linkError) fs.linkSync = () => { throw Object.assign(new Error(`link ${linkError}`), { code: linkError }); };
  let res;
  try {
    res = await sendMessage({ conversationId, content: 'x' }).then(() => 'SENT', (e) => e.message);
  } finally {
    Object.assign(fs, orig);
  }
  assert.equal(injected, true, 'kich ban khong xay ra: PM nay khong dong vao khoa cu');
  assert.equal(fs.existsSync(lock) ? fs.readFileSync(lock, 'utf8') : '(khoa da bi xoa)', 'pm-A', 'khoa MOI cua PM A bi xoa / thay');
  assert.match(res, /khoa so dang ky agy .* bi giu qua 3 s/, `PM nay vao doan gang trong khi PM A dang giu khoa: ${res}`);
  assert.equal(fake.calls().filter((c) => c.args.includes('--conversation')).length, 0, 'sinh agy trong khi PM A dang giu khoa');
  assert.deepEqual(fs.readdirSync(homeStateDir()).filter((n) => n.endsWith('.stale')), [], 'con sot file khoa doi ten');
}

test('lay lai khoa cu: PM khac da lay lai TRUOC (khoa moi, tuoi) thi KHONG xoa khoa cua no, cho va bao "bi giu qua 3 s"', async (t) => {
  await pmBAfterPmATakesOver(t, 'cfcfcfcf-2222-3333-4444-555555555555');
});

test('lay lai khoa cu tren he tep KHONG co hard link (link EPERM): khoa tuoi cua PM khac van duoc tra lai (doi ten lai), khong bi xoa', async (t) => {
  await pmBAfterPmATakesOver(t, 'dbdbdbdb-2222-3333-4444-555555555555', 'EPERM');
});

test('su kien init cua agy in JSON co khoang trang ("event": "init"): van nhan ra, khong bao "khong in su kien init" (khong treo 60 s)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'd5d5d5d5-2222-3333-4444-555555555555', FAKE_AGY_SPACED_JSON: '1' });
  const r = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  assert.equal(r.conversationId, 'd5d5d5d5-2222-3333-4444-555555555555');
  assert.match(fs.readFileSync(r.parsed.out, 'utf8'), /"event": "init"/, 'agy gia khong in JSON co khoang trang: test khong kiem dieu no noi');
});

test('pm_doctor in trang thai agy (binary, so dang ky hong) CA KHI model mac dinh la bac IDE: task van chay agy qua model cua task / pm_dispatch', async (t) => {
  fakeAgy(t, { ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  process.env.ANTIGRAVITY_PM_AGY = NO_AGY;   // agy vang mat tren may
  fs.writeFileSync(registryFile(), '{"broken": ');
  const dir = mkProject(t, { defaultModel: 'flash' });
  const out = await call('pm_doctor', { project: dir });
  assert.match(out.text, /agy: KHONG TIM THAY/, out.text);
  assert.match(out.text, /SO DANG KY AGY HONG/, out.text);
});

test('task bac IDE (flash) ma hoi thoai la agy (dispatch chon Argon), ps hong + nudge: so dang ky doc duoc => LA agy, KHONG biet luot, bo qua nudge, KHONG reject ca tool', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'd6d6d6d6-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '3000' });
  const dir = mkProject(t, { defaultModel: 'flash' });
  const taskId = await newTask(dir);   // task.model = flash
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: dir });   // nhu pm_dispatch ... model=Argon (task.model khong doi)
  setConversation(dir, taskId, conversationId);
  process.env.ANTIGRAVITY_PM_PS = '/nonexistent/ps';
  const out = await call('pm_status', { project: dir, taskId, nudge: true });
  assert.match(out.text, /Luot agy: KHONG biet/, out.text);
  assert.match(out.text, /Khong nhac duoc agent/, out.text);
});

test('nhanh PLAN: hoi thoai phan bien la agy, ps hong + nudge: KHONG biet luot agy (noi MOT lan), bo qua nudge, KHONG reject ca tool', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'd8d8d8d8-2222-3333-4444-555555555555', FAKE_AGY_HOLD_MS: '3000' });
  const dir = mkProject(t, { defaultModel: ARGON });
  const taskId = await newTask(dir);   // phase PLAN, chua co hoi thoai lam viec
  await call('pm_plan', { project: dir, taskId, content: '# x\n1. lam\n2. test', files: ['src/a.js'] });
  await call('pm_dispatch', { project: dir, taskId, kind: 'plan_review' });
  process.env.ANTIGRAVITY_PM_PS = '/nonexistent/ps';
  const out = await call('pm_status', { project: dir, taskId, nudge: true });
  assert.match(out.text, /Khong nhac duoc hoi thoai phan bien: khong biet trang thai luot agy/, out.text);
  // ly do (ps hong) in MOT lan: dong trang thai plan-review.json da noi, nhanh nudge khong lap lai
  assert.equal((out.text.match(/khong doc duoc dau van tay/g) || []).length, 1, out.text);
});

test('don so dang ky: het ngan sach ps (3 muc co pid) van don tiep cac muc cu KHONG can ps (khong dung ca vong)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'd7d7d7d7-2222-3333-4444-555555555555' });
  // 5 muc cu nhat "dang chay" = chinh tien trinh test nay (song, dau van tay dung): khong sinh tien trinh nao
  const tag = execFileSync('/bin/ps', ['-o', 'lstart=', '-p', String(process.pid)], { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' } }).trim();
  const reg = {};
  for (let i = 0; i < 520; i++) reg[`c${i}`] = { model: ARGON, cwd: os.tmpdir(), at: new Date(2020, 0, 1, 0, 0, i).toISOString() };
  for (let i = 0; i < 5; i++) Object.assign(reg[`c${i}`], { pid: process.pid, pidTag: tag });
  fs.writeFileSync(registryFile(), JSON.stringify(reg));
  const r = await newConversation({ prompt: 'x', model: ARGON, cwd: mkProject(t) });
  const after = JSON.parse(fs.readFileSync(registryFile(), 'utf8'));
  assert.equal(Object.keys(after).length, 500, `${Object.keys(after).length} muc sau khi don (phai 500): muc cu khong pid bi giu lai`);
  for (let i = 0; i < 5; i++) assert.ok(after[`c${i}`], `muc dang chay c${i} bi don`);
  assert.ok(after[r.conversationId]);
});

test('so dang ky hong + nudge, task bac IDE ma phan bien ke hoach giao model=Argon: model THAT cua hoi thoai (ghi luc dispatch) quyet, bo qua nudge, KHONG reject', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'd9d9d9d9-2222-3333-4444-555555555555', ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  const dir = mkProject(t, { defaultModel: 'flash' });
  const taskId = await newTask(dir);   // task.model = flash
  await call('pm_plan', { project: dir, taskId, content: '# x\n1. lam\n2. test', files: ['src/a.js'] });
  await call('pm_dispatch', { project: dir, taskId, kind: 'plan_review', model: ARGON });   // hoi thoai phan bien la agy, task.model khong doi
  fs.writeFileSync(registryFile(), '{"broken": ');
  const out = await call('pm_status', { project: dir, taskId, nudge: true });
  assert.match(out.text, /Khong nhac duoc hoi thoai phan bien: khong biet trang thai luot agy/, out.text);
  assert.equal((out.text.match(/agy-conversations\.json hong/g) || []).length, 1, `so dang ky hong phai noi MOT lan:\n${out.text}`);
});

test('so dang ky hong + nudge, task bac IDE ma trien khai giao model=Argon: dispatch ghi model THAT cua hoi thoai, bo qua nudge, KHONG reject', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'dadadada-2222-3333-4444-555555555555', ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  const dir = mkProject(t, { defaultModel: 'flash' });
  const taskId = await newTask(dir);
  await call('pm_plan', { project: dir, taskId, content: '# x\n1. lam\n2. test', files: ['src/a.js'] });
  await call('pm_dispatch', { project: dir, taskId, kind: 'implement', force: true, model: ARGON });   // mo hoi thoai lam viec bang agy
  const cfg = loadConfig(dir);
  const opened = loadTask(cfg, taskId).dispatches.find((d) => d.kind === 'implement');
  assert.equal(opened.model, ARGON, 'dispatch implement mo hoi thoai bang Argon nhung ghi model khac');
  fs.writeFileSync(registryFile(), '{"broken": ');
  const out = await call('pm_status', { project: dir, taskId, nudge: true });
  assert.match(out.text, /Khong nhac duoc agent: khong biet trang thai luot agy/, out.text);
});

test('trien khai mo hoi thoai Argon nhung workspace lech (strict): task bi chan MA dispatch van ghi model THAT cua hoi thoai (khong roi ve task.model)', async (t) => {
  fakeAgy(t, { FAKE_AGY_ID: 'dbdbdbdb-2222-3333-4444-555555555555', FAKE_AGY_INIT_CWD: '/nowhere/else', ANTIGRAVITY_LS_ADDRESS: '127.0.0.1:9', ANTIGRAVITY_CSRF_TOKEN: 'x' });
  const dir = mkProject(t, { defaultModel: 'flash' });
  const taskId = await newTask(dir);
  await call('pm_plan', { project: dir, taskId, content: '# x\n1. lam\n2. test', files: ['src/a.js'] });
  await assert.rejects(call('pm_dispatch', { project: dir, taskId, kind: 'implement', force: true, model: ARGON }), /workspace/);
  const task = loadTask(loadConfig(dir), taskId);
  assert.equal(task.state, 'blocked');
  const opened = (task.dispatches || []).find((d) => d.kind === 'implement' && d.conversationId === task.conversationId);
  assert.equal(opened?.model, ARGON, `dispatch cua hoi thoai ${task.conversationId} khong ghi model that: ${JSON.stringify(task.dispatches)}`);
});
