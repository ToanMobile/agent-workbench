#!/usr/bin/env node
// pm-review-audit.js — Antigravity's vote in the 4-way review (universal-agent-devkit/bin/review-fanout.sh).
// Same path as the MCP tools (pm_task_create -> pm_dispatch kind=audit), from a shell, then waits for audit-agent.json.
//
//   node bin/pm-review-audit.js --project ROOT --base REF --out FILE [--message-file F] [--timeout SEC] [--model M] [--scope diff|full] [--label TEXT]
//
// Always writes an envelope to --out: {reviewer:"antigravity", status: ok|failed|timeout|error|unavailable, verdict, findings,
// reason}. status ok only when Antigravity wrote audit-agent.json for THIS head (auditedHead == git HEAD) after the dispatch.
// Exit 0 when the envelope says ok (whatever the verdict), 1 otherwise. Nothing here ever turns a missing audit into a pass.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { TOOLS_BY_NAME } from '../src/tools.js';

function arg(name, dflt = '') {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : dflt;
}
const project = path.resolve(arg('--project', process.cwd()));
const base = arg('--base', 'HEAD');
const out = arg('--out');
const timeoutS = Number(arg('--timeout', '1200')) || 1200;
const model = arg('--model');
const msgFile = arg('--message-file');
const scope = arg('--scope', 'diff');
const label = arg('--label');   // unique per parallel audit (a full scan runs one per chunk): the task id derives from the title   // diff | full (whole-solution audit of the files named in the message)

function write(env) {
  const full = { reviewer: 'antigravity', usage: { tokens: 0, usd: 0 }, findings: [], ...env };
  if (out) fs.writeFileSync(out, `${JSON.stringify(full, null, 1)}\n`);
  else process.stdout.write(`${JSON.stringify(full, null, 1)}\n`);
  process.exit(full.status === 'ok' ? 0 : 1);
}

async function call(name, args) {
  const tool = TOOLS_BY_NAME.get(name);
  if (!tool) throw new Error(`antigravity-pm has no tool ${name}`);
  const r = await tool.handler(args);
  return typeof r === 'string' ? r : (r?.text ?? '');
}

// The working tree the audit is about: HEAD + uncommitted diff + untracked files (names and bytes). An audit is only valid for
// the head AND tree it started on (critical scan / audit 31/10: a missing auditedHead passed; edits during the audit passed).
// HEAD is in the hash (#756): a commit during the audit leaves both trees clean, so the diff alone hashed the same. The PM's own
// untracked task files (.antigravity-pm/, written by pm_task_create/pm_dispatch after tree0) are left out: in a repo that does
// not gitignore it they made every audit 'worktree hash differs'.
// ponytail: only the default stateDir is left out (a project-set stateDir could name "src"); a custom, un-ignored stateDir
// still fails closed as 'differs' — read it from the config only if such a project shows up.
const PM_STATE_DIR = '.antigravity-pm/';
export function treeHash(root) {
  const h = createHash('sha256');
  const git = (...a) => execFileSync('git', ['-C', root, ...a], { maxBuffer: 256 * 1024 * 1024 });
  h.update(git('rev-parse', 'HEAD'));
  h.update(git('diff', '--no-ext-diff', '--binary', 'HEAD'));
  for (const f of git('ls-files', '-z', '--others', '--exclude-standard').toString('utf8').split('\0')
    .filter((p) => p && !p.startsWith(PM_STATE_DIR)).sort()) {
    h.update(`\0${f}\0`);
    try {
      const st = fs.lstatSync(path.join(root, f));
      if (st.isFile()) h.update(fs.readFileSync(path.join(root, f)));
      else if (st.isSymbolicLink()) h.update(fs.readlinkSync(path.join(root, f)));
    } catch { h.update('<gone>'); }
  }
  return h.digest('hex');
}

/** The envelope for one audit-agent.json: ok only for THIS head and an unchanged working tree (fail closed otherwise). */
export function judgeAudit(rep, { head, tree0, tree1, model = '' }) {
  if (!rep?.auditedHead || rep.auditedHead !== head) {   // no auditedHead is no proof of what was audited
    return { status: 'error', reason: rep?.auditedHead ? `audited ${rep.auditedHead} but HEAD is ${head} (stale audit)`
      : 'audit-agent.json has no auditedHead (cannot tell which code was audited)' };
  }
  if (!tree0 || tree1 !== tree0) return { status: 'error', reason: 'HEAD or the working tree changed during the audit (worktree hash differs)' };
  return { status: 'ok', verdict: rep.verdict === 'pass' ? 'pass' : 'fail', findings: Array.isArray(rep.findings) ? rep.findings : [],
    reason: rep.notes || '', audited_head: head, worktree_hash: tree0, model: String(model || rep.model || '') };   // the model PM dispatched to; the agent's own claim only without one
}

const sleep = (ms) => new Promise((res) => { setTimeout(res, ms); });
// result poll (speed 31/10): was a flat 5 s (2.5 s lost per audit on average); a stat() is cheap, so 0.5 s for the first
// two minutes, then 1 s. PM_AUDIT_POLL_MS overrides (tests).
export const pollDelay = (elapsedMs) => {
  const fixed = Number(process.env.PM_AUDIT_POLL_MS);
  if (Number.isFinite(fixed) && fixed > 0) return fixed;
  return elapsedMs < 120000 ? 500 : 1000;
};

async function main() {
  if (!out) { process.stderr.write('pm-review-audit: --out FILE is required\n'); process.exit(2); }
  let head;
  try {
    head = execFileSync('git', ['-C', project, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  } catch (e) {
    write({ status: 'error', reason: `git rev-parse HEAD failed: ${e.message}` });
  }
  let tree0;
  try { tree0 = treeHash(project); } catch (e) { write({ status: 'error', reason: `working-tree hash failed: ${e.message}` }); }
  const message = msgFile ? fs.readFileSync(msgFile, 'utf8') : '';
  let created;
  try {
    created = await call('pm_task_create', {
      project,
      title: (scope === 'full' ? `[4-way full audit] ${head.slice(0, 12)}` : `[4-way review] ${head.slice(0, 12)} vs ${base}`)
        + (label ? ` ${label}` : ''),
      brief: (scope === 'full'
        ? 'CHI DOC, KHONG SUA. Audit TOAN BO cac file liet ke trong message (khong phai diff), doc tron ven tung file. '
        : `CHI DOC, KHONG SUA. Audit doc lap cho thay doi: \`git diff ${base}\` (commit tu ${base} + thay doi chua commit + file moi chua track). `)
        + 'Day la 1 trong 4 reviewer (Claude Opus, Antigravity, Grok, OCR); PASS chi khi ca 4 cung pass.',
      definitionOfDone: [scope === 'full' ? 'Bao cao moi loi blocker/major trong cac file duoc liet ke'
        : `Khong con loi blocker/major trong thay doi so voi ${base}`],
      type: 'refactor',
      proofKind: 'script',
      ...(model && { model }),
    });
  } catch (e) {
    write({ status: 'unavailable', reason: `pm_task_create failed: ${e.message}${e.hint ? ` (${e.hint})` : ''}` });
  }
  const taskId = (created.match(/\b(T\d{3,}[A-Za-z0-9-]*)\b/) || [])[1];
  if (!taskId) write({ status: 'error', reason: `no task id in pm_task_create output: ${created.slice(0, 300)}` });
  const t0 = Date.now();
  let dispatched;
  try {
    dispatched = await call('pm_dispatch', { project, taskId, kind: 'audit', message, force: true, ...(model && { model }) });
  } catch (e) {
    write({ status: 'unavailable', reason: `pm_dispatch kind=audit failed: ${e.message}${e.hint ? ` (${e.hint})` : ''}` });
  }
  const file = (dispatched.match(/Ket qua se nam o: (.+audit-agent\.json)/) || [])[1];
  if (!file) write({ status: 'error', reason: `audit result path not in pm_dispatch output: ${dispatched.slice(0, 300)}` });
  const deadline = t0 + timeoutS * 1000;
  while (Date.now() < deadline) {
    try {
      const st = fs.statSync(file);
      if (st.mtimeMs >= t0) {
        let rep;
        try { rep = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { await sleep(250); continue; }   // half-written
        let tree1 = '';
        try { tree1 = treeHash(project); } catch { /* '' never equals tree0 */ }
        write({ ...judgeAudit(rep, { head, tree0, tree1, model }), task_id: taskId, audit_file: file });
      }
    } catch { /* not written yet */ }
    await sleep(pollDelay(Date.now() - t0));
  }
  write({ status: 'timeout', reason: `no audit-agent.json from Antigravity within ${timeoutS}s (task ${taskId})`, task_id: taskId });
}

const isMain = () => { try { return fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url)); } catch { return false; } };
if (isMain()) main().catch((e) => write({ status: 'error', reason: `pm-review-audit crashed: ${e?.stack || e}` }));
