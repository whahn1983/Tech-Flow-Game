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
- **Pause & Accessibility:** `P`/`Esc` to pause, auto-pause when the tab is hidden, `prefers-reduced-motion` honored.
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
└── scripts/              # Asset generators (PWA icons, screenshots)
```

## Installation

You can run Tech Flow Runner via Apache + PHP **or** the bundled Node server (used by the Docker image). Both speak the same leaderboard JSON API.

### Apache + PHP
1. Clone the repository: `git clone https://github.com/whahn1983/Tech-Flow-Game.git`
2. Deploy the repo directory to Apache (DocumentRoot or subfolder).
3. Ensure PHP is enabled in Apache.
4. Ensure Apache can write to the deploy directory so `leaderboard.txt`, `rate_limit.txt`, and `nonces.txt` can be created.
5. Open the game URL in a web browser.

### Node (Docker)
```bash
docker compose up --build
# or:
docker build -t tech-flow-runner .
docker run -p 5001:5001 -v $(pwd)/data:/app/data tech-flow-runner
```
The bundled `server.js` serves both the static assets and the leaderboard API; the in-game client uses `./leaderboard.php`, which the Node server also accepts as an alias for `/api/leaderboard`.

### Local development
```bash
node server.js              # http://localhost:8080
PORT=5001 node server.js
```

## Leaderboard API

| Method | Path                            | Purpose                              |
|-------:|---------------------------------|--------------------------------------|
| GET    | `/leaderboard.php`              | Top 100 entries                      |
| GET    | `/leaderboard.php?action=nonce` | Issue a single-use submission nonce  |
| POST   | `/leaderboard.php`              | Submit `{ name, score, nonce? }`     |

The Node server additionally responds at `/api/leaderboard` with the same semantics.

Submissions accept an optional `nonce` (recommended). Nonces:
- Must be obtained from `?action=nonce` and used once.
- Are valid for 10 minutes.
- Reject submissions that arrive less than ~4 seconds after issuance (basic anti-script gate).

This raises the bar against trivial scripted spam but is **not** cryptographic anti-cheat — a JS client cannot keep secrets from a determined attacker.

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

`'unsafe-inline'` for `style-src` is retained because the game manipulates `element.style` at runtime (fullscreen handling). Scripts are no longer inline.

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

Lightweight tooling is configured via `.eslintrc.json`, `.prettierrc.json`, and `.editorconfig`. To lint locally:

```bash
npx eslint@8 --no-eslintrc --config .eslintrc.json 'js/**/*.js' sw.js server.js
```

CI (`.github/workflows/ci.yml`) runs Node and PHP syntax checks plus a best-effort ESLint pass on every PR.

## License
This project is proprietary and owned exclusively by whahn1983. See LICENSE file for details.

## Contact
For more information, bug reports, or feature requests, open an issue on [GitHub](https://github.com/whahn1983/Tech-Flow-Game/issues) or contact whahn1983 directly.
