// Vo boc mong quanh `agentapi` cua Antigravity (CLI noi bo, KHONG duoc Google tai lieu hoa).
// Chi co 3 lenh: new-conversation / send-message / get-conversation-metadata.
// Moi thay doi giao dien cua no phai no O DAY va no THAT TO, khong am tham fallback.
//
// Hai duong, chon theo `model`:
//   bac (flash_lite | flash | pro) -> `agentapi --model=<bac>`: hoi thoai nam trong IDE, model do server quyet (14/10/2026: ca `pro` va
//     `flash` deu ra gemini-3.8-flash-tiered; agentapi tu choi ten model cu the: "no available models found for tier ...").
//   model cu the (gemini-4-argon-high ...) -> CLI `agy --model`: cach DUY NHAT chon duoc model. Hoi thoai cua agy nam o
//     ~/.gemini/antigravity-cli (IDE khong thay: "trajectory not found"), luot chay song cung tien trinh agy (agy thoat = luot dung),
//     nen tien trinh duoc tach nhom, chay den het, va so dang ky agy-conversations.json giu model + cwd + pid cua tung hoi thoai.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, execFileSync } from 'node:child_process';
import { run, redact, truncate, homeStateDir, readJsonIfExists, writeJsonAtomic, ensureDir, nowIso, trackChild, untrackChild, logStderr, killGroup } from './util.js';
import { discover, forgetCache, AntigravityUnavailable, ENV_ADDRESS, ENV_TOKEN } from './discover.js';
import { ENV_PROJECT_ID, resolveProject } from './projects.js';

export const TIERS = ['flash_lite', 'flash', 'pro'];
export const AGY_MODELS = [
  'gemini-4-argon-high', 'gemini-4-argon-medium', 'gemini-4-argon-low',
  'gemini-3.8-flash-high', 'gemini-3.8-flash-medium', 'gemini-3.8-flash-low',
];
export const MODELS = [...TIERS, ...AGY_MODELS];
export const isAgyModel = (m) => AGY_MODELS.includes(m);

export class AgentApiError extends Error {
  constructor(message, detail) {
    super(message);
    this.name = 'AgentApiError';
    this.detail = detail;
  }
}

function connEnv(conn, extra = {}) {
  return { [ENV_ADDRESS]: conn.address, [ENV_TOKEN]: conn.secret, ...extra };
}

async function call(args, { timeoutMs = 180000, retryOnRpcError = true, projectId = null } = {}) {
  // new-conversation bat buoc co project id; thieu no server bao
  // "project_id is required when providing project_env_config".
  const extraEnv = projectId ? { [ENV_PROJECT_ID]: projectId } : {};
  let conn = await discover();
  let r = await run(conn.agentapi, args, { timeoutMs, env: connEnv(conn, extraEnv) });
  let parsed = parseJson(r.stdout);

  const rpcBroken = r.code !== 0 || /rpc error|Unauthenticated|connection (error|reset)/i.test(`${r.stdout}${r.stderr}`);
  if (rpcBroken && retryOnRpcError) {
    // IDE co the vua khoi dong lai => cong/khoa phien doi. Do lai 1 lan roi thoi.
    forgetCache();
    conn = await discover({ force: true });
    r = await run(conn.agentapi, args, { timeoutMs, env: connEnv(conn, extraEnv) });
    parsed = parseJson(r.stdout);
  }

  const clean = (s) => truncate(redact(s, [conn.secret]), 4000);
  if (r.timedOut) throw new AgentApiError(`agentapi ${args[0]} qua han ${timeoutMs}ms`, clean(r.stderr));
  if (parsed && parsed.error) throw new AgentApiError(`agentapi ${args[0]} bao loi: ${clean(String(parsed.error))}`, clean(r.stderr));
  if (r.code !== 0) throw new AgentApiError(`agentapi ${args[0]} ket thuc voi exit ${r.code}`, clean(`${r.stdout}\n${r.stderr}`));
  if (!parsed) throw new AgentApiError(`agentapi ${args[0]} tra ve thu khong phai JSON (CLI noi bo co the da doi)`, clean(r.stdout));
  return { parsed, raw: clean(r.stdout), address: conn.address };
}

function parseJson(s) {
  const t = String(s || '').trim();
  if (!t) return null;
  try { return JSON.parse(t); } catch { /* thu cach khac */ }
  const i = t.indexOf('{');
  const j = t.lastIndexOf('}');
  if (i >= 0 && j > i) {
    try { return JSON.parse(t.slice(i, j + 1)); } catch { return null; }
  }
  return null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Lan tim bat ky khoa ket thuc bang conversationId / conversation_id trong cay JSON. */
export function findConversationId(obj, depth = 0) {
  if (!obj || typeof obj !== 'object' || depth > 8) return null;
  for (const [k, v] of Object.entries(obj)) {
    if (typeof v === 'string' && UUID_RE.test(v) && /conversation_?id$/i.test(k)) return v;
  }
  for (const v of Object.values(obj)) {
    const found = findConversationId(v, depth + 1);
    if (found) return found;
  }
  // Cuoi cung: bat ky UUID nao xuat hien trong cay (CLI noi bo co the doi ten khoa).
  if (depth === 0) return findAnyUuid(obj);
  return null;
}

function findAnyUuid(obj, depth = 0) {
  if (!obj || typeof obj !== 'object' || depth > 8) return null;
  for (const v of Object.values(obj)) {
    if (typeof v === 'string' && UUID_RE.test(v)) return v;
    const found = findAnyUuid(v, depth + 1);
    if (found) return found;
  }
  return null;
}

// ---- duong agy (model cu the) ---------------------------------------------------------------------------------------------
const AGY_INIT_WAIT_MS = 60000;
const AGY_RUNS_KEEP_MS = 7 * 24 * 3600 * 1000;

/** Binary agy. ANTIGRAVITY_PM_AGY dat thi CHI dung no (khong roi sang cho khac): biet chinh xac dang goi binary nao. */
export function agyPath() {
  const home = process.env.HOME || os.homedir();
  const candidates = process.env.ANTIGRAVITY_PM_AGY
    ? [process.env.ANTIGRAVITY_PM_AGY]
    : [path.join(home, '.local/bin/agy'), '/opt/homebrew/bin/agy', '/usr/local/bin/agy'];
  for (const c of candidates) {
    try { fs.accessSync(c, fs.constants.X_OK); return c; } catch { /* thu cai ke tiep */ }
  }
  return null;
}

const agyRegistryFile = () => path.join(homeStateDir(), 'agy-conversations.json');
/** So dang ky hoi thoai agy. File hong thi NEM LOI (khong coi la rong roi ghi de: se mat model + cwd cua moi hoi thoai dang chay). */
function readAgyRegistry() {
  const f = agyRegistryFile();
  if (!fs.existsSync(f)) return {};
  const bad = (why) => new AgentApiError(`${f} hong (${why}): sua tay hoac xoa file. PM khong tu ghi de de khong mat hoi thoai agy dang chay.`);
  let r;
  try { r = JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { throw bad(e.message); }
  if (!r || typeof r !== 'object' || Array.isArray(r)) throw bad('khong phai object');
  return r;
}
/**
 * agyTurnStatus cho tool DOC: { status, error, registryBroken } (khong nem). error = ps / so dang ky khong tra loi duoc: "khong biet",
 * khong phai "da xong". So dang ky doc duoc ma van co error => loi tu ps tren MOT MUC CO TRONG SO: hoi thoai nay chac chan la agy.
 */
export function agyTurnStatusSafe(conversationId) {
  if (!conversationId) return { status: null, error: null };
  // So dang ky hong: khong biet hoi thoai nay la agy hay IDE => "khong biet" (nudge bo qua), khong phai "khong phai agy"
  const problem = agyRegistryProblem();
  if (problem) return { status: null, error: problem.split('\n')[0], registryBroken: true };
  try { return { status: agyTurnStatus(conversationId), error: null }; } catch (e) { return { status: null, error: String(e.message || e).split('\n')[0] }; }
}

/** Loi cua duong IDE khi so dang ky agy dang hong: noi nguyen nhan co the that (hoi thoai agy bi dinh sang IDE se bao "trajectory not found"). */
async function withRegistryHint(fn) {
  try { return await fn(); } catch (e) {
    const problem = agyRegistryProblem();
    if (problem && e instanceof Error) e.message += ` | LUU Y: so dang ky agy co van de, neu day la hoi thoai agy thi do la nguyen nhan that: ${problem.split('\n')[0]}`;
    throw e;
  }
}

/** Tra cuu de CHON DUONG (agy hay IDE): so dang ky hong khong duoc keo sap duong IDE. Ghi / dat cho van doc nghiem (readAgyRegistry). */
function agyEntryOf(id) {
  try { return readAgyRegistry()[id]; } catch (e) { logStderr(e.message); return undefined; }
}

/** null = so dang ky doc duoc (hoac chua co); khac = cau mo ta hong. Cho pm_status / pm_doctor hien ra: tra cuu chon duong chi ghi stderr. */
export function agyRegistryProblem() {
  try { readAgyRegistry(); return null; } catch (e) { return e.message; }
}

const LOCK_STALE_MS = 20000;   // > ngan sach ps toi da duoi khoa (<= 5 lan x 1,5 s) de PM khac khong lay mat khoa dang giu that
/**
 * Lay lai khoa cu (chu khoa da chet): DOI TEN no sang ten rieng (nguyen tu) roi xet CHINH file vua lay ra. Hai PM cung thay mot khoa cu:
 * PM sau co the lay trung khoa MOI cua PM truoc (no vua lay lai xong) => file trong tay con tuoi: tra lai cho cu (putLockBack) roi cho
 * nhu thuong. Truoc day xoa-roi-tao: PM sau xoa luon khoa moi, ca hai cung vao doan gang (OpenCodeReview 14/10).
 * true = da bo khoa cu, tao lai ngay; false = khong lay duoc / da tra lai: cho.
 */
// ponytail: tra lai khong nguyen tu voi PM THU BA: giua rename va link (hoac rename lai, tren he tep khong co hard link) PM C tao duoc khoa
// (C va chu khoa cung vao doan gang), hoac chu khoa xong viec dung luc do va khoa tra lai thanh mo coi (het han sau LOCK_STALE_MS). Can ba
// PM cung dung mot khoa cu trong vai micro giay; nang cap thanh flock (Node khong co san) neu thay xay ra.
function takeStaleLock(lock, token) {
  const aside = `${lock}.${token}.stale`;
  try { fs.renameSync(lock, aside); } catch { return false; }   // vua duoc nha / PM khac vua lay di
  let fresh = true;   // khong xet duoc thi coi la tuoi: tra lai, khong bo khoa co the con nguoi giu
  try { fresh = Date.now() - fs.statSync(aside).mtimeMs <= LOCK_STALE_MS; } catch (e) { logStderr(`khoa so dang ky agy: khong xet duoc ${aside} (${e.message}): tra lai`); }
  if (fresh) { putLockBack(aside, lock); return false; }
  fs.rmSync(aside, { force: true });
  return true;
}

/**
 * Tra khoa con tuoi (da doi ten sang `aside`) ve cho cu; chi bo `aside` khi da tra duoc. link khong bao gio de len khoa cua PM thu ba
 * (EEXIST). He tep khong co hard link (EPERM, ENOTSUP...): doi ten lai, duong dan khoa dang trong vi chinh ta vua doi ten no di
 * (OpenCodeReview 14/10: truoc day link loi thi van xoa `aside` => khoa cua chu dang giu bi xoa). Khong tra duoc thi giu `aside` lam dau vet.
 */
function putLockBack(aside, lock) {
  try {
    fs.linkSync(aside, lock);
  } catch (e) {
    if (e.code === 'EEXIST') {
      logStderr(`khoa so dang ky agy: lay nham khoa con tuoi cua PM khac va PM thu ba da tao khoa moi: giu ${aside}`);
      return;
    }
    try { fs.renameSync(aside, lock); } catch (e2) {
      logStderr(`khoa so dang ky agy: khong tra lai duoc khoa con tuoi cua PM khac (link ${e.code || e.message}, rename ${e2.code || e2.message}): giu ${aside}`);
    }
    return;
  }
  fs.rmSync(aside, { force: true });   // da link lai: `aside` chi con la ten phu
}

/** Khoa file ngan (open 'wx') quanh doc-sua-ghi so dang ky: hai tien trinh PM khong dat cho / ghi de len nhau. Khoa mo coi > 20 s la cu. */
function withRegistryLock(fn) {
  const lock = `${agyRegistryFile()}.lock`;
  const token = `${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const deadline = Date.now() + 3000;
  for (;;) {
    try { fs.writeFileSync(lock, token, { flag: 'wx', mode: 0o600 }); break; } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      try {
        if (Date.now() - fs.statSync(lock).mtimeMs > LOCK_STALE_MS && takeStaleLock(lock, token)) continue;
      } catch { /* khoa vua duoc nha */ }
      if (Date.now() > deadline) throw new AgentApiError(`khoa so dang ky agy ${lock} bi giu qua 3 s`);
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25);
    }
  }
  try { return fn(); } finally {
    // chi go khoa CUA MINH: khoa cu bi PM khac lay lai thi khong xoa nham khoa moi cua no
    try { if (fs.readFileSync(lock, 'utf8') === token) fs.rmSync(lock, { force: true }); } catch { /* da bi lay lai hoac da nha */ }
  }
}

function putAgyEntry(reg, id, entry) {
  reg[id] = { ...(reg[id] || {}), ...entry };
  // ponytail: so dang ky chi tang; giu 500 hoi thoai dung gan nhat (lastSentAt, khong phai luc tao), nang cap thanh xoa theo task khi can
  const keys = Object.keys(reg);
  if (keys.length > 500) {
    const used = (k) => String(reg[k].lastSentAt || reg[k].at || '');
    // chi bo muc KHONG co luot dang chay (entryBusy): don muc dang chay thi lan gui sau mat model + cwd va roi sang agentapi ("trajectory not found")
    let over = keys.length - 500;
    let asked = 0;   // moi lan hoi la mot lenh ps dong bo DUOI khoa: chan tren, khong thi nhieu muc cham giu khoa qua LOCK_STALE_MS va PM khac lay mat
    for (const k of keys.sort((a, b) => used(a).localeCompare(used(b)))) {
      if (over <= 0) break;
      if (k === id) continue;
      if (reg[k].pid && reg[k].pidTag) {   // chi muc co pid + dau van tay moi can ps (entryBusy tra ve ngay neu khong co)
        if (asked >= 3) continue;   // het ngan sach ps: GIU muc nay nhung van don tiep cac muc khong can ps (truoc day dung ca vong)
        asked += 1;
      }
      let busy = true;   // khong xac dinh duoc (ps loi) thi GIU muc: don nha khong duoc lam hong lan ghi dang dien ra (va khong giu khoa qua lau)
      try { busy = entryBusy(reg[k]); } catch (e) { logStderr(`don so dang ky: giu muc ${k} (${e.message})`); }
      if (busy) continue;
      delete reg[k];
      over -= 1;
    }
  }
  writeJsonAtomic(agyRegistryFile(), reg);
}
function saveAgyEntry(id, entry) {
  return withRegistryLock(() => putAgyEntry(readAgyRegistry(), id, entry));
}

/** Dau van tay cua tien trinh: thoi diem bat dau (ps lstart). Pid bi he dieu hanh dung lai thi dau van tay khac => khong nhan nham. */
let SELF_TAG = null;
/** Dau van tay cua chinh PM: khong doi suot doi tien trinh nen tinh MOT lan (reserveTurn khong goi ps them duoi khoa). */
const selfTag = () => { SELF_TAG = SELF_TAG || procTag(process.pid); return SELF_TAG; };

function procTag(pid) {
  if (!pid) return null;
  try {
    // /bin/ps tuyet doi + LC_ALL=C TZ=UTC: lstart doi theo TZ/locale cua tung PM => PM thu hai khong nhan ra agy cua PM dau (do 14/10/2026).
    return execFileSync(process.env.ANTIGRAVITY_PM_PS || '/bin/ps', ['-o', 'lstart=', '-p', String(pid)],
      { encoding: 'utf8', timeout: 1500, env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' } }).trim() || null;
  } catch (e) {
    // Pid vua thoat: ps exit 1, khong in gi => tien trinh da chet. Moi truong hop khac la KHONG BIET: nem loi to, khong coi la "da xong".
    if (e.status === 1 && !String(e.stdout || '').trim() && !String(e.stderr || '').trim()) return null;
    throw new AgentApiError(`khong doc duoc dau van tay tien trinh ${pid} (ps): ${e.message}`);
  }
}
/** Pid con la DUNG tien trinh co dau van tay `pidTag` (pid bi dung lai / da thoat => false; khong co dau van tay => false). Nem khi ps hong. */
export function sameProcess(pid, pidTag) {
  return Boolean(pid && pidTag) && procTag(pid) === pidTag;
}
const RESERVATION_MAX_MS = 90000;   // = cho init toi da (60 s) + le: cho giu "starting" qua han la cho khong nha duoc (PM van song), khong phai agy dang mo
function entryBusy(e) {
  if (!e?.pid || !e.pidTag) return false;
  if (e.reservation && e.reservedAt && Date.now() - Date.parse(e.reservedAt) > RESERVATION_MAX_MS) return false;   // chi cho giu cua PM: pid agy THAT thi khong het han
  return procTag(e.pid) === e.pidTag;
}

/**
 * null = khong phai hoi thoai agy; con lai { running, starting, pid }.
 * running = tien trinh agy cua luot hien tai con song (dung dau van tay, khong chi pid); starting = PM dang mo luot (chua co pid agy).
 */
export function agyTurnStatus(conversationId) {
  const e = agyEntryOf(conversationId);
  if (!e) return null;
  return { running: entryBusy(e), starting: Boolean(e.starting), pid: e.pid || null };
}

/**
 * agy headless tu choi moi lenh shell tru khi co allow rule hoac --dangerously-skip-permissions. Co do chi duoc truyen khi nguoi dung DA cho IDE
 * tu chay lenh (EAGER/TURBO): chinh sach cua project trong ~/.gemini/config/projects, khong co thi cai chung trong ~/.gemini/config/config.json
 * (userSettings.autoExecutionPolicy). Khong dat => loi to, KHONG am tham nang quyen (plan_review/audit la doc, implement sua file).
 * ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS=1: cong tac cua nguoi dung, bo qua kiem tra.
 */
/** Chinh sach quyen cho agy tai cwd: { ok, policy, from } (khong nem loi). Dung chung cho chot quyen va pm_doctor. */
export function agyPermissionPolicy(cwd) {
  if (process.env.ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS === '1') return { ok: true, policy: 'ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS=1', from: 'bien moi truong (cong tac cua nguoi dung)' };
  const proj = resolveProject(cwd);
  let policy = proj?.autoExecution || null;
  let from = proj ? `project "${proj.name}" cua Antigravity` : null;
  if (!policy) {
    const g = readJsonIfExists(path.join(process.env.HOME || os.homedir(), '.gemini/config/config.json'));
    policy = g?.userSettings?.autoExecutionPolicy || null;
    from = '~/.gemini/config/config.json';
  }
  return { ok: Boolean(policy && /_(EAGER|TURBO)$/.test(policy)), policy, from };   // khop ten enum, khong phai chuoi con bat ky
}

function agyMaySkipPermissions(cwd) {
  const p = agyPermissionPolicy(cwd);
  if (p.ok) return true;
  throw new AgentApiError(
    `agy chay khong co nguoi bam Accept nen can --dangerously-skip-permissions, nhung chinh sach tu chay lenh cua IDE la "${p.policy || '(chua dat)'}" (${p.from}). `
    + 'Dat autoExecutionPolicy = EAGER/TURBO trong Antigravity cho project nay (hoac ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS=1 neu ban chap nhan). PM khong tu nang quyen.',
  );
}

function pruneAgyRuns(dir) {
  try {
    const cutoff = Date.now() - AGY_RUNS_KEEP_MS;
    for (const name of fs.readdirSync(dir)) {
      const f = path.join(dir, name);
      if (fs.statSync(f).mtimeMs < cutoff) fs.rmSync(f, { force: true });
    }
  } catch (e) {
    logStderr(`khong don duoc ${dir}: ${e.message}`);
  }
}

/** Binary agy hoac AntigravityUnavailable. Goi TRUOC chot quyen: loi "khong co agy" khong duoc phu thuoc chinh sach quyen that cua may. */
function requireAgy() {
  const agy = agyPath();
  if (!agy) {
    throw new AntigravityUnavailable(
      'Khong tim thay CLI agy cua Antigravity.',
      'Model cu the (vd gemini-4-argon-high) chi chay duoc qua agy: cai ~/.local/bin/agy hoac tro ANTIGRAVITY_PM_AGY vao dung file. KHONG tu doi sang bac flash.',
    );
  }
  return agy;
}

function assertProjectDir(cwd) {
  if (!fs.existsSync(cwd)) throw new AgentApiError(`thu muc project ${cwd} khong con ton tai (da doi ten hoac xoa?): agy khong chay duoc o do`);
}

/**
 * Chay `agy ...` tach nhom, cho den khi no in su kien `init` (co conversation_id + cwd that) roi de no chay tiep den het luot.
 * stdout+stderr vao 1 file 0600 trong agy-runs/ (dong khong phai JSON bi bo qua khi doc). Cho init ma server bi tat (SIGTERM) thi don luon nhom con.
 * onSpawn(child) goi NGAY sau spawn: noi goi ghi pid agy that vao so dang ky, de PM chet (SIGKILL) giua luc cho init van de lai dau vet dung.
 */
function agyStart(args, cwd, onSpawn) {
  const agy = requireAgy();
  assertProjectDir(cwd);
  const runsDir = ensureDir(path.join(homeStateDir(), 'agy-runs'));
  fs.chmodSync(runsDir, 0o700);
  pruneAgyRuns(runsDir);
  const outFile = path.join(runsDir, `${Date.now()}-${process.pid}-${Math.random().toString(36).slice(2, 8)}.jsonl`);
  const fd = fs.openSync(outFile, 'a', 0o600);
  let child;
  try {
    child = spawn(agy, args, { cwd, detached: true, stdio: ['ignore', fd, fd] });
  } finally {
    fs.closeSync(fd);
  }
  trackChild(child.pid);
  if (onSpawn && child.pid) {
    try { onSpawn(child); } catch (e) {
      killGroup(child.pid);   // loi = nhom da het
      untrackChild(child.pid);
      throw e;
    }
  }
  return new Promise((resolve, reject) => {
    let done = false;
    const finish = (fn, v) => {
      if (done) return;
      done = true;
      clearInterval(timer);
      clearTimeout(limit);
      untrackChild(child.pid);   // tu day tien trinh song doc lap voi server (da co conversationId de theo doi)
      child.removeAllListeners();
      child.on('error', () => { /* da tach: loi sau nay doc o file */ });
      fn(v);
    };
    const tailOf = () => { try { return truncate(redact(fs.readFileSync(outFile, 'utf8').slice(-1500)), 1500); } catch { return ''; } };
    const initEvent = () => {
      let text = '';
      try { text = fs.readFileSync(outFile, 'utf8'); } catch { return null; }
      for (const raw of text.split('\n')) {
        // chuoi con chi de loc nhanh; quyet theo object da parse (JSON co khoang trang "event": "init" cung la init)
        const line = raw.trim();
        if (!line.startsWith('{') || !line.includes('init')) continue;
        try { const j = JSON.parse(line); if (j?.event === 'init' && j.conversation_id) return j; } catch { /* dong dang ghi do */ }
      }
      return null;
    };
    const ready = (j) => ({
      conversationId: j.conversation_id, workspace: j.init?.cwd || null, pid: child.pid, pidTag: procTag(child.pid), out: outFile,
    });
    // procTag co the NEM (ps hong): trong callback cua timer / 'exit' no la uncaughtException va giet server, de agy chay khong ai theo doi.
    // Bat o day: dung agy vua mo, tu choi bang loi ro.
    const settle = (j) => {
      let r;
      try { r = ready(j); } catch (e) { stopChild(); finish(reject, e); return; }
      finish(resolve, r);
    };
    const timer = setInterval(() => {
      const j = initEvent();
      if (j) { child.unref(); settle(j); }
    }, 150);
    const stopChild = () => { if (child.pid) killGroup(child.pid); };   // loi = nhom da het
    const limit = setTimeout(() => {
      stopChild();
      finish(reject, new AgentApiError(`agy khong in su kien init sau ${AGY_INIT_WAIT_MS}ms`, tailOf()));
    }, AGY_INIT_WAIT_MS);
    child.once('error', (e) => finish(reject, new AgentApiError(`khong chay duoc agy: ${e.message}`)));
    child.once('exit', (code) => {
      const j = initEvent();   // chay xong qua nhanh: init da nam trong file
      if (j) settle(j);
      else { stopChild(); finish(reject, new AgentApiError(`agy ket thuc (exit ${code}) ma khong in su kien init`, tailOf())); }   // don ca lenh con con sot
    });
  });
}

const agyArgs = (model, tail, skipPermissions) => [
  ...tail, '--model', model, '--output-format', 'stream-json', ...(skipPermissions ? ['--dangerously-skip-permissions'] : []),
];

/** Dung luot agy vua mo ma KHONG ghi duoc so dang ky: khong de agent chay (skip-permissions) ma PM khong theo doi. */
function stopUntracked(r, e) {
  killGroup(r.pid);   // loi = nhom da het
  const err = new AgentApiError(`khong ghi duoc so dang ky agy sau khi mo luot (${e.message}): da dung agy pid ${r.pid} de khong de agent chay ma PM khong theo doi`);
  err.cause = e;
  return err;
}

async function agyNewConversation({ prompt, model, cwd }) {
  requireAgy();
  if (!cwd) throw new AgentApiError(`model ${model} chay qua agy: can cwd (thu muc project), khong doan thu muc`);
  assertProjectDir(cwd);
  const root = fs.realpathSync(cwd);
  readAgyRegistry();   // hong thi nem loi NGAY, truoc khi sinh agent: sau khi spawn khong con cach nao theo doi no
  const r = await agyStart(agyArgs(model, ['--print', String(prompt)], agyMaySkipPermissions(root)), root);
  try {
    saveAgyEntry(r.conversationId, { model, cwd: root, workspace: r.workspace, pid: r.pid, pidTag: r.pidTag, starting: false, out: r.out, at: nowIso() });
  } catch (e) { throw stopUntracked(r, e); }
  return { conversationId: r.conversationId, raw: `agy pid ${r.pid}`, parsed: { pid: r.pid, pidTag: r.pidTag, out: r.out } };
}

const busyError = (conversationId, e) => Object.assign(new AgentApiError(e.starting
  ? `hoi thoai agy ${conversationId} dang mo luot moi (PM dang cho agy khoi dong): thu lai sau vai giay.`
  : `hoi thoai agy ${conversationId} dang chay luot truoc (pid ${e.pid}): agy chi nhan tin giua hai luot. `
    + `Cho luot xong (pm_status); neu treo qua stallMinutes thi kill -- -${e.pid} (ca nhom: agy + lenh con; agy thoat = luot dung) roi gui lai, hoi thoai tiep tuc duoc.`), { code: 'AGY_TURN_BUSY' });

/**
 * Kiem tra "dang chay?" va DAT CHO la mot buoc nguyen tu: khoa file (giua cac tien trinh PM) + dong bo (trong tien trinh).
 * Cho giu: pid = chinh PM, starting = true; PM chet giua chung thi dau van tay khong con khop => tu nha. Tra ve muc TRUOC khi dat cho.
 */
function reserveTurn(conversationId) {
  const mine = selfTag();   // ps (neu chua co) TRUOC khi giu khoa
  return withRegistryLock(() => {
    const reg = readAgyRegistry();
    const e = reg[conversationId];
    if (!e) throw new AgentApiError(`hoi thoai agy ${conversationId} khong co trong so dang ky`);
    if (!e.model || !e.cwd) {
      throw new AgentApiError(`muc ${conversationId} trong ${agyRegistryFile()} thieu model/cwd (da bi duoi khoi so luc day roi ghi lai?): khong biet chay lai bang model nao, o dau`);
    }
    if (entryBusy(e)) throw busyError(conversationId, e);
    putAgyEntry(reg, conversationId, { pid: process.pid, pidTag: mine, starting: true, reservation: true, reservedAt: nowIso(), lastSentAt: nowIso() });
    return e;
  });
}

async function agySendMessage(conversationId, content) {
  requireAgy();
  const entry = reserveTurn(conversationId);
  let r = null;
  try {
    const skip = agyMaySkipPermissions(entry.cwd);
    // Khong co --model thi agy resume bang model mac dinh, khong phai model cua hoi thoai (do 14/10/2026): luon truyen model da luu.
    r = await agyStart(agyArgs(entry.model, ['--conversation', conversationId, '--print', String(content)], skip), entry.cwd,
      (child) => saveAgyEntry(conversationId, { pid: child.pid, pidTag: procTag(child.pid), starting: true, reservation: false, reservedAt: nowIso() }));
    saveAgyEntry(conversationId, { pid: r.pid, pidTag: r.pidTag, starting: false, reservation: false, out: r.out, lastSentAt: nowIso(), workspace: r.workspace || entry.workspace });
    return { ok: true, raw: `agy pid ${r.pid}`, parsed: { pid: r.pid, pidTag: r.pidTag, out: r.out } };
  } catch (e) {
    const failure = r ? stopUntracked(r, e) : e;
    try {
      saveAgyEntry(conversationId, { pid: entry.pid || null, pidTag: entry.pidTag || null, starting: false, reservation: false });   // nha cho: luot khong mo duoc
    } catch (e2) {
      logStderr(`khong nha duoc cho giu cua hoi thoai agy ${conversationId}: ${e2.message}`);   // khong che loi goc
    }
    throw failure;
  }
}

export async function newConversation({ prompt, model = 'pro', title, profile, projectId, cwd, timeoutMs = 180000 }) {
  if (!prompt || !String(prompt).trim()) throw new AgentApiError('prompt rong');
  if (model && !MODELS.includes(model)) throw new AgentApiError(`model khong hop le: ${model} (chi nhan ${MODELS.join(', ')})`);
  // agy khong co co --title / timeout: tieu de "[PM] ..." chi co o hoi thoai IDE; luot agy chay den het (khong co timeoutMs)
  if (isAgyModel(model)) return agyNewConversation({ prompt, model, cwd });
  const args = ['new-conversation'];
  if (model) args.push(`--model=${model}`);
  if (title) args.push(`--title=${title}`);
  if (profile) args.push(`--profile=${profile}`);
  args.push(String(prompt));
  const { parsed, raw } = await call(args, { timeoutMs, projectId });
  const conversationId = findConversationId(parsed);
  if (!conversationId) throw new AgentApiError('Tao conversation xong nhung khong doc ra conversationId', raw);
  return { conversationId, raw, parsed };
}

export async function sendMessage({ conversationId, content, title, projectId, timeoutMs = 120000 }) {
  if (!conversationId) throw new AgentApiError('thieu conversationId');
  if (!content || !String(content).trim()) throw new AgentApiError('noi dung tin nhan rong');
  if (agyEntryOf(conversationId)) return agySendMessage(conversationId, content);
  const args = ['send-message'];
  if (title) args.push(`--title=${title}`);
  args.push(String(conversationId), String(content));
  const { parsed, raw } = await withRegistryHint(() => call(args, { timeoutMs, projectId }));
  return { ok: true, raw, parsed };
}

export async function getConversationMetadata(conversationId) {
  const agyEntry = agyEntryOf(conversationId);
  if (agyEntry) {   // IDE khong biet hoi thoai cua agy ("trajectory not found"): workspace = thu muc ta da chay agy trong do
    return { found: true, workspace: agyEntry.workspace || agyEntry.cwd, branch: null, repo: null, createdAt: agyEntry.at || null, projectId: null, raw: 'agy' };
  }
  const { parsed, raw } = await withRegistryHint(() => call(['get-conversation-metadata', String(conversationId)], { timeoutMs: 60000 }));
  const md = parsed?.response?.conversationMetadata?.metadata || null;
  const ws = md?.workspaces?.[0] || null;
  return {
    found: Boolean(md),
    workspace: ws?.workspaceFolderAbsoluteUri
      ? decodeURI(ws.workspaceFolderAbsoluteUri).replace(/^file:\/\//, '')
      : null,
    branch: ws?.branchName || null,
    repo: ws?.repository?.computedName || null,
    createdAt: md?.createdAt || null,
    projectId: md?.projectId || null,
    raw,
  };
}

/**
 * Do tien trien cua 1 hoi thoai bang cach STAT file CSDL cua no.
 * CO Y KHONG mo file: noi dung buoc lam la protobuf rieng cua Antigravity, va ta khong
 * doc hoi thoai cua nguoi dung. Chi can biet "co dong tinh gan day khong".
 */
export function conversationProgress(conversationId) {
  const home = process.env.HOME || '';
  const dirs = [
    path.join(home, '.gemini/antigravity/conversations'),
    path.join(home, '.gemini/antigravity-ide/conversations'),
    path.join(home, '.gemini/antigravity-cli/conversations'),   // hoi thoai cua agy
  ];
  let newest = 0;
  let file = null;
  for (const d of dirs) {
    for (const suffix of ['.db', '.db-wal']) {
      const p = path.join(d, `${conversationId}${suffix}`);
      try {
        const st = fs.statSync(p);
        if (st.mtimeMs > newest) { newest = st.mtimeMs; file = p; }
      } catch { /* khong co thi thoi */ }
    }
  }
  // Transcript cua brain la tin hieu that hon CSDL (de xuat Unity 14/09/2026): stat mtime.
  const tr = transcriptPath(conversationId);
  try {
    const st = fs.statSync(tr);
    if (st.mtimeMs > newest) { newest = st.mtimeMs; file = tr; }
  } catch { /* khong co */ }
  if (!newest) return { found: false, lastActivityAt: null, idleMinutes: null, file: null };
  return {
    found: true,
    lastActivityAt: new Date(newest).toISOString(),
    idleMinutes: Math.round((Date.now() - newest) / 60000),
    file,
  };
}

function transcriptPath(conversationId) {
  const home = process.env.HOME || '';
  const cands = ['.gemini/antigravity-cli', '.gemini/antigravity']   // agy truoc: id cua hai ben la UUID rieng, khong trung
    .map((d) => path.join(home, d, 'brain', conversationId, '.system_generated/logs/transcript.jsonl'));
  return cands.find((c) => fs.existsSync(c)) || cands[cands.length - 1];
}

/**
 * Loi stream trong transcript: dem dong `"type":"ERROR_MESSAGE"` o DUOI file (64 KB cuoi) va xem buoc cuoi co phai loi khong.
 * NGOAI LE co chu dich cua luat "khong mo noi dung hoi thoai": chi lay hai truong type + created_at, KHONG tra ve content.
 * Vi sao (Unity T0007, 14/09/2026): 3/6 vong phan bien treo vi "The stream was interrupted" — stallMinutes chi dem im lang, khong thay.
 */
export function transcriptErrors(conversationId) {
  const tr = transcriptPath(conversationId);
  let fd;
  try {
    const st = fs.statSync(tr);
    const len = Math.min(st.size, 65536);
    const buf = Buffer.alloc(len);
    fd = fs.openSync(tr, 'r');
    fs.readSync(fd, buf, 0, len, st.size - len);
    const lines = buf.toString('utf8').split('\n').filter((l) => l.trim());
    const errs = lines.filter((l) => l.includes('"type":"ERROR_MESSAGE"'));
    const last = lines[lines.length - 1] || '';
    const at = (l) => /"created_at":"([^"]+)"/.exec(l)?.[1] || null;
    return {
      found: true,
      errorCount: errs.length,
      lastErrorAt: errs.length ? at(errs[errs.length - 1]) : null,
      lastStepIsError: last.includes('"type":"ERROR_MESSAGE"'),
    };
  } catch {
    return { found: false, errorCount: 0, lastErrorAt: null, lastStepIsError: false };
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}

export { AntigravityUnavailable };
