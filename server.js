const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Validate PORT is in the acceptable range for non-privileged listening.
const PORT = (() => {
  const p = parseInt(process.env.PORT || '8080', 10);
  if (isNaN(p) || p < 1024 || p > 65535) {
    console.error('Invalid PORT. Must be 1024–65535. Defaulting to 8080.');
    return 8080;
  }
  return p;
})();

const HOST = '0.0.0.0';
const PUBLIC_DIR = __dirname;
// Persisted state lives in a writable directory mounted via Docker so the
// app's read-only root filesystem doesn't block writes. Override paths via
// LEADERBOARD_FILE / DAILY_SEED_FILE / NONCE_FILE for non-Docker deployments.
const DATA_DIR = process.env.DATA_DIR || '/app/data';
const LEADERBOARD_FILE = process.env.LEADERBOARD_FILE || path.join(DATA_DIR, 'leaderboard.txt');
const DAILY_SEED_FILE = process.env.DAILY_SEED_FILE || path.join(DATA_DIR, 'dailyseed.txt');
const NONCE_FILE = process.env.NONCE_FILE || path.join(DATA_DIR, 'nonces.txt');
const MAX_ENTRIES = 100;
const MAX_PER_CATEGORY = 10;
const MAX_DAILY_ENTRIES = 10;
const MAX_SCORE = 999999;
const DAILY_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MAX_NAME_LENGTH = 24;
const MAX_PAYLOAD_BYTES = 10240; // 10 KB — name + score never exceeds a few hundred bytes

// Modifier categories. 'og' is reserved for legacy entries from the original
// distance-only scoring system; everything else maps to a current run modifier.
const VALID_MODIFIERS = ['og', 'none', 'hardcore', 'bitrush', 'featherfall', 'glasscannon'];

// CORS allowlist. Defaults to same-origin only. Set ALLOWED_ORIGINS to a
// comma-separated list of origins to permit cross-origin API access.
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .map((value) => value.trim())
  .filter(Boolean);

// Rate limiting: max 5 POST submissions per IP per 60 seconds (in-memory).
const RATE_LIMIT_MAX = 5;
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const rateLimitStore = new Map(); // ip -> [timestamps]

// Nonce store: nonce -> issuedAt (ms epoch). Adds a required round-trip before
// score submissions to deter trivial scripted spam.
const NONCE_LIFETIME_MS = 10 * 60 * 1000;
const NONCE_MIN_AGE_MS = 4 * 1000;
const NONCE_MAX_TRACKED = 4096;
const nonceStore = new Map();

// Prune stale rate-limit and nonce entries every minute. unref() so the timer
// alone doesn't keep Node alive (lets test runners exit cleanly).
const pruneTimer = setInterval(() => {
  const cutoff = Date.now() - RATE_LIMIT_WINDOW_MS;
  for (const [ip, timestamps] of rateLimitStore) {
    const filtered = timestamps.filter((ts) => ts > cutoff);
    if (filtered.length === 0) {
      rateLimitStore.delete(ip);
    } else {
      rateLimitStore.set(ip, filtered);
    }
  }

  const nonceCutoff = Date.now() - NONCE_LIFETIME_MS;
  let prunedAny = false;
  for (const [nonce, ts] of nonceStore) {
    if (ts < nonceCutoff) {
      nonceStore.delete(nonce);
      prunedAny = true;
    }
  }
  if (prunedAny) persistNonceStore();
}, 60 * 1000);
pruneTimer.unref();

function checkRateLimit(ip) {
  const now = Date.now();
  const cutoff = now - RATE_LIMIT_WINDOW_MS;
  const timestamps = (rateLimitStore.get(ip) || []).filter((ts) => ts > cutoff);
  if (timestamps.length >= RATE_LIMIT_MAX) {
    rateLimitStore.set(ip, timestamps);
    return false;
  }
  timestamps.push(now);
  rateLimitStore.set(ip, timestamps);
  return true;
}

function issueNonce() {
  const nonce = crypto.randomBytes(16).toString('hex');
  nonceStore.set(nonce, Date.now());
  // Hard cap to keep memory bounded even under abusive requestors.
  if (nonceStore.size > NONCE_MAX_TRACKED) {
    const oldestNonce = nonceStore.keys().next().value;
    if (oldestNonce !== undefined) nonceStore.delete(oldestNonce);
  }
  persistNonceStore();
  return nonce;
}

function consumeNonce(nonce) {
  if (typeof nonce !== 'string' || !/^[0-9a-f]+$/i.test(nonce)) return false;
  const issuedAt = nonceStore.get(nonce);
  if (issuedAt === undefined) return false;
  nonceStore.delete(nonce);
  persistNonceStore();
  const now = Date.now();
  if (now - issuedAt > NONCE_LIFETIME_MS) return false;
  if (now - issuedAt < NONCE_MIN_AGE_MS) return false;
  return true;
}

function loadNonceStore() {
  try {
    if (!fs.existsSync(NONCE_FILE)) return;
    const raw = fs.readFileSync(NONCE_FILE, 'utf8').trim();
    if (!raw) return;
    const cutoff = Date.now() - NONCE_LIFETIME_MS;
    for (const line of raw.split('\n')) {
      const [nonce, tsRaw] = line.split('|');
      if (!nonce || !/^[0-9a-f]+$/i.test(nonce)) continue;
      const issuedAt = Number(tsRaw);
      if (!Number.isFinite(issuedAt) || issuedAt < cutoff) continue;
      nonceStore.set(nonce, issuedAt);
    }
  } catch (error) {
    console.error('Failed to load nonce store:', error.message);
  }
}

function persistNonceStore() {
  try {
    ensureDataDir();
    const lines = [];
    for (const [nonce, ts] of nonceStore) {
      lines.push(`${nonce}|${ts}`);
    }
    fs.writeFileSync(NONCE_FILE, lines.join('\n'), { encoding: 'utf8', mode: 0o644 });
  } catch (error) {
    console.error('Failed to persist nonce store:', error.message);
  }
}

loadNonceStore();

function getClientIp(req) {
  // Only use the socket's remote address; never trust X-Forwarded-For without a verified proxy.
  return req.socket.remoteAddress || '0.0.0.0';
}

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.mp3': 'audio/mpeg',
  '.txt': 'text/plain; charset=utf-8',
};

// Security headers sent on every response.
const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
};

// CSP for HTML pages: scripts/styles are now in external files. style-src keeps
// 'unsafe-inline' because the game manipulates element.style at runtime.
const HTML_CSP = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "media-src 'self'",
  "connect-src 'self'",
  "worker-src 'self'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join('; ');

// CSP for JSON API responses: no sub-resources allowed.
const API_CSP = "default-src 'none'";

function ensureDataDir() {
  const dir = path.dirname(LEADERBOARD_FILE);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true, mode: 0o755 });
  }
}

function ensureLeaderboardFile() {
  ensureDataDir();
  if (!fs.existsSync(LEADERBOARD_FILE)) {
    fs.writeFileSync(LEADERBOARD_FILE, '', { encoding: 'utf8', mode: 0o644 });
  }
}

function todayUtcStamp() {
  const d = new Date();
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function seedFromDateStamp(stamp) {
  // Deterministic 31-bit seed derived from the date string. Same date -> same
  // seed across processes / restarts; different dates -> different seeds.
  const hash = crypto.createHash('sha256').update(stamp).digest();
  return hash.readUInt32BE(0) & 0x7fffffff || 1;
}

function readDailySeed() {
  const today = todayUtcStamp();
  ensureDataDir();
  if (fs.existsSync(DAILY_SEED_FILE)) {
    try {
      const raw = fs.readFileSync(DAILY_SEED_FILE, 'utf8').trim();
      const [storedDate, storedSeed] = raw.split('|');
      if (storedDate === today) {
        const parsed = Number(storedSeed);
        if (Number.isFinite(parsed) && Number.isInteger(parsed) && parsed > 0) {
          return { date: storedDate, seed: parsed };
        }
      }
    } catch {
      // Fall through to regenerate.
    }
  }
  const seed = seedFromDateStamp(today);
  try {
    fs.writeFileSync(DAILY_SEED_FILE, `${today}|${seed}`, { encoding: 'utf8', mode: 0o644 });
  } catch (error) {
    console.error('Failed to persist daily seed:', error.message);
  }
  return { date: today, seed };
}

function readLeaderboard() {
  ensureLeaderboardFile();
  const raw = fs.readFileSync(LEADERBOARD_FILE, 'utf8').trim();
  if (!raw) return [];

  return raw
    .split('\n')
    .map((line) => {
      const [name, score, savedAt, modifier, daily, seedDate] = line.split('|');
      // Optional 4th field: modifier. Legacy rows are categorized as 'og'.
      const normalizedModifier =
        modifier && VALID_MODIFIERS.includes(modifier.trim()) ? modifier.trim() : 'og';
      // Optional 5th/6th fields: daily flag + seed date. Legacy rows default to false/''.
      const normalizedDaily = String(daily || '').trim() === '1';
      const rawSeedDate = String(seedDate || '').trim();
      const normalizedSeedDate =
        normalizedDaily && DAILY_DATE_PATTERN.test(rawSeedDate) ? rawSeedDate : '';
      return {
        name: (name || '').trim(),
        score: Number(score || 0),
        savedAt: savedAt || new Date(0).toISOString(),
        modifier: normalizedModifier,
        daily: normalizedDaily && normalizedSeedDate !== '',
        seedDate: normalizedSeedDate,
      };
    })
    .filter((entry) => entry.name && Number.isFinite(entry.score));
}

function writeLeaderboard(entries) {
  const rows = entries.map((entry) => {
    const modifier = VALID_MODIFIERS.includes(entry.modifier) ? entry.modifier : 'og';
    const daily = entry.daily && DAILY_DATE_PATTERN.test(entry.seedDate || '') ? '1' : '0';
    const seedDate = daily === '1' ? entry.seedDate : '';
    return `${entry.name}|${Math.floor(entry.score)}|${entry.savedAt}|${modifier}|${daily}|${seedDate}`;
  });
  fs.writeFileSync(LEADERBOARD_FILE, rows.join('\n'), { encoding: 'utf8', mode: 0o644 });
}

function sortedLeaderboard(entries) {
  return [...entries]
    .sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return new Date(a.savedAt).getTime() - new Date(b.savedAt).getTime();
    })
    .slice(0, MAX_ENTRIES);
}

// Group entries by modifier, sort each bucket, and trim to MAX_PER_CATEGORY.
// Categories with no entries still appear (as []) so the client can render a
// consistent set of sections.
function categorizeLeaderboard(entries) {
  const buckets = {};
  for (const modifier of VALID_MODIFIERS) {
    buckets[modifier] = [];
  }
  for (const entry of entries) {
    const modifier = VALID_MODIFIERS.includes(entry.modifier) ? entry.modifier : 'og';
    buckets[modifier].push(entry);
  }
  for (const modifier of VALID_MODIFIERS) {
    buckets[modifier].sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return new Date(a.savedAt).getTime() - new Date(b.savedAt).getTime();
    });
    buckets[modifier] = buckets[modifier].slice(0, MAX_PER_CATEGORY);
  }
  return buckets;
}

function flattenCategories(categories) {
  const flat = [];
  for (const modifier of VALID_MODIFIERS) {
    for (const entry of categories[modifier] || []) {
      flat.push(entry);
    }
  }
  return flat;
}

// Top scores for a given daily-seed date, across all modifier categories.
// Used to render the dedicated "Daily Seed" section above the modifier
// leaderboards. Caller passes the date stamp (UTC, YYYY-MM-DD) of the
// currently-active daily seed.
function dailyLeaderboard(entries, seedDate) {
  if (!DAILY_DATE_PATTERN.test(String(seedDate || ''))) return [];
  return entries
    .filter((entry) => entry.daily && entry.seedDate === seedDate)
    .sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return new Date(a.savedAt).getTime() - new Date(b.savedAt).getTime();
    })
    .slice(0, MAX_DAILY_ENTRIES);
}

function corsHeadersFor(req) {
  const origin = req.headers.origin;
  if (!origin || !ALLOWED_ORIGINS.includes(origin)) return {};
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '600',
    Vary: 'Origin',
  };
}

function sendJson(res, statusCode, payload, req) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Security-Policy': API_CSP,
    ...SECURITY_HEADERS,
    ...(req ? corsHeadersFor(req) : {}),
  });
  res.end(body);
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > MAX_PAYLOAD_BYTES) {
        reject(new Error('Payload too large'));
        req.destroy();
      }
    });
    req.on('end', () => {
      if (!data) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(data));
      } catch {
        reject(new Error('Invalid JSON payload'));
      }
    });
    req.on('error', reject);
  });
}

function cleanPlayerName(rawName) {
  // Allow only printable ASCII: letters, digits, spaces, and a limited punctuation set.
  return String(rawName || '')
    .replace(/[^a-zA-Z0-9 .'\-_!?@#*()+]/g, '')
    .trim()
    .slice(0, MAX_NAME_LENGTH);
}

function handleLeaderboardGet(req, res, parsedUrl) {
  if (parsedUrl.searchParams.get('action') === 'nonce') {
    sendJson(res, 200, { nonce: issueNonce() }, req);
    return;
  }
  const allEntries = readLeaderboard();
  const categories = categorizeLeaderboard(allEntries);
  const todayDate = todayUtcStamp();
  const daily = {
    date: todayDate,
    entries: dailyLeaderboard(allEntries, todayDate),
  };
  // `entries` is retained as a flat list for older clients; `categories` holds
  // the per-modifier top-10 buckets used by the current UI; `daily` holds the
  // top scores for today's daily seed across all modifiers.
  sendJson(res, 200, { categories, daily, entries: flattenCategories(categories) }, req);
}

function handleLeaderboardPost(req, res) {
  const ip = getClientIp(req);
  if (!checkRateLimit(ip)) {
    sendJson(res, 429, { error: 'Too many requests. Please wait before submitting again.' }, req);
    return;
  }

  parseBody(req)
    .then((body) => {
      const name = cleanPlayerName(body.name);
      // Accept either `points` (current clients) or `score` (legacy field name).
      const rawScore = body.points !== undefined ? body.points : body.score;
      const score = Number(rawScore);
      const nonce = typeof body.nonce === 'string' ? body.nonce : '';
      const modifier = typeof body.modifier === 'string' ? body.modifier : 'none';
      const daily = body.daily === true;
      const seedDate = typeof body.seedDate === 'string' ? body.seedDate.trim() : '';

      if (!name) {
        sendJson(res, 400, { error: 'Player name is required.' }, req);
        return;
      }

      if (!Number.isFinite(score) || !Number.isInteger(score) || score < 0 || score > MAX_SCORE) {
        sendJson(res, 400, { error: 'Score must be a whole number between 0 and 999999.' }, req);
        return;
      }

      // Modifier must be one of the known categories. 'og' is reserved for
      // legacy migration and rejected on direct submission.
      if (!VALID_MODIFIERS.includes(modifier) || modifier === 'og') {
        sendJson(res, 400, { error: 'Unknown run modifier.' }, req);
        return;
      }

      // Daily-seed runs must be tagged with the seed's date stamp. Reject
      // mismatched (daily without date, date without daily, or wrong date)
      // submissions so the daily section can't be polluted with bogus seeds.
      if (daily) {
        if (!DAILY_DATE_PATTERN.test(seedDate)) {
          sendJson(res, 400, { error: 'Daily-seed submissions require a valid seedDate.' }, req);
          return;
        }
        if (seedDate !== todayUtcStamp()) {
          sendJson(
            res,
            400,
            { error: 'Daily seed has rolled over. Reload to play today’s seed.' },
            req
          );
          return;
        }
      } else if (seedDate !== '') {
        sendJson(res, 400, { error: 'seedDate is only allowed on daily runs.' }, req);
        return;
      }

      // Nonce is mandatory. Score submissions must obtain a single-use nonce
      // via GET ?action=nonce and present it here.
      if (!consumeNonce(nonce)) {
        sendJson(res, 400, { error: 'Submission expired or invalid. Please try again.' }, req);
        return;
      }

      const savedAt = new Date().toISOString();
      const newEntry = { name, score, savedAt, modifier, daily, seedDate: daily ? seedDate : '' };
      const allEntries = [...readLeaderboard(), newEntry];
      const categories = categorizeLeaderboard(allEntries);
      const flatCategoryEntries = flattenCategories(categories);
      // Persist the union of category top-N and the daily top-N so a daily
      // entry that doesn't crack its modifier's top-10 is still retained
      // for the daily section.
      const dailyEntries = dailyLeaderboard(allEntries, todayUtcStamp());
      const persistKey = (entry) =>
        `${entry.name}|${entry.score}|${entry.savedAt}|${entry.modifier}`;
      const persistMap = new Map();
      for (const entry of [...flatCategoryEntries, ...dailyEntries]) {
        persistMap.set(persistKey(entry), entry);
      }
      const entries = Array.from(persistMap.values());

      writeLeaderboard(entries);
      sendJson(
        res,
        201,
        {
          categories,
          daily: { date: todayUtcStamp(), entries: dailyEntries },
          entries: flatCategoryEntries,
          saved: {
            name,
            score,
            points: score,
            savedAt,
            modifier,
            daily,
            seedDate: daily ? seedDate : '',
          },
        },
        req
      );
    })
    .catch((error) => {
      sendJson(res, 400, { error: error.message }, req);
    });
}

function isLeaderboardPath(pathname) {
  return pathname === '/api/leaderboard' || pathname === '/leaderboard.php';
}

function isDailySeedPath(pathname) {
  return pathname === '/api/daily-seed';
}

function handleDailySeedGet(req, res) {
  try {
    const { date, seed } = readDailySeed();
    sendJson(res, 200, { date, seed }, req);
  } catch (error) {
    sendJson(res, 500, { error: 'Daily seed unavailable.' }, req);
    console.error('Daily seed error:', error.message);
  }
}

function handleCorsPreflight(req, res) {
  const cors = corsHeadersFor(req);
  if (Object.keys(cors).length === 0) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8', ...SECURITY_HEADERS });
    res.end('Forbidden');
    return;
  }
  res.writeHead(204, { ...SECURITY_HEADERS, ...cors });
  res.end();
}

function handleApi(req, res) {
  const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = parsedUrl.pathname;

  if (isDailySeedPath(pathname)) {
    if (req.method === 'OPTIONS') {
      handleCorsPreflight(req, res);
      return true;
    }
    if (req.method === 'GET') {
      handleDailySeedGet(req, res);
      return true;
    }
    res.writeHead(405, {
      Allow: 'GET, OPTIONS',
      'Content-Type': 'application/json; charset=utf-8',
      ...SECURITY_HEADERS,
    });
    res.end(JSON.stringify({ error: 'Method not allowed.' }));
    return true;
  }

  if (!isLeaderboardPath(pathname)) return false;

  if (req.method === 'OPTIONS') {
    handleCorsPreflight(req, res);
    return true;
  }

  if (req.method === 'GET') {
    handleLeaderboardGet(req, res, parsedUrl);
    return true;
  }

  if (req.method === 'POST') {
    handleLeaderboardPost(req, res);
    return true;
  }

  // Path matched but method is not allowed — explicit 405 instead of 404.
  res.writeHead(405, {
    Allow: 'GET, POST, OPTIONS',
    'Content-Type': 'application/json; charset=utf-8',
    ...SECURITY_HEADERS,
  });
  res.end(JSON.stringify({ error: 'Method not allowed.' }));
  return true;
}

function serveStatic(req, res) {
  const requestedPath = req.url === '/' ? '/index.html' : req.url;
  const safePath = path.normalize(decodeURIComponent(requestedPath)).replace(/^\.\.(\/|\\|$)+/, '');
  const absolutePath = path.join(PUBLIC_DIR, safePath);

  if (!absolutePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8', ...SECURITY_HEADERS });
    res.end('Forbidden');
    return;
  }

  fs.stat(absolutePath, (statError, stats) => {
    if (statError || !stats.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8', ...SECURITY_HEADERS });
      res.end('Not found');
      return;
    }

    const ext = path.extname(absolutePath).toLowerCase();
    const basename = path.basename(absolutePath);
    const contentType =
      (basename === 'manifest.json'
        ? 'application/manifest+json; charset=utf-8'
        : MIME_TYPES[ext]) || 'application/octet-stream';
    const isHtml = ext === '.html';

    const headers = { 'Content-Type': contentType, ...SECURITY_HEADERS };
    if (isHtml) {
      headers['Content-Security-Policy'] = HTML_CSP;
    }

    res.writeHead(200, headers);
    fs.createReadStream(absolutePath).pipe(res);
  });
}

const server = http.createServer((req, res) => {
  if (handleApi(req, res)) return;
  serveStatic(req, res);
});

if (require.main === module) {
  server.listen(PORT, HOST, () => {
    ensureLeaderboardFile();
    console.log(`Tech Flow Runner server listening on http://${HOST}:${PORT}`);
  });
}

module.exports = {
  cleanPlayerName,
  checkRateLimit,
  issueNonce,
  consumeNonce,
  sortedLeaderboard,
  categorizeLeaderboard,
  flattenCategories,
  dailyLeaderboard,
  VALID_MODIFIERS,
  isLeaderboardPath,
  isDailySeedPath,
  seedFromDateStamp,
  todayUtcStamp,
  handleApi,
  server,
  // Exposed for tests to inspect/reset internal state.
  _state: { rateLimitStore, nonceStore },
};
