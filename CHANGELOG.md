# Changelog

All notable changes to this project will be documented in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Legacy paid-app grandfathering (iOS).** Anyone who PAID for Tech Flow Runner
  before it went free now receives **Unlimited Lives permanently, for free** — no
  purchase required. Eligibility is determined from StoreKit 2's app-level
  transaction (`AppTransaction.shared`, verified only): a user qualifies if the
  originally-acquired `CFBundleVersion` is at/before
  `LegacyPaidAppEligibility.lastPaidBuildNumber` (`"7"`, the final build sold at
  $0.99, compared **component-wise numerically** — not by naive string
  comparison) **or** `originalPurchaseDate` precedes `freeTransitionDate`. The
  date rule covers the transition window where the free-model build is already
  live but still priced $0.99: those buyers download the *same build* as later
  free users, so only the purchase date can distinguish them. Eligibility is
  never based on mere receipt/app-transaction existence (free downloads have one
  too). To keep new free users distinct from paid buyers, the free-model
  `CURRENT_PROJECT_VERSION` is bumped to **8** (strictly above the paid cutoff of
  `7`, and the next valid build after the paid build 7). A new
  `UnlimitedLivesSource`
  (`.none` / `.purchasedIAP` / `.legacyPaidApp`) unifies both entitlement
  sources behind a single `hasUnlimitedLives`; `StoreManager` resolves ownership
  by priority (verified IAP → verified legacy → locally cached → none) and
  **never revokes a previously-verified entitlement just because a later check
  fails offline**. A grandfathered user sees a one-time **"Early Supporter
  Upgrade"** message (tracked by a separate `legacySupporterMessageShown` flag,
  never shown to IAP purchasers or new free users), never sees the $2.99 button
  (the store and Settings show "Early Supporter Access" instead), and Restore
  Purchases rechecks both the IAP and legacy eligibility with distinct success
  messages. A DEBUG-only entitlement override in Settings simulates each state
  (StoreKit sandbox can't reproduce real paid-app history); it is compiled out
  of Release builds.

- **Free-to-play lives system + Unlimited Lives in-app purchase (iOS).** The iOS
  app (Tech Flow Runner) moves from a paid download to a free-to-play model. The
  game now runs on a regenerating pool of lives: players start with **10 lives**,
  each run spends one, and **one life regenerates every 15 minutes** up to a
  maximum of **10**. Regeneration is computed from the wall clock (via a new
  `LivesManager`), so it keeps accruing while the app is backgrounded or closed;
  the menu shows the current pool and a live countdown to the next life. When the
  pool is empty, Start Run / Reboot Run become an **Out of Lives** prompt.
  A single one-time non-consumable in-app purchase, **Unlimited Lives Forever**
  ($2.99), removes the limit so runs never cost a life. It is implemented with
  **StoreKit 2** (`StoreManager`): ownership is derived from
  `Transaction.currentEntitlements` (authoritative, resolves offline once bought)
  with a `Transaction.updates` listener for Ask-to-Buy / cross-device / refund
  events, plus a **Restore Purchases** action (`AppStore.sync()`) in the paywall
  and Settings (App Store Review Guideline 3.1.1). A new `LivesStoreView` paywall
  is reachable from the menu, the out-of-lives prompts, and Settings. A
  scheme-referenced `Products.storekit` configuration file enables purchase/
  restore testing in the simulator without App Store Connect. Product ID:
  `com.whahn1983.techflowrunner.unlimitedlives`.

- **Game Center consent flow (App Store Review Guideline 5.1.2).** The iOS app
  (Tech Flow Runner) no longer authenticates Game Center automatically on first
  launch. A first-run dialog ("Game Center Leaderboards") lets the player choose
  **Play Offline** or **Connect to Game Center**, with the privacy policy linked
  before they opt in. The choice is persisted as a `GameCenterConsentState`
  (`notAsked` / `offline` / `consented`, default `notAsked`). Score submission
  and achievement reporting are now gated behind both consent and an
  authenticated local player; offline play saves local bests with nothing
  uploaded. A new **Game Center** section in Settings shows the current status
  and lets offline players connect later (or switch a connected account back to
  offline). Previously-consented players still authenticate automatically on
  subsequent launches.

- **SQLite-backed leaderboard** for the PHP backend. Scores are now stored in
  `leaderboard.sqlite` (via PDO + WAL) when the SQLite driver is available.
  Whenever the `scores` table is empty, the backend imports any existing
  `leaderboard.txt` so a redeploy (or wiped DB) can recover from the flat
  file. The `.txt` is left in place as a recovery source. Falls back to the
  flat-file path if PDO SQLite is unavailable.
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

- **Rotate-to-play prompt on iPhone.** Starting a run while holding the device
  in portrait no longer snaps the iPhone into a sideways landscape layout.
  Instead the interface follows the device's physical orientation and shows the
  existing "Rotate Device to Continue" overlay (previously seen mainly on iPad)
  until the device is turned to landscape, at which point the run locks to
  landscape and play begins.
- **Nonces are now mandatory** on score submissions. Previously the server
  accepted submissions without a nonce for legacy clients; that fallback has
  been removed on both the Node and PHP backends. The bundled client always
  obtains one.
- **Method handling** on `/api/leaderboard` and `/leaderboard.php` — non
  GET/POST/OPTIONS now return an explicit `405 Method Not Allowed` with an
  `Allow` header.
- **Service worker** bumped to `tech-flow-runner-v13` to evict any stale
  caches alongside the leaderboard EACCES fix, ensuring clients pick up the
  current client bundle on next load.
- **Service worker** bumped to `tech-flow-runner-v7`.
  - Removed the MP3 from the static cache regex; the ~7 MB audio file is now
    fetched lazily when playback starts instead of being precached.
  - Static and HTML caches now skip storing non-OK / opaque responses.
- **Dockerfile** pinned to `node:20.18.1-alpine3.20`, sets `NODE_ENV=production`,
  and removes group-write on the application directory.
- **Dockerfile** pins the `app` user to UID/GID `1001:1001` so the persisted
  `/app/data` volume keeps matching ownership across image rebuilds. Previously
  the auto-assigned UID could drift, leaving the volume owned by a UID the
  rebuilt container no longer mapped to and surfacing as `EACCES: permission
denied` on leaderboard writes.
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

### Fixed

- **Rapid-tap jump float (iOS).** Hammering the jump button no longer lets the
  player hover/climb instead of falling after the double jump. Each rapid press
  used to re-arm the jump-input buffer, so every brief ground contact auto-fired
  a buffered jump (and refilled the double jump), chaining into an endless
  auto-bounce. The jump buffer is now latched so it can be armed at most once per
  landing — it only re-enables after the player settles back on the ground — so
  no matter how fast the button is pressed the game recognizes only a single
  jump or double jump. Legitimate input buffering (a single press just before
  landing) and coyote-time jumps are unaffected.

### Security

- Mandatory nonce on score submissions (see above).
- Explicit CORS allowlist with `Vary: Origin`.
- Hardened Docker runtime defaults (read-only filesystem, dropped capabilities,
  no new privileges).

## Earlier history

See the git log for changes prior to the introduction of this changelog.
