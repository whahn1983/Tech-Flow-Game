# Tech Flow Game

## Proprietary Ownership

This software is owned by whahn1983. All rights reserved.

This program is not open-source and cannot be modified or distributed without the owner's explicit permission. All music and audio contained within is also owned by whahn1983.

## Overview
Tech Flow Runner is an engaging game that challenges players to navigate through a circuit board filled with various obstacles. The objective is to guide the Tech Flow Runner through levels while enjoying incredible original music.

## Gameplay
- Players control the Tech Flow Runner using keyboard commands or screen taps.
- The Runner auto-scrolls through the level; players must jump (including double jump) to evade obstacles and enemies.
- There are multiple levels, each with unique challenges and a boss fight at the end.

## Features
- **Dynamic Obstacles:** Different types of obstacles that may move or change.
- **Global Leaderboard:** Save your best runs to a server-backed leaderboard shared by all players.
- **Power-Ups:** Obtain various power-ups to enhance abilities temporarily.
- **Progressive Difficulty:** Each level gets progressively harder with more obstacles and faster enemies.
- **Scoring System:** Players earn points based on performance, speed, and level completion.
- **Original Soundtrack:** Experience amazing original music created by whahn1983.
- **Pause & Accessibility:** `P`/`Esc` to pause, auto-pause when the tab is hidden, `prefers-reduced-motion` honored, skip-link, focus-trapped modal, `aria-live` announcements.
- **PWA / Offline:** Installable on desktop and mobile, plays offline after first load.

## Controls
- **Space / W / Up Arrow:** Jump (supports double jump).
- **P / Esc:** Pause / resume.
- **M:** Toggle mute (persists across sessions).
- **R:** Restart after game over.
- **Tap / Click:** Jump (touch and mouse support).

## Project Structure

```
.
├── index.html            # Entry point — markup only
├── css/styles.css        # Styling (extracted from index.html)
├── js/game.js            # Game logic (extracted from index.html)
├── sw.js                 # Service worker (cache-first static, network-first HTML)
├── manifest.json         # PWA manifest
├── leaderboard.php       # PHP leaderboard backend (Apache deployment)
├── server.js             # Node leaderboard + static file server (Docker deployment)
├── Dockerfile            # Node-based container image
├── docker-compose.yml    # Compose config for the Node deployment
├── tests/                # Unit tests (Node native test runner)
├── scripts/              # Asset generators (PWA icons, screenshots)
├── CHANGELOG.md          # Release notes
└── CONTRIBUTING.md       # Contributor guide
```

## Installation

You can run Tech Flow Runner via Apache + PHP **or** the bundled Node server (used by the Docker image). Both speak the same leaderboard JSON API.

### Apache + PHP

1. **Clone the repository:**
   ```bash
   git clone https://github.com/whahn1983/Tech-Flow-Game.git
   ```
2. **Deploy the repo directory** to Apache (DocumentRoot or subfolder).
3. **Enable PHP** (`>= 8.0`) in Apache, with the `pdo_sqlite` and `mbstring`
   extensions if you want SQLite-backed leaderboard storage (recommended for
   any deployment expecting concurrent submissions).
4. **Make the directory writable** by the Apache user so the backend can
   create:
   - `leaderboard.sqlite` (or `leaderboard.txt` if SQLite is unavailable),
   - `rate_limit.txt`,
   - `nonces.txt`.
5. **(Recommended)** Add a `.htaccess` to deny direct access to the data files:
   ```apache
   <FilesMatch "^(leaderboard\.(txt|sqlite|sqlite-journal)|rate_limit\.txt|nonces\.txt)$">
     Require all denied
   </FilesMatch>
   ```
6. **Open the game URL** in a browser.

### Node (Docker)

```bash
docker compose up --build
# or:
docker build -t tech-flow-runner .
docker run -p 5001:5001 -v $(pwd)/data:/app/data tech-flow-runner
```

The bundled `server.js` serves both the static assets and the leaderboard API; the in-game client uses `./leaderboard.php`, which the Node server also accepts as an alias for `/api/leaderboard`.

The shipped `docker-compose.yml` runs the container with hardened defaults:
`read_only: true`, `cap_drop: [ALL]`, `no-new-privileges`, and a `tmpfs` for `/tmp`.

### Local development

```bash
npm install                 # devDependencies only
node server.js              # http://localhost:8080
PORT=5001 node server.js
npm test                    # run unit tests
npm run lint                # ESLint
npm run format              # Prettier (check); use format:fix to write
```

## Environment variables

| Variable          | Default | Description                                                                 |
|-------------------|---------|-----------------------------------------------------------------------------|
| `PORT`            | `8080`  | TCP port the Node server listens on (1024–65535).                           |
| `ALLOWED_ORIGINS` | _empty_ | Comma-separated list of origins permitted to call the leaderboard API.<br>Empty means same-origin only. Honored by both `server.js` and `leaderboard.php`. |
| `NODE_ENV`        | _unset_ | Standard Node convention; the Dockerfile sets it to `production`.            |

## Leaderboard API

| Method  | Path                            | Purpose                              |
|--------:|---------------------------------|--------------------------------------|
| GET     | `/leaderboard.php`              | Top 100 entries                      |
| GET     | `/leaderboard.php?action=nonce` | Issue a single-use submission nonce  |
| POST    | `/leaderboard.php`              | Submit `{ name, score, nonce }`      |
| OPTIONS | `/leaderboard.php`              | CORS preflight                       |

The Node server additionally responds at `/api/leaderboard` with the same semantics.

### Nonce flow

```
Client                                   Server
  │                                        │
  │── GET  /leaderboard.php?action=nonce ─▶│   issue_nonce(): random 16-byte hex
  │                                        │   stored with timestamp; capped at 4096
  │◀── { "nonce": "abc...123" } ──────────│
  │                                        │
  │  (wait at least 4 s — anti-script gate) │
  │                                        │
  │── POST /leaderboard.php ──────────────▶│   consume_nonce()
  │   { name, score, nonce }               │   - rejects if missing/malformed
  │                                        │   - rejects if expired (>10 min)
  │                                        │   - rejects if too fresh (<4 s)
  │                                        │   - rejects if already consumed
  │◀── 201 { entries, saved }  ────────────│
  │   or 400 if nonce check fails          │
```

This raises the bar against trivial scripted spam but is **not** cryptographic
anti-cheat — a JS client cannot keep secrets from a determined attacker.

### Rate limiting

Each client IP may submit at most **5 POSTs per 60 seconds**. Excess requests
receive `429 Too Many Requests`. Rate-limit state is in-memory in the Node
server and file-backed (`rate_limit.txt`) in PHP.

## Security & CSP

The page ships a strict Content-Security-Policy:

```
default-src 'self';
script-src 'self';
style-src 'self' 'unsafe-inline';
img-src 'self' data: blob:;
media-src 'self';
connect-src 'self';
worker-src 'self';
base-uri 'self';
form-action 'self';
frame-ancestors 'none';
```

`'unsafe-inline'` for `style-src` is retained because the game manipulates
`element.style` at runtime (fullscreen / scroll-lock handling). Scripts are
served from external files only.

Additional defences:

- `X-Content-Type-Options: nosniff` and `X-Frame-Options: DENY` on every
  response.
- `Referrer-Policy: strict-origin-when-cross-origin` (Node) /
  `no-referrer` (PHP).
- `Content-Security-Policy: default-src 'none'` on JSON API responses.
- Mandatory single-use nonces on score submissions.
- Same-origin CORS by default; explicit allowlist via `ALLOWED_ORIGINS`.
- 10 KB request body cap on submissions.
- Hardened Docker runtime (`read_only`, `cap_drop`, `no-new-privileges`).

## PWA Icon Assets
To keep this repository code-only, generated PNG icon files are not committed.

Run the icon generator before creating a release/build so PWA and iOS home-screen icons exist:

```bash
python scripts/generate_pwa_icons.py
```

This creates:
- `apple-touch-icon.png`
- `icons/icon-192.png`
- `icons/icon-512.png`

## Development

Lightweight tooling is configured via `package.json`, `eslint.config.js`,
`.prettierrc.json`, and `.editorconfig`.

```bash
npm run lint           # ESLint
npm run format         # Prettier (check)
npm run format:fix     # Prettier (write)
npm test               # node --test
```

CI (`.github/workflows/ci.yml`) runs Node and PHP syntax checks, ESLint, a
Prettier check, manifest validation, and the unit-test suite on every PR. Lint
failures fail the build (no longer best-effort).

A pre-commit hook is wired via Husky + lint-staged. Run `npm run prepare`
once after `npm install` to enable it locally.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full contributor guide and
[`CHANGELOG.md`](CHANGELOG.md) for release notes.

## License
This project is proprietary and owned exclusively by whahn1983. See LICENSE file for details.

## Contact
For more information, bug reports, or feature requests, open an issue on [GitHub](https://github.com/whahn1983/Tech-Flow-Game/issues) or contact whahn1983 directly.

For security issues, please open a private security advisory rather than a
public issue.
