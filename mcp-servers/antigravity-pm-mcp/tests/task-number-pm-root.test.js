// #742 OCR b266f3d4 (tasks.js:106): nextTaskNumber() scans cfg.pmTasksRoot (HOME), but the number lock only created
// tasksRoot/<id> (in the repo). pmTasksRoot/<id> appeared later in save(), after the lock was released, so a second
// createTask in that window read the same max and got the same Txxxx. The PM-side folder must exist before the lock is let go.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { loadConfig } from '../src/config.js';
import { createTask } from '../src/tasks.js';
import { tmpProject, cleanup } from './helpers.js';

test('createTask: the PM-side task folder exists when the number lock is released', () => {
  const dir = tmpProject({});
  const cfg = loadConfig(dir);
  assert.notEqual(cfg.pmTasksRoot, cfg.tasksRoot, 'the test needs a PM task root outside the repo');
  const lock = `${cfg.pmTasksRoot}.lock`;
  const realRm = fs.rmSync;
  const seen = [];
  fs.rmSync = (p, ...rest) => {
    if (p === lock) seen.push(fs.existsSync(cfg.pmTasksRoot) ? fs.readdirSync(cfg.pmTasksRoot) : []);
    return realRm(p, ...rest);
  };
  try {
    const t = createTask(cfg, { title: 'x', brief: 'y', definitionOfDone: ['z'] });
    assert.equal(seen.length, 1, 'the number lock is taken and released once');
    assert.ok(seen[0].includes(t.id), `pmTasksRoot at lock release: ${JSON.stringify(seen[0])} (missing ${t.id})`);
    const t2 = createTask(cfg, { title: 'x', brief: 'y', definitionOfDone: ['z'] });
    assert.notEqual(t2.id.slice(0, 5), t.id.slice(0, 5), 'next task gets the next number');
  } finally {
    fs.rmSync = realRm;
    cleanup(dir);
  }
});
