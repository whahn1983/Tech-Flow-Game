'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Redirect persisted state into a per-run tmp dir so the suite doesn't depend on
// /app/data being writable and doesn't pollute a real Docker volume.
const TMP_DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'tfg-test-'));
process.env.DATA_DIR = TMP_DATA_DIR;

const server = require('../server.js');
const NONCE_FILE = path.join(TMP_DATA_DIR, 'nonces.txt');

test('cleanPlayerName strips disallowed characters and trims', () => {
  assert.equal(server.cleanPlayerName('  Alice<script>  '), 'Alicescript');
  assert.equal(server.cleanPlayerName('Bob_42!'), 'Bob_42!');
  assert.equal(server.cleanPlayerName(null), '');
  assert.equal(server.cleanPlayerName(undefined), '');
});

test('cleanPlayerName enforces max length (24 chars)', () => {
  const longName = 'A'.repeat(60);
  assert.equal(server.cleanPlayerName(longName).length, 24);
});

test('cleanPlayerName rejects emoji and non-ASCII', () => {
  assert.equal(server.cleanPlayerName('Hi😀there'), 'Hithere');
  assert.equal(server.cleanPlayerName('Café'), 'Caf');
});

test('isLeaderboardPath matches both Node and PHP routes', () => {
  assert.equal(server.isLeaderboardPath('/api/leaderboard'), true);
  assert.equal(server.isLeaderboardPath('/leaderboard.php'), true);
  assert.equal(server.isLeaderboardPath('/leaderboard'), false);
  assert.equal(server.isLeaderboardPath('/api/other'), false);
});

test('sortedLeaderboard sorts descending by score, ascending by savedAt', () => {
  const entries = [
    { name: 'A', score: 100, savedAt: '2024-01-01T00:00:00Z' },
    { name: 'B', score: 200, savedAt: '2024-01-02T00:00:00Z' },
    { name: 'C', score: 200, savedAt: '2024-01-01T00:00:00Z' },
  ];
  const sorted = server.sortedLeaderboard(entries);
  assert.deepEqual(
    sorted.map((e) => e.name),
    ['C', 'B', 'A']
  );
});

test('categorizeLeaderboard buckets by modifier and caps each at 10', () => {
  const entries = [];
  // Seed 12 entries each for two categories — top 10 should survive per bucket.
  for (let i = 0; i < 12; i++) {
    entries.push({
      name: `H${i}`,
      score: 1000 + i,
      savedAt: `2024-01-01T00:00:0${i % 10}Z`,
      modifier: 'hardcore',
    });
    entries.push({
      name: `B${i}`,
      score: 200 + i,
      savedAt: `2024-01-02T00:00:0${i % 10}Z`,
      modifier: 'bitrush',
    });
  }
  // A row with a missing modifier should land in 'og'.
  entries.push({ name: 'Legacy', score: 50, savedAt: '2023-12-31T00:00:00Z' });
  const buckets = server.categorizeLeaderboard(entries);
  assert.equal(buckets.hardcore.length, 10);
  assert.equal(buckets.bitrush.length, 10);
  assert.equal(buckets.hardcore[0].name, 'H11', 'top hardcore score should be the highest');
  assert.equal(buckets.og.length, 1);
  assert.equal(buckets.og[0].name, 'Legacy');
  assert.equal(buckets.none.length, 0);
});

test('categorizeLeaderboard treats unknown modifiers as og', () => {
  const buckets = server.categorizeLeaderboard([
    { name: 'X', score: 5, savedAt: '2024-01-01T00:00:00Z', modifier: 'cheater' },
  ]);
  assert.equal(buckets.og.length, 1);
  assert.equal(buckets.og[0].name, 'X');
});

test('sortedLeaderboard caps at 100 entries', () => {
  const entries = Array.from({ length: 250 }, (_, i) => ({
    name: `P${i}`,
    score: i,
    savedAt: '2024-01-01T00:00:00Z',
  }));
  assert.equal(server.sortedLeaderboard(entries).length, 100);
});

test('checkRateLimit allows up to 5 calls per IP per window', () => {
  const ip = '203.0.113.42';
  server._state.rateLimitStore.delete(ip);
  for (let i = 0; i < 5; i++) {
    assert.equal(server.checkRateLimit(ip), true, `call ${i + 1} should pass`);
  }
  assert.equal(server.checkRateLimit(ip), false, '6th call should be blocked');
});

test('issueNonce returns a 32-char hex string', () => {
  const nonce = server.issueNonce();
  assert.match(nonce, /^[0-9a-f]{32}$/);
});

test('consumeNonce rejects unknown, malformed, and rapid-fire nonces', () => {
  // Unknown nonce.
  assert.equal(server.consumeNonce('deadbeef'.repeat(4)), false);
  // Malformed nonce.
  assert.equal(server.consumeNonce('not-a-hex-string'), false);
  assert.equal(server.consumeNonce(''), false);
  assert.equal(server.consumeNonce(null), false);

  // Issued nonce can't be consumed within MIN_AGE.
  const fresh = server.issueNonce();
  assert.equal(server.consumeNonce(fresh), false, 'rapid-fire submission must be rejected');
});

test('consumeNonce accepts a sufficiently aged nonce exactly once', () => {
  const aged = server.issueNonce();
  // Backdate the nonce so it's older than NONCE_MIN_AGE_MS (4s).
  server._state.nonceStore.set(aged, Date.now() - 5000);

  assert.equal(server.consumeNonce(aged), true, 'aged nonce should be accepted');
  assert.equal(server.consumeNonce(aged), false, 'replayed nonce should be rejected');
});

test('issueNonce persists the nonce to nonces.txt in the data dir', () => {
  const nonce = server.issueNonce();
  assert.ok(fs.existsSync(NONCE_FILE), 'nonces.txt should be created on first issue');
  const raw = fs.readFileSync(NONCE_FILE, 'utf8');
  assert.match(raw, new RegExp(`^${nonce}\\|\\d+$`, 'm'));
});

test('consumeNonce removes the entry from the on-disk nonce file', () => {
  const aged = server.issueNonce();
  server._state.nonceStore.set(aged, Date.now() - 5000);
  assert.equal(server.consumeNonce(aged), true);
  const raw = fs.existsSync(NONCE_FILE) ? fs.readFileSync(NONCE_FILE, 'utf8') : '';
  assert.ok(!raw.includes(aged), 'consumed nonce should no longer appear in nonces.txt');
});

test('dailyLeaderboard returns only entries matching the seed date, top 10, ranked by score', () => {
  const today = '2026-05-02';
  const otherDay = '2026-05-01';
  const entries = [];
  for (let i = 0; i < 12; i++) {
    entries.push({
      name: `D${i}`,
      score: 500 + i,
      savedAt: `2026-05-02T00:00:0${i % 10}Z`,
      modifier: 'none',
      daily: true,
      seedDate: today,
    });
  }
  // Same date, mixed modifier — should also be eligible for the daily section.
  entries.push({
    name: 'Mixed',
    score: 9999,
    savedAt: '2026-05-02T00:00:00Z',
    modifier: 'hardcore',
    daily: true,
    seedDate: today,
  });
  // Different date — must be excluded.
  entries.push({
    name: 'Yesterday',
    score: 100000,
    savedAt: '2026-05-01T00:00:00Z',
    modifier: 'none',
    daily: true,
    seedDate: otherDay,
  });
  // Non-daily — must be excluded even with a matching seedDate field.
  entries.push({
    name: 'NotDaily',
    score: 100000,
    savedAt: '2026-05-02T00:00:00Z',
    modifier: 'none',
    daily: false,
    seedDate: today,
  });

  const top = server.dailyLeaderboard(entries, today);
  assert.equal(top.length, 10, 'caps at MAX_DAILY_ENTRIES');
  assert.equal(top[0].name, 'Mixed', 'top score across modifiers wins');
  assert.ok(
    top.every((e) => e.seedDate === today && e.daily),
    "only today's daily entries are returned"
  );
});

test('dailyLeaderboard rejects malformed seed-date inputs', () => {
  const entries = [
    {
      name: 'A',
      score: 1,
      savedAt: '2026-05-02T00:00:00Z',
      modifier: 'none',
      daily: true,
      seedDate: '2026-05-02',
    },
  ];
  assert.deepEqual(server.dailyLeaderboard(entries, ''), []);
  assert.deepEqual(server.dailyLeaderboard(entries, 'bogus'), []);
  assert.deepEqual(server.dailyLeaderboard(entries, '2026-05-2'), []);
});

test('categorizeLeaderboard preserves daily/seedDate fields on entries', () => {
  const entries = [
    {
      name: 'Solo',
      score: 42,
      savedAt: '2026-05-02T00:00:00Z',
      modifier: 'none',
      daily: true,
      seedDate: '2026-05-02',
    },
  ];
  const buckets = server.categorizeLeaderboard(entries);
  assert.equal(buckets.none.length, 1);
  assert.equal(buckets.none[0].daily, true);
  assert.equal(buckets.none[0].seedDate, '2026-05-02');
});

test('purgeStaleDailyEntries drops daily entries from prior dates and keeps the rest', () => {
  const today = '2026-05-02';
  const entries = [
    // Today's daily entry — keep.
    { name: 'Today', score: 50, savedAt: `${today}T01:00:00Z`, modifier: 'none', daily: true, seedDate: today },
    // Yesterday's daily entry — drop.
    { name: 'Yesterday', score: 80, savedAt: '2026-05-01T01:00:00Z', modifier: 'hardcore', daily: true, seedDate: '2026-05-01' },
    // Non-daily entry — keep regardless of seedDate value.
    { name: 'Regular', score: 30, savedAt: '2026-04-20T00:00:00Z', modifier: 'none', daily: false, seedDate: '' },
    // Older daily entry from a different category — drop.
    { name: 'WayBack', score: 999, savedAt: '2025-12-31T00:00:00Z', modifier: 'bitrush', daily: true, seedDate: '2025-12-31' },
  ];
  const purged = server.purgeStaleDailyEntries(entries, today);
  assert.deepEqual(
    purged.map((e) => e.name).sort(),
    ['Regular', 'Today']
  );
});

test('purgeStaleDailyEntries returns a copy when given a malformed today date', () => {
  const entries = [
    { name: 'A', score: 1, savedAt: '2026-05-02T00:00:00Z', modifier: 'none', daily: true, seedDate: '2026-05-02' },
  ];
  const purged = server.purgeStaleDailyEntries(entries, 'bogus');
  assert.deepEqual(purged, entries);
  assert.notEqual(purged, entries, 'returns a fresh array, not the same reference');
});
