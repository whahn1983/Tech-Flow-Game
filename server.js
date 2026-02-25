const http = require('http');
const fs = require('fs');
const path = require('path');

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
const LEADERBOARD_FILE = path.join(__dirname, 'leaderboard.txt');
const MAX_ENTRIES = 100;
const MAX_SCORE = 999999;
const MAX_NAME_LENGTH = 24;
const MAX_PAYLOAD_BYTES = 10240; // 10 KB — name + score never exceeds a few hundred bytes

// Rate limiting: max 5 POST submissions per IP per 60 seconds (in-memory).
const RATE_LIMIT_MAX = 5;
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const rateLimitStore = new Map(); // ip -> [timestamps]

// Prune stale rate-limit entries every minute to prevent unbounded memory growth.
setInterval(() => {
  const cutoff = Date.now() - RATE_LIMIT_WINDOW_MS;
  for (const [ip, timestamps] of rateLimitStore) {
    const filtered = timestamps.filter((ts) => ts > cutoff);
    if (filtered.length === 0) {
      rateLimitStore.delete(ip);
    } else {
      rateLimitStore.set(ip, filtered);
    }
  }
}, 60 * 1000);

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
  '.txt': 'text/plain; charset=utf-8'
};

// Security headers sent on every response.
const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'strict-origin-when-cross-origin'
};

// CSP for HTML pages: allow same-origin resources plus inline scripts/styles (required by the
// single-file game). frame-ancestors replaces X-Frame-Options for modern browsers.
const HTML_CSP = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "media-src 'self'",
  "connect-src 'self'",
  "worker-src 'self'",
  "frame-ancestors 'none'"
].join('; ');

// CSP for JSON API responses: no sub-resources allowed.
const API_CSP = "default-src 'none'";

function ensureLeaderboardFile() {
  if (!fs.existsSync(LEADERBOARD_FILE)) {
    fs.writeFileSync(LEADERBOARD_FILE, '', { encoding: 'utf8', mode: 0o644 });
  }
}

function readLeaderboard() {
  ensureLeaderboardFile();
  const raw = fs.readFileSync(LEADERBOARD_FILE, 'utf8').trim();
  if (!raw) return [];

  return raw
    .split('\n')
    .map((line) => {
      const [name, score, savedAt] = line.split('|');
      return {
        name: (name || '').trim(),
        score: Number(score || 0),
        savedAt: savedAt || new Date(0).toISOString()
      };
    })
    .filter((entry) => entry.name && Number.isFinite(entry.score));
}

function writeLeaderboard(entries) {
  const rows = entries.map((entry) => `${entry.name}|${Math.floor(entry.score)}|${entry.savedAt}`);
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

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Security-Policy': API_CSP,
    ...SECURITY_HEADERS
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

function handleApi(req, res) {
  if (req.url === '/api/leaderboard' && req.method === 'GET') {
    const entries = sortedLeaderboard(readLeaderboard());
    sendJson(res, 200, { entries });
    return true;
  }

  if (req.url === '/api/leaderboard' && req.method === 'POST') {
    const ip = getClientIp(req);
    if (!checkRateLimit(ip)) {
      sendJson(res, 429, { error: 'Too many requests. Please wait before submitting again.' });
      return true;
    }

    parseBody(req)
      .then((body) => {
        const name = cleanPlayerName(body.name);
        const score = Number(body.score);

        if (!name) {
          sendJson(res, 400, { error: 'Player name is required.' });
          return;
        }

        if (!Number.isFinite(score) || !Number.isInteger(score) || score < 0 || score > MAX_SCORE) {
          sendJson(res, 400, { error: 'Score must be a whole number between 0 and 999999.' });
          return;
        }

        const savedAt = new Date().toISOString();
        const entries = sortedLeaderboard([
          ...readLeaderboard(),
          { name, score, savedAt }
        ]);

        writeLeaderboard(entries);
        sendJson(res, 201, { entries, saved: { name, score, savedAt } });
      })
      .catch((error) => {
        sendJson(res, 400, { error: error.message });
      });
    return true;
  }

  return false;
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
    const contentType = (basename === 'manifest.json'
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

server.listen(PORT, HOST, () => {
  ensureLeaderboardFile();
  console.log(`Tech Flow Runner server listening on http://${HOST}:${PORT}`);
});
