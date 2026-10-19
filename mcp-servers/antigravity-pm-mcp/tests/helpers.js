import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/** Doi dong ho nhich it nhat `ms` mili-giay (moc giao viec va mtime result.json khong trung mili-giay). */
export function tick(ms = 3) {
  const end = Date.now() + ms;
  while (Date.now() < end) { /* cho */ }
}

/** PNG 1x1 that (de test duong di cua anh nghiem thu). */
export const PNG_1PX = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
  'base64',
);

// Test khong duoc dinh cau hinh chung that cua may dang chay: tro ANTIGRAVITY_PM_GLOBAL_CONFIG vao cho KHONG BAO GIO co file
// (/dev/null khong phai thu muc) ngay khi nap helpers. Truoc day la os.tmpdir()/agpm-test-...: duong dan doan duoc trong /tmp dung chung,
// nguoi khac (hoac lan chay cu) tao san file do (vd testCommand la) thi lai duoc moi test (OpenCodeReview 14/10).
const NO_GLOBAL_CONFIG = '/dev/null/agpm-test-khong-co-cau-hinh-chung/.antigravity-pm.json';
/** "agy vang mat" cho test tu dat ANTIGRAVITY_PM_AGY giua chung: khong bao gio co file (khong ai dat san duoc mot agy gia o day de bi chay). */
export const NO_AGY = '/dev/null/agpm-khong-co-agy/agy';
process.env.ANTIGRAVITY_PM_GLOBAL_CONFIG = NO_GLOBAL_CONFIG;
// Test KHONG duoc chay agy THAT (agent Argon, --dangerously-skip-permissions, tren thu muc tam): tro vao file khong ton tai => AntigravityUnavailable
// o buoc "goi agent", dung cho nhung test cu cho do. Test can agy gia thi tu dat lai (tests/agy-model.test.js). 14/10/2026: khi model mac dinh
// doi sang Argon, bai-hoc-14-09 #3 da sinh 3 tien trinh agy that voi prompt TRIEN KHAI.
// Duong dan tu mkdtemp (khong doan truoc duoc, /tmp dung chung khong cho ai dat san file thuc thi o do); so project cua IDE cung la thu muc tam rong,
// de test khong doc ~/.gemini that (chinh sach EAGER/TURBO, project da dang ky).
// Thu muc tam tao qua tmpDir() duoc xoa khi tien trinh test thoat, ke ca khi test quen goi cleanup(), hong giua chung, hay bi
// SIGTERM/SIGINT/SIGHUP (post-fix-gate gui TERM truoc KILL khi het gio; Node khong chay 'exit' khi chet vi tin hieu). 19/10/2026:
// hon 700 thu muc agpm-test-*, agpm-s-/-shot-/-src-* sot lai trong TMPDIR, moi lan npm test them 6.
const CREATED = new Set();
const removeCreated = () => { for (const dir of CREATED) cleanup(dir); };
process.once('exit', removeCreated);
for (const sig of ['SIGTERM', 'SIGINT', 'SIGHUP']) {
  // don xong roi thoat voi ma 128+tin hieu (gui lai tin hieu thi listener khac, vd cua node:test, co the nuot mat)
  process.once(sig, () => { removeCreated(); process.exit(128 + os.constants.signals[sig]); });
}

/** Thu muc tam cua mot test, tu xoa khi tien trinh thoat. */
export function tmpDir(prefix = 'agpm-test-') {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  CREATED.add(dir);
  return dir;
}

const NO_AGY_DIR = tmpDir('agpm-test-no-agy-');
process.env.ANTIGRAVITY_PM_AGY = path.join(NO_AGY_DIR, 'agy');
process.env.ANTIGRAVITY_PM_PROJECTS_DIR = path.join(NO_AGY_DIR, 'ide-projects');
// Trang thai PM (task.json) nam o HOME: test khong duoc ghi vao ~/.antigravity-pm that.
process.env.ANTIGRAVITY_PM_STATE_HOME = tmpDir('agpm-state-home-');

/** Tao cau hinh chung gia (dong vai ~/.antigravity-pm.json) cho mot test. */
export function tmpGlobalConfig(config = {}) {
  const dir = tmpDir('agpm-home-');
  const file = path.join(dir, '.antigravity-pm.json');
  fs.writeFileSync(file, JSON.stringify(config, null, 2));
  process.env.ANTIGRAVITY_PM_GLOBAL_CONFIG = file;
  return {
    dir,
    file,
    restore() {
      process.env.ANTIGRAVITY_PM_GLOBAL_CONFIG = NO_GLOBAL_CONFIG;
      cleanup(dir);
    },
  };
}

export function tmpProject(config = {}) {
  const dir = tmpDir('agpm-test-');
  fs.writeFileSync(path.join(dir, '.antigravity-pm.json'), JSON.stringify(config, null, 2));
  return dir;
}

export function writeFile(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
  return file;
}

export function cleanup(dir) {
  try {
    fs.rmSync(dir, { recursive: true, force: true });
    CREATED.delete(dir);   // da xoa: ten tro lai cho mkdtemp cua tien trinh khac, luc thoat khong xoa lai
  } catch { /* xoa hong: van theo doi, luc thoat thu lai */ }
}

/** Task mau da co du de test cong chan. */
export function sampleTaskArgs(over = {}) {
  return {
    title: 'Thêm cổng chặn kính xe',
    brief: 'Hiện tại lệnh hạ kính không hỏi xác nhận. Cần thêm bước xác nhận.',
    definitionOfDone: ['Có unit test cho cổng chặn', 'Không đổi hành vi lệnh khác'],
    ...over,
  };
}
