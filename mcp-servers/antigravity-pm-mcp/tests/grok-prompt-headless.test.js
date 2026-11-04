// 04/11: audit grok THAT tren PR #977 (diff 23 file) dung giua chung, khong co dong VERDICT: grok o plan mode headless dinh ghi diff ra
// file, lenh can xin quyen ma phien headless khong hoi duoc ("permission required ... headless run cannot ask for approval"). Prompt grok
// phai cam lenh can quyen (ghi file, redirect, tee, mktemp), chi doc truc tiep, va LUON ket thuc bang dong VERDICT (chua doc het ->
// VERDICT: REVISE, an toan ve phia bi quan).
import test from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../src/config.js';
import { createTask } from '../src/tasks.js';
import { buildGrokAuditPrompt } from '../src/prompt.js';
import { tmpProject, cleanup, sampleTaskArgs } from './helpers.js';

test('GH1 prompt grok (doc lap va thuong): cam lenh can xin quyen trong headless, bat buoc dong VERDICT ke ca khi chua doc het', () => {
  const dir = tmpProject({ projectName: 'grok-headless', testCommand: 'echo ok' });
  try {
    const cfg = loadConfig(dir);
    const task = createTask(cfg, sampleTaskArgs());
    const head = 'a'.repeat(40);
    for (const independent of [true, false]) {
      const p = buildGrokAuditPrompt(cfg, task, { head, range: { base: 'b'.repeat(40), trunk: 'refs/heads/main', edited: ['tests/x.sh'] }, independent });
      assert.match(p, /headless/i, `independent=${independent}`);
      assert.match(p, /redirect|`>`/, `independent=${independent}`);
      assert.match(p, /git diff b{40} a{40} -- <file>/, `independent=${independent}`);
      assert.match(p, /chua doc het.*VERDICT: REVISE/s, `independent=${independent}`);
    }
  } finally {
    cleanup(dir);
  }
});
