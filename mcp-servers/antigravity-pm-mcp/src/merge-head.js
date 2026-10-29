// #672: head moi H co phai "merge commit cua origin/main vao auditedHead A, diff cua PR khong doi"?
// Gate merge tu gop main vao nhanh PR nen head doi du diff PR giu nguyen. Moi bat dinh (git loi, sha la) = khong chap nhan.
import { execFileSync } from 'node:child_process';

const SHA = /^[0-9a-f]{40}$/;
const git = (root, args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 5000, maxBuffer: 16_000_000 }).trim();
const lines = (s) => s.split('\n').filter(Boolean);
const nul = (s) => s.split('\0').filter(Boolean);

/** @returns {{ok: boolean, reason: string}} reason = ly do chap nhan (parent1, parent2, hai ket qua diff) hoac ly do tu choi */
export function mergeHeadVerdict(root, audited, head, base = 'origin/main') {
  const no = (why) => ({ ok: false, reason: `head ${head} khong phai merge commit hop le cua auditedHead ${audited}: ${why}` });
  if (!SHA.test(audited) || !SHA.test(head)) return no('sha khong hop le');
  try {
    const [, p1, p2, ...extra] = git(root, ['rev-list', '--parents', '-n1', head]).split(' ');
    if (!p2 || extra.length) return no('khong phai merge commit hai parent');
    if (p1 !== audited) return no(`parent1 ${p1} khac auditedHead`);
    try { git(root, ['merge-base', '--is-ancestor', p2, base]); } catch { return no(`parent2 ${p2} khong nam trong ${base}`); }
    // -z/--no-renames: ten file la/doi ten khong bi boc dau; --literal-pathspecs: ten co ky tu pathspec khong doi pham vi.
    const names = (a, b) => nul(git(root, ['--no-pager', 'diff', '--name-only', '-z', '--no-renames', a, b]));
    const raw = (a, b) => nul(git(root, ['--no-pager', 'diff', '--raw', '--no-abbrev', '--no-renames', '-z', a, b]));
    const prFiles = names(git(root, ['merge-base', base, audited]), audited);
    if (!prFiles.length) return no('diff cua PR rong, khong co file de doi chieu');
    // Lenh 1: file cua PR giua auditedHead va head phai khong doi.
    if (git(root, ['--literal-pathspecs', '--no-pager', 'diff', '--name-only', audited, head, '--', ...prFiles])) return no('git diff auditedHead head -- <file cua PR> khong rong');
    // Lenh 2: moi ban ghi doi (mode, blob, path) giua auditedHead va head phai nam trong thay doi cua main (diem re..parent2).
    // Ten file khong du: merge sua noi dung file trung ten voi file main doi, hay `-s ours`, van lot.
    const fromMain = new Set(raw(git(root, ['merge-base', audited, p2]), p2));
    const stray = raw(audited, head).filter((r) => !fromMain.has(r));
    if (stray.length) return no('thay doi giua auditedHead va head khong den tu main');
    // Cay cua head phai bang dung ket qua tu merge auditedHead voi parent2 (chan evil merge, -s ours, giai xung dot tay).
    if (git(root, ['merge-tree', '--write-tree', audited, p2]) !== git(root, ['rev-parse', `${head}^{tree}`])) return no('cay cua head khac ket qua merge tu dong auditedHead voi parent2');
    return { ok: true, reason: `merge-head: parent1=${p1} parent2=${p2} diff-pr-files=empty diff-from-main=ok` };
  } catch (e) {
    return no(`git loi (${String(e.message).split('\n')[0]})`);
  }
}
