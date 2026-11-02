// #742 finding 46b9215e8f: takeStaleLock() đổi tên lockFile sang aside rồi mới xét tuổi. Nếu chủ cũ vừa nhả khoá và C vừa lấy
// khoá mới, B đổi tên mất khoá SỐNG của C; D chen vào lockFile trống, linkSync trả EEXIST và file .stale bị bỏ lại.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { withFileLock } from '../src/tasks.js';
import { tmpDir, cleanup } from './helpers.js';

const leftovers = (dir) => fs.readdirSync(dir).filter((n) => n !== 'x.lock');

test('withFileLock: khoá sống vừa thay chỗ khoá cũ thì không bị cướp, không rò .stale', () => {
  const dir = tmpDir('agpm-lock-race-');
  const lock = path.join(dir, 'x.lock');
  const cToken = `${process.pid}.${Date.now()}.ccc`;
  const real = { statSync: fs.statSync, readFileSync: fs.readFileSync, renameSync: fs.renameSync, rmSync: fs.rmSync };
  let swapped = false;
  let dJoined = false;
  // Ngay sau lần B nhìn khoá cũ đầu tiên: chủ cũ A nhả khoá, C lấy khoá mới (tươi, tiến trình còn sống).
  const afterFirstLook = (p) => {
    if (swapped || p !== lock) return;
    swapped = true;
    real.rmSync(lock, { force: true });
    fs.writeFileSync(lock, cToken, { flag: 'wx' });
  };
  // Lúc lockFile biến khỏi đĩa: D lấy được khoá ngay (openSync wx).
  const afterVanish = (p) => {
    if (dJoined || p !== lock || fs.existsSync(lock)) return;
    dJoined = true;
    fs.writeFileSync(lock, `${process.pid}.${Date.now()}.ddd`, { flag: 'wx' });
  };
  try {
    fs.writeFileSync(lock, `${process.pid}.${Date.now() - 60000}.aaa`);
    const old = new Date(Date.now() - 60000);
    fs.utimesSync(lock, old, old);
    fs.statSync = (p, ...rest) => { const r = real.statSync(p, ...rest); afterFirstLook(p); return r; };
    fs.readFileSync = (p, ...rest) => { const r = real.readFileSync(p, ...rest); afterFirstLook(p); return r; };
    fs.renameSync = (a, b) => { real.renameSync(a, b); afterVanish(a); };
    fs.rmSync = (p, ...rest) => { real.rmSync(p, ...rest); if (p === lock) afterVanish(p); };

    let ran = false;
    assert.throws(() => withFileLock(lock, () => { ran = true; }), /Khong lay duoc khoa/);
    assert.equal(ran, false, 'B không được vào vùng găng khi C đang giữ khoá');
    assert.equal(swapped, true);
    assert.equal(real.readFileSync(lock, 'utf8'), cToken, 'khoá của C phải còn nguyên ở lockFile');
    assert.deepEqual(leftovers(dir), [], 'không rò file aside/.stale/.reap');
  } finally {
    Object.assign(fs, real);
    cleanup(dir);
  }
});

test('withFileLock: khoá của tiến trình đã chết được thu hồi ngay, kể cả khi còn tươi', () => {
  const dir = tmpDir('agpm-lock-race-');
  try {
    const lock = path.join(dir, 'x.lock');
    const deadPid = spawnSync(process.execPath, ['-e', '']).pid;
    fs.writeFileSync(lock, `${deadPid}.${Date.now()}.dead`);
    const t0 = Date.now();
    assert.equal(withFileLock(lock, () => 'ok'), 'ok');
    assert.ok(Date.now() - t0 < 2000, 'không phải chờ 30 s hay tới hạn 5 s');
    assert.equal(fs.existsSync(lock), false);
    assert.deepEqual(leftovers(dir), []);
  } finally { cleanup(dir); }
});
