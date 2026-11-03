// #865 (tách từ #742): hai ca hồi quy cc-switcher, để ở file riêng thay vì sửa audit-fixes.test.js có sẵn.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createLogTailReader, detectRateLimitInLogChunk } from '../src/daemon.js';
import { switchProfile } from '../src/profiles.js';

function createTempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-audit-'));
  fs.writeFileSync(
    path.join(dir, 'settings.json'),
    JSON.stringify({ currentProviderClaude: 'finos_toan' }, null, 2),
  );
  return {
    dir,
    cleanup() {
      fs.rmSync(dir, { recursive: true, force: true });
    },
  };
}

// critical scan 31/10 — BUG-REV-ccs-carryover-refire
test('createLogTailReader: after a 429 match the carried tail is dropped (no second rotation from the same line)', () => {
  const tmp = createTempDir();
  try {
    const logFile = path.join(tmp.dir, 'claude.log');
    fs.writeFileSync(logFile, '');
    const reader = createLogTailReader(logFile);
    fs.appendFileSync(logFile, 'error 429 Too Many Requests rate_limit_error\n');
    const first = reader.readNewChunk();
    assert.equal(detectRateLimitInLogChunk(first), true);
    reader.resetCarryOver();
    fs.appendFileSync(logFile, 'ok normal line\n');
    assert.equal(detectRateLimitInLogChunk(reader.readNewChunk()), false);
  } finally {
    tmp.cleanup();
  }
});

// critical scan 31/10 — BUG-REV-ccs-settings-wipe
test('switchProfile: an unparsable CC Switch settings.json is left alone, never overwritten with {}', () => {
  const tmp = createTempDir();
  try {
    const f = path.join(tmp.dir, 'settings.json');
    fs.writeFileSync(f, '{ "currentProviderClaude": "finos_toan", "keep": 1, ');   // truncated JSON
    switchProfile({ stateDir: tmp.dir, target: 'finos_linh', nowMs: Date.now(), enforceCooldown: false });
    assert.equal(fs.readFileSync(f, 'utf8'), '{ "currentProviderClaude": "finos_toan", "keep": 1, ');
  } finally {
    tmp.cleanup();
  }
});
