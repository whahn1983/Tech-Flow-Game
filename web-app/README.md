# Tech Flow Runner — Web App (Browser / PWA)

The browser version of Tech Flow Runner. It's a self-contained HTML/CSS/JS game
that runs in any modern browser, installs as a Progressive Web App, plays
offline after first load, and posts scores to a server-backed global
leaderboard.

This README covers everything specific to the web deployment. For a general
overview of the game and gameplay, see the [root README](../README.md).

## Tech stack

- **Client:** Vanilla HTML, CSS, and JavaScript — no build step or framework.
- **Service worker** (`sw.js`) for offline play and PWA installability.
- **Leaderboard backend:** ships in two interchangeable flavors that speak the
  same JSON API:
  - `leaderboard.php` — PHP backend for an Apache deployment.
  - `server.js` — Node static-file + leaderboard server (used by the Docker
    image).
- **Tooling:** ESLint, Prettier, and the Node native test runner.

## Controls

- **Space / W / Up Arrow:** Jump (supports double jump).
- **P / Esc:** Pause / resume.
- **M:** Toggle mute (persists across sessions).
- **R:** Restart after game over.
- **Tap / Click:** Jump (touch and mouse support).

## Directory layout

```
web-app/
├── index.html          # Entry point — markup only
├── css/styles.css      # Styling (extracted from index.html)
├── js/game.js          # Game logic (extracted from index.html)
├── sw.js               # Service worker (cache-first static, network-first HTML)
├── manifest.json       # PWA manifest
├── favicon.svg         # Favicon
├── leaderboard.php     # PHP leaderboard backend (Apache deployment)
├── server.js           # Node leaderboard + static file server (Docker deployment)
├── Dockerfile          # Node-based container image
├── docker-compose.yml  # Compose config for the Node deployment
├── Tech Flow.mp3       # Original soundtrack (© H3 Consulting Partners LLC)
├── icons/              # Generated PWA icons (see "PWA icon assets")
├── tests/              # Unit tests (Node native test runner)
├── scripts/            # Asset generators (PWA icons, screenshots)
├── screenshots/        # Marketing / store screenshots
└── extras/             # Supplementary assets
```

## Installation & deployment

You can run the web app via Apache + PHP **or** the bundled Node server (used by
the Docker image). Both speak the same leaderboard JSON API.

### Apache + PHP

1. **Clone the repository:**
   ```bash
   git clone https://github.com/whahn1983/Tech-Flow-Game.git
   ```
2. **Deploy the `web-app/` directory** to Apache (DocumentRoot or subfolder).
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
cd web-app
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
cd web-app
npm install                 # devDependencies only
node server.js              # http://localhost:8080
PORT=5001 node server.js
npm test                    # run unit tests
npm run lint                # ESLint
npm run format              # Prettier (check); use format:fix to write
```

## Environment variables

| Variable          | Default | Description                                                                                                                                                |
| ----------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PORT`            | `8080`  | TCP port the Node server listens on (1024–65535).                                                                                                          |
| `ALLOWED_ORIGINS` | _empty_ | Comma-separated list of origins permitted to call the leaderboard API.<br>Empty means same-origin only. Honored by both `server.js` and `leaderboard.php`. |
| `NODE_ENV`        | _unset_ | Standard Node convention; the Dockerfile sets it to `production`.                                                                                          |

## Leaderboard API

|  Method | Path                            | Purpose                             |
| ------: | ------------------------------- | ----------------------------------- |
|     GET | `/leaderboard.php`              | Top 100 entries                     |
|     GET | `/leaderboard.php?action=nonce` | Issue a single-use submission nonce |
|    POST | `/leaderboard.php`              | Submit `{ name, score, nonce }`     |
| OPTIONS | `/leaderboard.php`              | CORS preflight                      |

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

## PWA / Offline

The web app is installable on desktop and mobile and plays offline after first
load via the service worker (`sw.js`), which uses a cache-first strategy for
static assets and network-first for HTML. The app also supports pausing with
`P`/`Esc`, auto-pauses when the tab is hidden, honors `prefers-reduced-motion`,
and includes a skip-link, a focus-trapped modal, and `aria-live` announcements.

### PWA icon assets

To keep this repository code-only, generated PNG icon files are not committed.

Run the icon generator before creating a release/build so PWA and iOS
home-screen icons exist:

```bash
cd web-app
python scripts/generate_pwa_icons.py
```

This creates:

- `apple-touch-icon.png`
- `icons/icon-192.png`
- `icons/icon-512.png`

## Tooling, tests & CI

Lightweight web-app tooling is configured via `package.json`, `eslint.config.js`,
and the repository-level `.prettierrc.json` and `.editorconfig`.

```bash
cd web-app
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

## Audio ownership

`Tech Flow.mp3` and all audio are © H3 Consulting Partners LLC and are served as
a static asset of this web app.
</content>
