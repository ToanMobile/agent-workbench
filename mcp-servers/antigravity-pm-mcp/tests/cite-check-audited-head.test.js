// 16/11: audit PR #1204 bị pm_verdict từ chối vì 2 trích dẫn "not-found" dù có thật ở head được audit: kiemTrichDan đối chiếu với cây
// làm việc HIỆN TẠI (main), nơi dòng đó đã đổi chỗ. Báo cáo có auditedHead (sha40) thì trích dẫn phải đối chiếu với blob ở đúng sha đó.
//  A  dòng có ở head audit nhưng KHÔNG có ở cây hiện tại -> verified (không còn NOT-FOUND).
//  B  dòng không có ở cả hai -> vẫn not-found (trích dẫn bịa vẫn bị bắt).
//  C  không có auditedHead -> chỉ đối chiếu cây hiện tại như cũ.
//  D  auditedHead không phải sha40 (ví dụ chuỗi lạ / cờ git) -> bỏ qua, không chạy git với nó.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { kiemBaoCao } from '../src/cite-check.js';
import { tmpDir, cleanup } from './helpers.js';

const git = (cwd, ...a) => execFileSync('git', a, { cwd, encoding: 'utf8', env: { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t' } }).trim();

function repoWithMovedLine() {
  const dir = tmpDir();
  git(dir, 'init', '-q');
  fs.writeFileSync(path.join(dir, 'gate.sh'), 'a\nb\nwinning || exit 1\nc\n');
  git(dir, 'add', '.');
  git(dir, 'commit', '-q', '-m', 'audited');
  const head = git(dir, 'rev-parse', 'HEAD');
  // cây hiện tại: dòng đã bị xoá (main đi tiếp)
  fs.writeFileSync(path.join(dir, 'gate.sh'), 'a\nb\nc\n');
  git(dir, 'commit', '-q', '-am', 'main moved on');
  return { dir, head };
}
const rep = (extra) => ({ dod_check: [{ evidence: 'gate.sh:3', snippet: 'winning || exit 1' }], ...extra });

test('A: citation present at auditedHead but not in the current tree is verified', () => {
  const { dir, head } = repoWithMovedLine();
  try {
    const kq = kiemBaoCao(dir, rep({ auditedHead: head }));
    assert.equal(kq.bia.length, 0, JSON.stringify(kq.items));
    assert.equal(kq.counts.verified, 1);
  } finally { cleanup(dir); }
});

test('B: a citation that exists nowhere is still not-found', () => {
  const { dir, head } = repoWithMovedLine();
  try {
    const kq = kiemBaoCao(dir, { auditedHead: head, dod_check: [{ evidence: 'gate.sh:3', snippet: 'this line was never written' }] });
    assert.equal(kq.bia.length, 1);
    assert.equal(kq.items[0].status, 'not-found');
  } finally { cleanup(dir); }
});

test('C: without auditedHead only the current tree is read (old behaviour)', () => {
  const { dir } = repoWithMovedLine();
  try {
    const kq = kiemBaoCao(dir, rep({}));
    assert.equal(kq.bia.length, 1);
  } finally { cleanup(dir); }
});

test('D: an auditedHead that is not a 40-hex sha is ignored', () => {
  const { dir } = repoWithMovedLine();
  try {
    const kq = kiemBaoCao(dir, rep({ auditedHead: '--output=/tmp/x' }));
    assert.equal(kq.bia.length, 1);
  } finally { cleanup(dir); }
});
