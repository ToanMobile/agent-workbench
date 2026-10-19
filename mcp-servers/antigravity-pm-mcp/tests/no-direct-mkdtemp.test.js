import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Test KHONG duoc goi thang mkdtemp/mkdtempSync: thu muc tam phai di qua tmpDir() cua tests/helpers.js (tu xoa khi tien trinh thoat,
// ke ca khi test hong giua chung hay bi SIGTERM). Goi thang lam ro thu muc tam (19/10/2026: hon 700 thu muc agpm-* sot lai, day dia).
// Chi helpers.js (noi tmpDir() duoc dinh nghia) va chinh file nay duoc nhac toi ten ham.
const TESTS_DIR = path.dirname(fileURLToPath(import.meta.url));
const SELF = path.basename(fileURLToPath(import.meta.url));
const DIRECT_CALL = /\bmkdtemp(?:Sync)?\b/;

test('khong *.test.js nao goi thang mkdtemp/mkdtempSync (dung tmpDir() cua helpers.js)', () => {
  const offenders = [];
  for (const name of fs.readdirSync(TESTS_DIR).filter((f) => f.endsWith('.test.js') && f !== SELF).sort()) {
    fs.readFileSync(path.join(TESTS_DIR, name), 'utf8').split('\n').forEach((line, i) => {
      if (DIRECT_CALL.test(line)) offenders.push(`${name}:${i + 1}: ${line.trim()}`);
    });
  }
  assert.deepEqual(offenders, [], `goi thang mkdtemp, hay doi sang tmpDir(prefix) cua tests/helpers.js:\n${offenders.join('\n')}`);
});
