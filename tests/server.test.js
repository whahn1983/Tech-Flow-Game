'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const server = require('../server.js');

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
  assert.deepEqual(sorted.map((e) => e.name), ['C', 'B', 'A']);
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
