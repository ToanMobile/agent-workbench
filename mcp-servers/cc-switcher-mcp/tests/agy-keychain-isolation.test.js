// agy luu tai khoan trong Keychain (service gemini), Keychain theo HOME: profile phai co Library/Keychains rieng, khong symlink Library that.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const zshFile = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'shell', 'agy-profile.zsh');
const darwin = process.platform === 'darwin';

function buildHome() {
  const real = fs.mkdtempSync(path.join(os.tmpdir(), 'agy-kc-'));
  fs.mkdirSync(path.join(real, 'Library', 'Keychains'), { recursive: true });
  fs.mkdirSync(path.join(real, 'Library', 'Preferences'), { recursive: true });
  fs.mkdirSync(path.join(real, 'Library', 'Application Support'), { recursive: true });
  fs.writeFileSync(path.join(real, '.gitconfig'), '[user]\n');
  const r = spawnSync('zsh', ['-f', '-c', `source '${zshFile}'; _agy_build_home antigravity_pro`], {
    env: { PATH: process.env.PATH, HOME: real },
    encoding: 'utf8',
  });
  return { real, h: path.join(real, '.agy-antigravity_pro'), r };
}

test('Library cua profile la thu muc that; Keychains va Preferences la thu muc rieng, muc khac symlink', { skip: !darwin }, () => {
  const { real, h, r } = buildHome();
  assert.equal(r.status, 0, r.stderr);
  assert.ok(fs.lstatSync(path.join(h, 'Library')).isDirectory(), 'Library khong duoc la symlink');
  for (const d of ['Keychains', 'Preferences']) {
    assert.ok(fs.lstatSync(path.join(h, 'Library', d)).isDirectory(), `${d} phai la thu muc rieng`);
  }
  assert.ok(fs.lstatSync(path.join(h, 'Library', 'Application Support')).isSymbolicLink());
  assert.equal(fs.readlinkSync(path.join(h, 'Library', 'Application Support')), path.join(real, 'Library', 'Application Support'));
  assert.ok(fs.lstatSync(path.join(h, '.gitconfig')).isSymbolicLink());
  assert.ok(fs.existsSync(path.join(h, 'Library', 'Keychains', 'login.keychain-db')), 'can login.keychain-db rieng');
});

test('profile cu co Library la symlink duoc doi thanh thu muc that, thu muc that khong bi xoa', { skip: !darwin }, () => {
  const real = fs.mkdtempSync(path.join(os.tmpdir(), 'agy-kc-'));
  fs.mkdirSync(path.join(real, 'Library', 'Keychains'), { recursive: true });
  fs.writeFileSync(path.join(real, 'Library', 'Keychains', 'keep.txt'), 'x');
  const h = path.join(real, '.agy-antigravity_pro');
  fs.mkdirSync(h, { recursive: true });
  fs.symlinkSync(path.join(real, 'Library'), path.join(h, 'Library'));
  const r = spawnSync('zsh', ['-f', '-c', `source '${zshFile}'; _agy_build_home antigravity_pro`], {
    env: { PATH: process.env.PATH, HOME: real },
    encoding: 'utf8',
  });
  assert.equal(r.status, 0, r.stderr);
  assert.ok(fs.lstatSync(path.join(h, 'Library')).isDirectory());
  assert.ok(fs.existsSync(path.join(real, 'Library', 'Keychains', 'keep.txt')), 'Library that phai con nguyen');
  assert.ok(!fs.existsSync(path.join(real, 'Library', 'Keychains', 'login.keychain-db')), 'khong tao keychain trong HOME that');
});
