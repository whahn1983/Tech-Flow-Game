const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 8080;
const HOST = '0.0.0.0';
const PUBLIC_DIR = __dirname;
const LEADERBOARD_FILE = path.join(__dirname, 'leaderboard.txt');
const MAX_ENTRIES = 25;

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.mp3': 'audio/mpeg',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8'
};

function ensureLeaderboardFile() {
  if (!fs.existsSync(LEADERBOARD_FILE)) {
    fs.writeFileSync(LEADERBOARD_FILE, '', 'utf8');
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
  fs.writeFileSync(LEADERBOARD_FILE, rows.join('\n'), 'utf8');
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
    'Cache-Control': 'no-store'
  });
  res.end(body);
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 1e6) {
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
  return String(rawName || '')
    .replace(/[\r\n|]+/g, ' ')
    .trim()
    .slice(0, 24);
}

function handleApi(req, res) {
  if (req.url === '/api/leaderboard' && req.method === 'GET') {
    const entries = sortedLeaderboard(readLeaderboard());
    sendJson(res, 200, { entries });
    return true;
  }

  if (req.url === '/api/leaderboard' && req.method === 'POST') {
    parseBody(req)
      .then((body) => {
        const name = cleanPlayerName(body.name);
        const score = Number(body.score);

        if (!name) {
          sendJson(res, 400, { error: 'Player name is required.' });
          return;
        }

        if (!Number.isFinite(score) || score < 0) {
          sendJson(res, 400, { error: 'Score must be a valid non-negative number.' });
          return;
        }

        const savedAt = new Date().toISOString();
        const entries = sortedLeaderboard([
          ...readLeaderboard(),
          { name, score: Math.floor(score), savedAt }
        ]);

        writeLeaderboard(entries);
        sendJson(res, 201, { entries, saved: { name, score: Math.floor(score), savedAt } });
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
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Forbidden');
    return;
  }

  fs.stat(absolutePath, (statError, stats) => {
    if (statError || !stats.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Not found');
      return;
    }

    const ext = path.extname(absolutePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    res.writeHead(200, { 'Content-Type': contentType });
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
