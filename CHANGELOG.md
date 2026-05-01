# Changelog

All notable changes to this project will be documented in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **SQLite-backed leaderboard** for the PHP backend. Scores are now stored in
  `leaderboard.sqlite` (via PDO + WAL) when the SQLite driver is available; the
  legacy `leaderboard.txt` is migrated automatically on first run and renamed
  to `leaderboard.txt.imported`. Falls back to the flat-file path if PDO SQLite
  is unavailable.
- **CORS allowlist** via the `ALLOWED_ORIGINS` environment variable (Node and
  PHP). Defaults to same-origin only.
- **Unit tests** under `tests/` covering name sanitization, route matching,
  leaderboard sorting & capping, rate limiting, and the nonce lifecycle (issue,
  consume, expiry, replay rejection).
- **Skip-link** ("Skip to game") for keyboard users.
- **`aria-live` region** for run-end and score-save announcements (screen
  reader feedback).
- **Focus trap + ESC-to-close** on the score submission modal; focus is
  restored to the trigger element on close.
- **`aria-pressed` state** on the music toggle.
- **Dependabot configuration** for npm, Docker, and GitHub Actions.
- **Pull-request and issue templates**.
- **`package.json`** with `npm run lint`, `npm test`, `npm run format`, and
  Husky + lint-staged scaffolding.

### Changed
- **Nonces are now mandatory** on score submissions. Previously the server
  accepted submissions without a nonce for legacy clients; that fallback has
  been removed on both the Node and PHP backends. The bundled client always
  obtains one.
- **Method handling** on `/api/leaderboard` and `/leaderboard.php` — non
  GET/POST/OPTIONS now return an explicit `405 Method Not Allowed` with an
  `Allow` header.
- **Service worker** bumped to `tech-flow-runner-v7`.
  - Removed the MP3 from the static cache regex; the ~7 MB audio file is now
    fetched lazily when playback starts instead of being precached.
  - Static and HTML caches now skip storing non-OK / opaque responses.
- **Dockerfile** pinned to `node:20.18.1-alpine3.20`, sets `NODE_ENV=production`,
  and removes group-write on the application directory.
- **docker-compose.yml** runs the container with `read_only: true`,
  `cap_drop: [ALL]`, `no-new-privileges`, and a `tmpfs` for `/tmp`.
- **Leaderboard polling** in the client is now visibility-aware: the 60-second
  poll only runs while the tab is visible, and re-fetches immediately on
  visibility regain.
- **Error handling** on leaderboard fetch / submission distinguishes between
  network errors (`TypeError`) and bad responses (`SyntaxError`) for clearer
  user-facing messages.
- **CI** no longer ignores ESLint failures (`|| true` removed); a Prettier
  check and the unit test job are now part of the pipeline.

### Security
- Mandatory nonce on score submissions (see above).
- Explicit CORS allowlist with `Vary: Origin`.
- Hardened Docker runtime defaults (read-only filesystem, dropped capabilities,
  no new privileges).

## Earlier history

See the git log for changes prior to the introduction of this changelog.
