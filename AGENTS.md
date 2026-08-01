# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## TL;DR — read this first

- **This is now an iOS-only project.** All active development happens in the
  **native iOS app** under [`TechFlowRunner/`](TechFlowRunner/).
- **The web app is archived.** [`web-app/`](web-app/) (HTML/CSS/JS + a PHP/Node
  leaderboard backend) is **no longer maintained or developed**. It is kept for
  reference only. **Do not add features, fix bugs, or spend effort in
  `web-app/`** unless the user explicitly and specifically asks you to touch the
  archived web code.
- When a request is ambiguous about platform, assume it targets the **iOS Swift
  app**.
- The iOS app was ported *from* the web game and treats the web code purely as a
  gameplay reference — it shares no source with it.

## Repository layout

```
Tech-Flow-Game/
├── AGENTS.md                 # ← you are here
├── README.md                 # Player-facing overview (iOS-first)
├── CHANGELOG.md              # Keep-a-Changelog; add iOS notes under [Unreleased]
├── CONTRIBUTING.md           # ⚠️ Legacy — written for the archived web app
├── LICENSE                   # Proprietary (H3 Consulting Partners LLC)
├── docs/privacy.html         # Privacy policy (served via GitHub Pages)
│
├── TechFlowRunner/           # ★ THE iOS APP — do your work here
│   ├── TechFlowRunner.xcodeproj
│   ├── Products.storekit     # Local StoreKit config for IAP testing (scheme-referenced)
│   ├── generate_project.py   # Recreates project.pbxproj if lost (NOT normal workflow)
│   ├── generate_app_icon.py  # Regenerates the app icon PNG
│   ├── README.md             # Deep, authoritative iOS app documentation
│   └── TechFlowRunner/       # Swift sources (file-system-synchronized group)
│       ├── TechFlowRunnerApp.swift   # @main App entry + AppDelegate (orientation)
│       ├── AppState.swift            # App-wide coordinator / run-state machine
│       ├── Game/                     # SpriteKit simulation + rendering
│       ├── Models/                   # Modifier.swift, Skin.swift
│       ├── Services/                 # GameCenter, Store, Audio, Lives, Persistence, …
│       ├── UI/                       # SwiftUI menus / HUD / overlays / pickers
│       ├── Resources/Tech Flow.mp3   # Bundled soundtrack (© H3 Consulting Partners LLC)
│       ├── Assets.xcassets           # App icon + accent color
│       └── TechFlowRunner.entitlements
│
└── web-app/                  # 🗄️ ARCHIVED — do not develop here
```

For anything iOS-specific not covered here, **`TechFlowRunner/README.md` is the
authoritative, detailed reference** (App Store Connect setup, monetization,
Game Center, skins, Daily Seed). Keep it in sync when you change those systems.

## Tech stack (iOS app)

- **Language:** Swift 5, `@MainActor`-centric.
- **Frameworks:** SwiftUI (UI/menus), SpriteKit (gameplay simulation + render),
  GameKit (Game Center), StoreKit 2 (single IAP), AVFoundation (audio), UIKit
  (app delegate + orientation).
- **Minimum OS:** iOS 17.0. Universal (iPhone + iPad, `TARGETED_DEVICE_FAMILY = "1,2"`).
- **Bundle ID:** `com.h3consultingpartners.techflowrunner`.
- **Backend:** none. Everything is local (UserDefaults); Game Center is optional.

## Build, run, and verify

- Open the project:
  ```
  open TechFlowRunner/TechFlowRunner.xcodeproj
  ```
  Select the **TechFlowRunner** scheme + an iPhone simulator/device and Run.
- **Requires Xcode 16 or later.** The project uses a **file-system-synchronized
  root group** (`PBXFileSystemSynchronizedRootGroup`).
- **There is no automated test target** for the iOS app, and **no CI/GitHub
  Actions workflows** in this repo. Verify changes by **building and running in
  Xcode / the simulator**.
- This is a remote/headless-friendly repo, but **an iOS build requires Xcode on
  macOS** — you generally cannot compile or run the app from the Linux web
  session. Make focused, well-reasoned edits and lean on reading the
  surrounding code; call out that you could not build when relevant.

### Adding, renaming, or deleting Swift files

Because of the synchronized group, **just add/remove the file on disk** — Xcode
picks it up automatically. **Do not hand-edit `project.pbxproj`** to register
sources, and **do not run `generate_project.py`** as part of normal work; that
script exists only to recreate the project file from scratch if it is ever lost
(it is idempotent and emits a fully static project).

## Architecture (iOS)

- **`AppState`** (`@MainActor ObservableObject`) is the single app-wide
  coordinator. It owns the one `TechFlowGameScene`, drives the `RunState`
  machine (`menu → running → paused → gameOver`), holds persisted menu
  selections, and is the scene's delegate — translating gameplay callbacks into
  `@Published` state the SwiftUI layer renders. Start here to understand any
  flow.
- **`TechFlowGameScene`** (`Game/`, ~1.3k lines) owns the entire gameplay
  simulation and rendering. Key properties:
  - Runs a **fixed 60 Hz timestep** with an accumulator, in **"design space"
    (y-down**, matching the original web reference), flipping to SpriteKit's
    y-up space only when positioning nodes.
  - Collisions use **explicit AABB tests** (not the physics solver) for
    determinism; physics categories exist only to honor the SpriteKit model.
  - Communicates with `AppState` via the `TechFlowGameSceneDelegate` protocol
    (`sceneDidUpdateHUD`, `sceneDidEndRun`).
- **`GameConstants`** is the central tuning table (gravity, speeds, combo,
  power-up durations, boss, terrain). Change gameplay feel **here**, not with
  magic numbers scattered in the scene.
- **`GameSceneView`** (`UI/`) bridges the SpriteKit scene into SwiftUI and wires
  gestures: **tap = jump/double-jump, swipe-down-hold = duck, swipe-right =
  dash.** The HUD's on-screen buttons provide the same actions for accessibility.
- **Models:** `Modifier` (run rules + score multipliers) and `Skin` (cosmetic,
  unlock thresholds, Game Center achievement IDs). Both are `Codable` enums with
  stable `rawValue`s used as persistence keys — **do not rename raw values.**
- **Services** (singletons, mostly `@MainActor`):
  - `PersistenceManager` — the only persistence layer, `UserDefaults`-backed.
    All keys are namespaced `tfr.*`. Never introduce a different storage layer.
  - `GameCenterManager` — auth, score submission, achievements, board UI.
  - `StoreManager` — StoreKit 2, the single "Unlimited Lives" non-consumable.
  - `LivesManager` — free-to-play energy pool (regenerates off the wall clock).
  - `AudioManager` — looping soundtrack + SFX via AVFoundation.
  - `OrientationManager` (+ `AppDelegate`) — orientation gating.
  - `HapticsManager` — haptic feedback.
- **The reference design space is fixed** at 874×402 pt (iPhone 16 Pro logical
  size). The SpriteKit scene is locked to this size and **aspect-fit scaled**
  onto every device so the playable area — and thus difficulty — is identical
  everywhere. Don't tie gameplay geometry to a device's actual point size.

## Critical conventions & gotchas

- **No backend, ever.** Best score, lifetime stats, settings, run history,
  lives, and cached IAP ownership all live on-device via `PersistenceManager`.
  Leaderboards go through Game Center only.
- **Determinism matters.** Daily Seed mode (`SeededRandom`, Mulberry32, seeded
  from the UTC `YYYYMMDD` date) must produce the identical course for every
  player on a given app version. Don't introduce nondeterminism (wall-clock
  randomness, unordered iteration affecting spawns) into the simulation path.
- **Game Center consent (App Store Review Guideline 5.1.2).** The app must
  **never authenticate Game Center or upload a score/achievement before the
  player has explicitly opted in.** Consent is tracked by
  `GameCenterConsentState` (`.notAsked` / `.offline` / `.consented`); every
  upload path is gated on `.consented` **and** `isAuthenticated`. Preserve this
  gating in any change touching Game Center.
- **App Store Connect IDs must stay in lockstep with code.** These string IDs
  are the source of truth in code and must match App Store Connect exactly
  (typos fail silently at runtime):
  - Leaderboards → `LeaderboardID` in `Services/GameCenterManager.swift`
    (`techflow.highscore`, `.none/.hardcore/.bitrush/.featherfall/.glasscannon`,
    `techflow.daily`).
  - Achievements → `Skin.achievementID` (`techflow.skin.*`).
  - IAP → `StoreProductID.unlimitedLives`
    (`com.whahn1983.techflowrunner.unlimitedlives`).
  If you add a modifier/skin/product, update both the code ID **and** the
  App Store Connect setup notes in `TechFlowRunner/README.md`.
- **Concurrency:** most managers and `AppState` are `@MainActor`. Scene→app
  callbacks hop back to the main actor (`Task { @MainActor in … }`). Keep new
  UI/state mutations on the main actor.
- **Orientation:** menus allow portrait+landscape; an **active run locks to
  landscape**. Rotation is requested via `UIWindowScene.requestGeometryUpdate`
  and reported through `AppDelegate.supportedInterfaceOrientationsFor` — no
  `UIDevice.setValue` hacks. Starting/rotating into portrait mid-run shows a
  "Rotate Device to Continue" overlay instead of forcing a sideways layout.
- **Lives regenerate from the wall clock** (a stored count + one anchor
  timestamp), not a running timer, so they accrue while backgrounded. Don't
  replace this with a Timer-based scheme.
- **`#if DEBUG` only** for diagnostics (`[GameCenter]`/`[Store]` logging, the
  in-app debug panel, `LivesManager.debugRefill()/debugDrain()`). Keep debug
  helpers out of release paths.
- **Skins are cosmetic only** — every skin renders inside the identical player
  hitbox. A new skin must not change collision geometry.
- **Assets** (`Tech Flow.mp3`, artwork) are © H3 Consulting Partners LLC and are
  bundled locally — never fetched remotely.

## Documentation to keep current

When you change behavior, update the relevant docs in the same change:

- **`CHANGELOG.md`** — add a bullet under `## [Unreleased]` (iOS-focused).
- **`TechFlowRunner/README.md`** — the detailed iOS reference (monetization,
  Game Center/leaderboard/achievement IDs, skins, Daily Seed, project layout).
- **`README.md`** — player-facing overview; keep it iOS-first.

## Known-stale files (web-era; do not treat as current)

These predate the iOS-only focus and describe the archived web app. Leave them
alone unless the user explicitly asks you to update or remove them:

- **`CONTRIBUTING.md`** — describes an npm/PHP/Node workflow for the web app.
- **`.claude/hooks/session-start.sh`** — runs `npm install` at the repo root
  (a web-app dependency step) on remote sessions.
- **`web-app/`** in its entirety.

## Git / workflow

- Proprietary software (see `LICENSE`) — © H3 Consulting Partners LLC. Do not
  add open-source headers or relicense anything.
- Commit style follows the log: `<type>: <short summary>` with types like
  `feat`, `fix`, `chore`, `docs`, `refactor`, `perf` (see `CHANGELOG.md`).
- Do not open a pull request unless explicitly asked.
