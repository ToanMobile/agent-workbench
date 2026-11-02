// quet critical 31/10 — BUG-REV-agpm-task-lock: withFileLock xoa khoa khong con la cua minh, hai tien trinh co the cung xoa
// mot khoa cu; createTask cap so task ngoai moi khoa.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { withFileLock } from '../src/tasks.js';
import { tmpDir, cleanup } from './helpers.js';

test('withFileLock: a lock taken over by someone else is not removed on release', () => {
  const dir = tmpDir('agpm-lock-');
  try {
    const lock = path.join(dir, 'x.lock');
    withFileLock(lock, () => { fs.writeFileSync(lock, 'other-owner'); });
    assert.equal(fs.readFileSync(lock, 'utf8'), 'other-owner');
  } finally { cleanup(dir); }
});

test('withFileLock: own lock removed; a stale lock (> 30 s) is taken over, a fresh one is not', () => {
  const dir = tmpDir('agpm-lock-');
  try {
    const lock = path.join(dir, 'y.lock');
    assert.equal(withFileLock(lock, () => 7), 7);
    assert.equal(fs.existsSync(lock), false);
    fs.writeFileSync(lock, 'dead');
    const old = new Date(Date.now() - 60000);
    fs.utimesSync(lock, old, old);
    assert.equal(withFileLock(lock, () => 'ok'), 'ok');
    assert.equal(fs.existsSync(lock), false);
    assert.deepEqual(fs.readdirSync(dir).filter((n) => n.includes('.stale')), []);
  } finally { cleanup(dir); }
});
