#!/usr/bin/env node
// pm-review-audit.js — Antigravity's vote in the 4-way review (universal-agent-devkit/bin/review-fanout.sh).
// Same path as the MCP tools (pm_task_create -> pm_dispatch kind=audit), from a shell, then waits for audit-agent.json.
//
//   node bin/pm-review-audit.js --project ROOT --base REF --out FILE [--message-file F] [--timeout SEC] [--model M] [--scope diff|full]
//
// Always writes an envelope to --out: {reviewer:"antigravity", status: ok|failed|timeout|error|unavailable, verdict, findings,
// reason}. status ok only when Antigravity wrote audit-agent.json for THIS head (auditedHead == git HEAD) after the dispatch.
// Exit 0 when the envelope says ok (whatever the verdict), 1 otherwise. Nothing here ever turns a missing audit into a pass.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
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
const scope = arg('--scope', 'diff');   // diff | full (whole-solution audit of the files named in the message)

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

const sleep = (ms) => new Promise((res) => { setTimeout(res, ms); });

async function main() {
  if (!out) { process.stderr.write('pm-review-audit: --out FILE is required\n'); process.exit(2); }
  let head;
  try {
    head = execFileSync('git', ['-C', project, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  } catch (e) {
    write({ status: 'error', reason: `git rev-parse HEAD failed: ${e.message}` });
  }
  const message = msgFile ? fs.readFileSync(msgFile, 'utf8') : '';
  let created;
  try {
    created = await call('pm_task_create', {
      project,
      title: scope === 'full' ? `[4-way full audit] ${head.slice(0, 12)}` : `[4-way review] ${head.slice(0, 12)} vs ${base}`,
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
        try { rep = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { await sleep(3000); continue; }   // half-written
        if (rep.auditedHead && rep.auditedHead !== head) {
          write({ status: 'error', reason: `audited ${rep.auditedHead} but HEAD is ${head} (stale audit)`, task_id: taskId });
        }
        const verdict = rep.verdict === 'pass' ? 'pass' : 'fail';
        write({ status: 'ok', verdict, findings: Array.isArray(rep.findings) ? rep.findings : [], task_id: taskId,
          audit_file: file, reason: rep.notes || '' });
      }
    } catch { /* not written yet */ }
    await sleep(5000);
  }
  write({ status: 'timeout', reason: `no audit-agent.json from Antigravity within ${timeoutS}s (task ${taskId})`, task_id: taskId });
}

main().catch((e) => write({ status: 'error', reason: `pm-review-audit crashed: ${e?.stack || e}` }));
