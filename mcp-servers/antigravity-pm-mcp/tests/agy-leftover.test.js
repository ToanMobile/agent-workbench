// #697: lenh cua agent (agy dat ANTIGRAVITY_AGENT=1 cho moi lenh no chay) song sot sau khi luot agy da xong, mo coi (PPID 1), dot CPU.
// PM chi dung DUNG tien trinh: ANTIGRAVITY_AGENT=1 + the luot (ANTIGRAVITY_PM_RUN) cua mot luot DA XONG do chinh PM nay (hoac PM da chet) mo.
// Test duoi day doi: cung lenh ma thieu bien / mang the cua phien khac / thuoc luot con chay / luot cua PM khac con song / la daemon dung chung => con song.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import { newConversation, sendMessage, reapTurnLeftovers, startLeftoverReaper } from '../src/agentapi.js';
import { loadConfig } from '../src/config.js';
import { createTask, updateTask, loadTask } from '../src/tasks.js';
import { buildPlanCritiquePrompt, buildAuditPrompt } from '../src/prompt.js';
import { TOOLS_BY_NAME } from '../src/tools.js';
import { homeStateDir } from '../src/util.js';
import { tmpProject, tmpDir, cleanup, sampleTaskArgs } from './helpers.js';

const ARGON = 'gemini-4-argon-high';
const KID = 'setInterval(() => {}, 1000)';
// agy gia: sinh cac "lenh cua agent" tach nhom (FAKE_AGY_KIDS: [[ten, {bien: gia tri | null = xoa}, ...argv them]]), roi in init + result va thoat
// => cac lenh con lai thanh mo coi (PPID 1), dung nhu tien trinh `python3 -c 'while True: pass'` 30/10.
const FAKE = `#!/usr/bin/env node
const fs = require('node:fs');
const { spawn } = require('node:child_process');
const a = process.argv.slice(2);
const i = a.indexOf('--conversation');
const id = i >= 0 ? a[i + 1] : process.env.FAKE_AGY_ID;
for (const [name, over, ...extra] of JSON.parse(process.env.FAKE_AGY_KIDS || '[]')) {
  const env = { ...process.env };
  const argv0 = over.ARGV0;   // ten tien trinh hien trong ps (argv[0]), khong phai bien env
  delete over.ARGV0;
  for (const [k, v] of Object.entries(over)) { if (v === null) delete env[k]; else env[k] = v; }
  const args = extra.map((x) => x.replace('$RUN', process.env.ANTIGRAVITY_PM_RUN || ''));   // $RUN = the luot PM dat cho agy
  const c = spawn(process.execPath, ['-e', ${JSON.stringify(KID)}, ...args], { detached: true, stdio: 'ignore', env, ...(argv0 ? { argv0 } : {}) });
  c.unref();
  fs.appendFileSync(process.env.FAKE_AGY_KIDS_FILE, name + ' ' + c.pid + '\\n');
}
console.log(JSON.stringify({ event: 'init', conversation_id: id, init: { cwd: process.cwd() } }));
console.log(JSON.stringify({ event: 'result', result: { conversation_id: id, status: 'SUCCESS' } }));
`;
const KEYS = ['ANTIGRAVITY_PM_AGY', 'ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS', 'FAKE_AGY_ID', 'FAKE_AGY_KIDS', 'FAKE_AGY_KIDS_FILE'];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const registryFile = () => path.join(homeStateDir(), 'agy-conversations.json');
const ps = (args) => execFileSync('/bin/ps', args, { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' } }).trim();
const tagOf = (pid) => { try { return ps(['-o', 'lstart=', '-p', String(pid)]) || null; } catch { return null; } };
const ppidOf = (pid) => { try { return Number(ps(['-o', 'ppid=', '-p', String(pid)])); } catch { return null; } };

/** Dung pid khi no con DUNG la tien trinh da ghi (dau van tay ps): don cua test khong bao gio trung tien trinh la dung lai pid. */
function killIfSame(pid, tag) {
  if (tag && tagOf(pid) === tag) { try { process.kill(pid, 'SIGKILL'); } catch { /* vua thoat */ } }
}

async function until(fn, ms, what) {
  const t0 = Date.now();
  while (!fn()) {
    if (Date.now() - t0 > ms) throw new Error(`het ${ms} ms ma chua: ${what}`);
    await sleep(50);
  }
}

/** Tien trinh "dung" cho test (agy gia / PM khac): con cua test, test tu don. */
function holder(t) {
  const c = spawn(process.execPath, ['-e', KID], { stdio: 'ignore' });
  t.after(() => c.kill('SIGKILL'));
  return { pid: c.pid, tag: null };
}

function setup(t, id, kids) {
  const dir = tmpDir('agpm-697-');
  const bin = path.join(dir, 'agy');
  fs.writeFileSync(bin, FAKE, { mode: 0o755 });
  const kidsFile = path.join(dir, 'kids.txt');
  const prev = { ...process.env };
  Object.assign(process.env, {
    ANTIGRAVITY_PM_AGY: bin, ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS: '1', FAKE_AGY_ID: id, FAKE_AGY_KIDS: JSON.stringify(kids), FAKE_AGY_KIDS_FILE: kidsFile,
  });
  const recorded = new Map();   // ten -> { pid, tag }
  t.after(() => {
    for (const k of KEYS) { if (prev[k] === undefined) delete process.env[k]; else process.env[k] = prev[k]; }
    for (const { pid, tag } of recorded.values()) killIfSame(pid, tag);
    fs.rmSync(registryFile(), { force: true });
    cleanup(dir);
  });
  const project = tmpProject({ defaultModel: ARGON });
  t.after(() => cleanup(project));
  /** Cho agy gia thoat va moi lenh con thanh mo coi (PPID 1); ghi dau van tay de don an toan. */
  const orphans = async () => {
    await until(() => fs.existsSync(kidsFile) && fs.readFileSync(kidsFile, 'utf8').trim().split('\n').length === kids.length, 10000, 'agy gia sinh du lenh con');
    for (const line of fs.readFileSync(kidsFile, 'utf8').trim().split('\n')) {
      const [name, pid] = line.split(' ');
      recorded.set(name, { pid: Number(pid), tag: tagOf(Number(pid)) });
    }
    await until(() => [...recorded.values()].every(({ pid }) => ppidOf(pid) === 1), 10000, 'lenh con thanh mo coi (PPID 1)');
    return recorded;
  };
  return { project, orphans };
}

const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };

test('#697 pm_status: lenh mo coi cua agent (ANTIGRAVITY_AGENT=1, luot agy da xong cua chinh PM) bi liet ke + dung DUNG pid; cung lenh khac dieu kien thi KHONG dung', async (t) => {
  const id = '69769769-2222-3333-4444-555555555555';
  const tokOther = `phien-khac-${process.pid}`;
  const tokBusy = `luot-dang-chay-${process.pid}`;
  const tokOtherPm = `pm-khac-con-song-${process.pid}`;
  const tokDeadPm = `pm-da-chet-${process.pid}`;
  const { project, orphans } = setup(t, id, [
    ['G', { ANTIGRAVITY_AGENT: '1', ANTIGRAVITY_PM_RUN: tokDeadPm }],     // dung: luot da xong cua PM DA CHET (khong ai khac don)
    // dung: dung hinh su co 30/10 — python3 Homebrew hien la .../Python.app/Contents/MacOS/Python (khong phai app GUI)
    ['P', { ANTIGRAVITY_AGENT: '1', ARGV0: '/opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/Resources/Python.app/Contents/MacOS/Python' }],
    ['U', { ANTIGRAVITY_AGENT: '1', ARGV0: '/Applications/Unity/Hub/Editor/6000.0.1f1/Unity.app/Contents/MacOS/Unity' }],   // app GUI dung chung
    ['A', { ANTIGRAVITY_AGENT: '1' }],                                    // dung: lenh cua agent, luot cua PM nay da xong
    ['B', { ANTIGRAVITY_AGENT: null }],                                   // cung lenh, khong co bien cua agent
    ['C', { ANTIGRAVITY_AGENT: '1', ANTIGRAVITY_PM_RUN: tokOther }],      // the luot cua phien khac (khong co trong so dang ky)
    ['D', { ANTIGRAVITY_AGENT: '1', ANTIGRAVITY_PM_RUN: tokBusy }],       // luot con chay (agy con song)
    ['E', { ANTIGRAVITY_AGENT: '1', ANTIGRAVITY_PM_RUN: tokOtherPm }],    // luot da xong cua PM KHAC con song: PM do tu don
    // daemon dung chung (build cua phien khac co the dang noi vao): java ... GradleDaemon
    ['F', { ANTIGRAVITY_AGENT: '1', ARGV0: '/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home/bin/java' }, 'org.gradle.launcher.daemon.bootstrap.GradleDaemon'],
    ['Q', { ANTIGRAVITY_AGENT: '1' }, 'GradleDaemon'],                    // dung: chi la tham so, khong phai daemon java
    // argv TRICH chuoi bien (vd prompt cua agy) nhung env khong co => giu (ps -E noi argv + env bang dau cach)
    ['X', { ANTIGRAVITY_AGENT: null, ANTIGRAVITY_PM_RUN: null }, 'ANTIGRAVITY_AGENT=1', 'ANTIGRAVITY_PM_RUN=$RUN'],
  ]);
  const cfg = loadConfig(project);
  const task = createTask(cfg, sampleTaskArgs());
  const { conversationId } = await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  updateTask(cfg, loadTask(cfg, task.id), (tk) => { tk.conversationId = conversationId; });
  const kids = await orphans();

  const agyAlive = holder(t);   // dong vai agy cua luot D (con chay)
  const otherPm = holder(t);    // dong vai PM khac con song (chu luot E)
  const reg = JSON.parse(fs.readFileSync(registryFile(), 'utf8'));
  const out = (tok) => path.join(project, `${tok}.jsonl`);
  reg['d0d0d0d0-2222-3333-4444-555555555555'] = { model: ARGON, cwd: project, out: out(tokBusy), pid: agyAlive.pid, pidTag: tagOf(agyAlive.pid), ownerPid: process.pid, ownerTag: tagOf(process.pid) };
  reg['e0e0e0e0-2222-3333-4444-555555555555'] = { model: ARGON, cwd: project, out: out(tokOtherPm), pid: kids.get('B').pid, pidTag: 'Thu Jan  1 00:00:00 2020', ownerPid: otherPm.pid, ownerTag: tagOf(otherPm.pid) };
  // chu la pid cua test nhung dau van tay khac = PM da chet, pid bi dung lai
  reg['70707070-2222-3333-4444-555555555555'] = { model: ARGON, cwd: project, out: out(tokDeadPm), pid: kids.get('B').pid, pidTag: 'Thu Jan  1 00:00:00 2020', ownerPid: process.pid, ownerTag: 'Thu Jan  1 00:00:00 2020' };
  fs.writeFileSync(registryFile(), JSON.stringify(reg));
  // H: the luot da xong cua chinh PM nay nhung KHONG mo coi (cha con song: PPID = test) => giu
  const myRun = path.basename(reg[conversationId].out, '.jsonl');
  const h = spawn(process.execPath, ['-e', KID], { stdio: 'ignore', env: { ...process.env, ANTIGRAVITY_AGENT: '1', ANTIGRAVITY_PM_RUN: myRun } });
  t.after(() => h.kill('SIGKILL'));
  kids.set('H', { pid: h.pid, tag: tagOf(h.pid) });

  const res = await TOOLS_BY_NAME.get('pm_status').handler({ project, taskId: task.id });
  const text = typeof res === 'string' ? res : res.text;
  for (const name of ['A', 'G', 'P', 'Q']) {
    const { pid } = kids.get(name);
    await until(() => !alive(pid), 3000, `lenh mo coi ${name} (pid ${pid}) bi dung`).catch((e) => assert.fail(`${e.message}\n${text}`));
    assert.match(text, new RegExp(`pid ${pid}\\b`), `pm_status phai liet ke pid bi dung (${name})\n${text}`);
  }
  assert.ok(!text.includes('setInterval'), `chi in ten file thuc thi, khong in argv (co the chua token)\n${text}`);
  for (const name of ['B', 'C', 'D', 'E', 'F', 'H', 'U', 'X']) {
    const { pid } = kids.get(name);
    assert.ok(alive(pid), `${name} (pid ${pid}) KHONG duoc bi dung`);
    assert.ok(!new RegExp(`pid ${pid}\\b`).test(text), `${name} (pid ${pid}) khong duoc bi liet ke la da dung\n${text}`);
  }
});

test('#697 gui tin luot moi: lenh mo coi cua luot TRUOC bi dung truoc khi so dang ky ghi de luot do', async (t) => {
  const id = '69769769-3333-3333-4444-555555555555';
  const { project, orphans } = setup(t, id, [['A', { ANTIGRAVITY_AGENT: '1' }]]);
  await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  const kids = await orphans();
  process.env.FAKE_AGY_KIDS = '[]';   // luot 2 khong sinh gi them
  await sendMessage({ conversationId: id, content: 'tiep' });
  const A = kids.get('A').pid;
  await until(() => !alive(A), 3000, `lenh mo coi cua luot 1 (pid ${A}) bi dung khi mo luot 2`);
});

test('#697 don dinh ky cua server: luot xong ma PM KHONG goi tool nao nua (su co 30/10) => lenh mo coi van bi dung', async (t) => {
  const id = '69769769-4444-3333-4444-555555555555';
  const { project, orphans } = setup(t, id, [['A', { ANTIGRAVITY_AGENT: '1' }]]);
  await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  const kids = await orphans();
  const timer = startLeftoverReaper(100);
  t.after(() => clearInterval(timer));
  const A = kids.get('A').pid;
  await until(() => !alive(A), 5000, `bo don dinh ky dung lenh mo coi (pid ${A})`);
});

test('#697 pid bi dung lai giua lan quet va luc giet (lstart khac) => KHONG dung', async (t) => {
  const id = '69769769-5555-3333-4444-555555555555';
  const { project, orphans } = setup(t, id, [['A', { ANTIGRAVITY_AGENT: '1' }]]);
  await newConversation({ prompt: 'x', model: ARGON, cwd: project });
  const kids = await orphans();
  // ps gia: lan hoi rieng tung pid ngay truoc khi giet (-ww -o lstart=,command= -p) tra nam khac => nhu tien trinh la vua nhan lai pid
  const dir = tmpDir('agpm-697-ps-');
  t.after(() => cleanup(dir));
  const wrapper = path.join(dir, 'ps-relstart.sh');
  fs.writeFileSync(wrapper, '#!/bin/sh\nif [ "$1" = "-ww" ]; then /bin/ps "$@" | sed -E \'s/ [0-9]{4} / 1999 /\'; exit 0; fi\nexec /bin/ps "$@"\n', { mode: 0o755 });
  const prev = process.env.ANTIGRAVITY_PM_PS;
  process.env.ANTIGRAVITY_PM_PS = wrapper;
  t.after(() => { if (prev === undefined) delete process.env.ANTIGRAVITY_PM_PS; else process.env.ANTIGRAVITY_PM_PS = prev; });
  const done = reapTurnLeftovers();
  const A = kids.get('A').pid;
  assert.deepEqual(done, [], 'lstart doi thi khong duoc dung');
  assert.ok(alive(A), `pid ${A} (lstart khac luc quet) KHONG duoc bi dung`);
});

test('#697 prompt phan bien ke hoach va audit (chi doc) CAM lenh nang / chay vo han / dot CPU', (t) => {
  const dir = tmpProject({});
  t.after(() => cleanup(dir));
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  for (const [name, p] of [['plan_review', buildPlanCritiquePrompt(cfg, task)], ['audit', buildAuditPrompt(cfg, task)]]) {
    assert.match(p, /CAM chay lenh nang/, `${name}: thieu dong cam lenh nang`);
    assert.match(p, /vo han/, `${name}: thieu dong cam lenh chay vo han`);
    assert.match(p, /dot CPU/, `${name}: thieu dong cam lenh dot CPU`);
  }
});
