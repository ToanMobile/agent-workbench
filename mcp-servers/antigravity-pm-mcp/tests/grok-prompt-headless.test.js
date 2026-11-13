// 13/11/2026 (PR #1163, chu repo bo Grok): prompt audit grok headless (GH1, 04/11) da go cung duong grok. Hop dong thay the con song la
// prompt AUDIT doc lap cua Antigravity (buildAuditPrompt): vai chi doc (lenh ngan tu ket thuc, khong chay vo han — #697), KHONG sua code,
// va khong con nhac toi grok (khong con reviewer grok nao doc prompt nay).
import test from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../src/config.js';
import { createTask } from '../src/tasks.js';
import { buildAuditPrompt } from '../src/prompt.js';
import { tmpProject, cleanup, sampleTaskArgs } from './helpers.js';

test('GH1 prompt audit Antigravity: vai chi doc, KHONG sua code, khong nhac grok; co pham vi thi neu base..head', () => {
  const dir = tmpProject({ projectName: 'audit-prompt', testCommand: 'echo ok' });
  try {
    const cfg = loadConfig(dir);
    const task = createTask(cfg, sampleTaskArgs());
    for (const range of [null, { base: 'a'.repeat(40), head: 'b'.repeat(40), edited: ['tests/t.sh'] }]) {
      const p = buildAuditPrompt(cfg, task, '', range);
      assert.match(p, /Vai chi doc/, 'thieu luat vai chi doc (#697)');
      assert.match(p, /KHONG sua code/, 'thieu cam sua code');
      assert.doesNotMatch(p, /grok/i, 'prompt audit con nhac grok');
      if (range) assert.ok(p.includes(`${range.base}..${range.head}`), 'co pham vi ma prompt khong neu base..head');
    }
  } finally {
    cleanup(dir);
  }
});
