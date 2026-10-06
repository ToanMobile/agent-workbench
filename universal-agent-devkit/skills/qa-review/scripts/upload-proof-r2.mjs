#!/usr/bin/env node
/**
 * upload-proof-r2.mjs — Đẩy ảnh screenshot nghiệm thu (Android/iOS/Unity Game) lên Cloudflare R2.
 * Zero-dependency: Ký AWS SigV4 thuần bằng node:crypto, không cần @aws-sdk hay wrangler.
 *
 * Cách dùng:
 *   node .agents/skills/qa-review/scripts/upload-proof-r2.mjs                      # Tự tìm ảnh mới nhất trong reports/
 *   node .agents/skills/qa-review/scripts/upload-proof-r2.mjs reports/proof-123.png # Chỉ định file ảnh cụ thể
 *   node .agents/skills/qa-review/scripts/upload-proof-r2.mjs --help
 *
 * Credential được đọc theo thứ tự ưu tiên:
 *   1. Biến môi trường (R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY)
 *   2. File .env của project hiện tại
 *   3. File ~/.claude/qa-skill/.env (dùng chung cho mọi project trên máy)
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import process from 'node:process';
import { execFileSync } from 'node:child_process';

const DEFAULT_R2 = {
  endpoint: 'https://2210faeff2d8e1c3d1f7ae5efbd35d4f.r2.cloudflarestorage.com',
  bucket: 'finos-qa-screenshots',
  publicBaseUrl: 'https://pub-d57f89f936224835963c361c8f455058.r2.dev',
};

// ==================== AWS SigV4 Engine (Zero-dep) ====================

const ALGORITHM = 'AWS4-HMAC-SHA256';
const sha256Hex = (data) => crypto.createHash('sha256').update(data).digest('hex');
const hmac = (key, data) => crypto.createHmac('sha256', key).update(data).digest();

function amzDates(date = new Date()) {
  const amzDate = date.toISOString().replace(/[:-]|\.\d{3}/g, '');
  return { amzDate, dateStamp: amzDate.slice(0, 8) };
}

function encodePath(pathname) {
  return pathname
    .split('/')
    .map((seg) => encodeURIComponent(seg).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`))
    .join('/');
}

function signRequest({
  method,
  url,
  body = '',
  headers = {},
  accessKeyId,
  secretAccessKey,
  region = 'auto',
  service = 's3',
  date = new Date(),
}) {
  const parsed = new URL(url);
  const { amzDate, dateStamp } = amzDates(date);
  const payloadHash = sha256Hex(body);

  const all = {
    ...headers,
    host: parsed.host,
    'x-amz-content-sha256': payloadHash,
    'x-amz-date': amzDate,
  };

  const names = Object.keys(all).map((k) => k.toLowerCase()).sort();
  const lower = Object.fromEntries(Object.entries(all).map(([k, v]) => [k.toLowerCase(), String(v).trim()]));
  const canonicalHeaders = `${names.map((n) => `${n}:${lower[n]}`).join('\n')}\n`;
  const signedHeaders = names.join(';');

  const query = [...parsed.searchParams.entries()]
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');

  const canonicalRequest = [
    method,
    encodePath(parsed.pathname),
    query,
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');

  const scope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = [ALGORITHM, amzDate, scope, sha256Hex(canonicalRequest)].join('\n');

  const signingKey = [dateStamp, region, service, 'aws4_request'].reduce(
    (key, part) => hmac(key, part),
    `AWS4${secretAccessKey}`
  );
  const signature = hmac(signingKey, stringToSign).toString('hex');

  return {
    ...all,
    Authorization: `${ALGORITHM} Credential=${accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`,
  };
}

function objectUrl(endpoint, bucket, key) {
  const base = endpoint.replace(/\/+$/, '');
  return `${base}/${bucket}/${key.replace(/^\/+/, '')}`;
}

// ==================== Helpers ====================

function parseEnv(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const res = {};
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq > 0) {
      let val = trimmed.slice(eq + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      res[trimmed.slice(0, eq).trim()] = val;
    }
  }
  return res;
}

function git(args, fallback = '') {
  try {
    return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return fallback;
  }
}

function slug(text) {
  return (text || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'unknown';
}

function findLatestProof(dir) {
  if (!fs.existsSync(dir)) return null;
  const files = fs.readdirSync(dir)
    .filter((f) => f.startsWith('proof-') && f.endsWith('.png'))
    .map((f) => path.join(dir, f))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  return files.length ? files[0] : null;
}

// ==================== Main ====================

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('-h') || args.includes('--help')) {
    console.log(`
Cách dùng:
  node upload-proof-r2.mjs [đường_dẫn_ảnh.png]

Tự tìm ảnh proof mới nhất trong thư mục reports/ nếu không truyền đường dẫn.
`);
    process.exit(0);
  }

  // 1. Tìm file ảnh
  let targetFile = args.find((a) => !a.startsWith('-'));
  if (!targetFile) {
    targetFile = findLatestProof('reports') || findLatestProof('.');
  }

  if (!targetFile || !fs.existsSync(targetFile)) {
    console.error(`LỖI: Không tìm thấy file ảnh để upload. Hãy truyền đường dẫn ảnh hoặc đảm bảo có reports/proof-*.png.`);
    process.exit(1);
  }

  // 2. Nạp credentials
  const globalEnv = parseEnv(path.join(process.env.HOME || '', '.claude', 'qa-skill', '.env'));
  const localEnv = parseEnv(path.join(process.cwd(), '.env'));

  const accessKeyId = process.env.R2_ACCESS_KEY_ID || localEnv.R2_ACCESS_KEY_ID || globalEnv.R2_ACCESS_KEY_ID;
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY || localEnv.R2_SECRET_ACCESS_KEY || globalEnv.R2_SECRET_ACCESS_KEY;
  const bucket = process.env.R2_BUCKET || localEnv.R2_BUCKET || globalEnv.R2_BUCKET || DEFAULT_R2.bucket;
  const endpoint = process.env.R2_ENDPOINT || localEnv.R2_ENDPOINT || globalEnv.R2_ENDPOINT || DEFAULT_R2.endpoint;
  const publicBaseUrl = process.env.R2_PUBLIC_BASE_URL || localEnv.R2_PUBLIC_BASE_URL || globalEnv.R2_PUBLIC_BASE_URL || DEFAULT_R2.publicBaseUrl;

  if (!accessKeyId || !secretAccessKey) {
    console.error(`
[CẢNH BÁO] Chưa cấu hình Cloudflare R2 Credentials!
Cần R2_ACCESS_KEY_ID và R2_SECRET_ACCESS_KEY.
Bạn có thể cấu hình nhanh tại:
  1. File .env trong project này
  2. Hoặc file ~/.claude/qa-skill/.env (dùng chung cho mọi repo)
`);
    process.exit(1);
  }

  // 3. Xây dựng Key R2
  const repo = slug(git(['remote', 'get-url', 'origin']).replace(/\.git$/, '').split(/[/:]/).pop()) || slug(path.basename(process.cwd()));
  const branch = slug(git(['rev-parse', '--abbrev-ref', 'HEAD'], 'main'));
  const sha = git(['rev-parse', '--short', 'HEAD'], 'worktree');
  const filename = path.basename(targetFile);

  const r2Key = `${repo}/${branch}/${sha}/${filename}`;
  const targetUrl = objectUrl(endpoint, bucket, r2Key);
  const fileBytes = fs.readFileSync(targetFile);

  console.log(`Đang upload: ${targetFile} (${(fileBytes.length / 1024).toFixed(1)} KB) -> R2...`);

  const ext = path.extname(targetFile).toLowerCase();
  const contentType = ext === '.jpg' || ext === '.jpeg' ? 'image/jpeg' : ext === '.webp' ? 'image/webp' : 'image/png';

  // 4. Ký và PUT lên R2
  const signedHeaders = signRequest({
    method: 'PUT',
    url: targetUrl,
    body: fileBytes,
    headers: {
      'content-type': contentType,
      'content-length': String(fileBytes.length),
      'cache-control': 'public, max-age=31536000, immutable',
    },
    accessKeyId,
    secretAccessKey,
  });

  const res = await fetch(targetUrl, {
    method: 'PUT',
    headers: signedHeaders,
    body: fileBytes,
  });

  if (!res.ok) {
    const errorText = await res.text();
    console.error(`Upload thất bại! HTTP ${res.status}: ${errorText.slice(0, 300)}`);
    process.exit(1);
  }

  const publicUrl = `${publicBaseUrl.replace(/\/+$/, '')}/${r2Key}`;
  console.log(`\nTHÀNH CÔNG!`);
  console.log(`URL: ${publicUrl}`);
  console.log(`Markdown: ![Ảnh nghiệm thu](${publicUrl})`);
}

main().catch((err) => {
  console.error(`Lỗi: ${err.message}`);
  process.exit(1);
});
