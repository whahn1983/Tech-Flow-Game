# Tech Flow Runner — Native iOS App

A standalone native iOS game built with **Swift, SwiftUI, SpriteKit, GameKit,
and AVFoundation**. It recreates the gameplay identity of the Tech Flow Runner
web game natively — a neon/circuit-board endless runner with jumping, double
jumping, ducking, dashing, collectible bits, combos, power-ups, progressive
levels, and a Mainframe boss fight — with **no backend**: leaderboards use Game
Center and all settings/progress persist locally.

This project does **not** use the web/PWA/JS/PHP/Node code in the parent repo;
that codebase was used only as a gameplay reference.

## Requirements

- Xcode 15 or later
- iOS 17.0+ device or simulator
- (For Game Center) a paid Apple Developer account + the leaderboards configured
  in App Store Connect (see below). Game Center is optional — the game is fully
  playable offline and unauthenticated.

## Opening & running

```
open TechFlowRunner/TechFlowRunner.xcodeproj
```

Select the **TechFlowRunner** scheme and an iPhone simulator/device, then Run.
Menus may be used in portrait or landscape, but an active run is locked to
landscape (both Landscape Left and Landscape Right) so every player gets the
same play area — this keeps the Game Center leaderboard fair. The lock is
driven by `OrientationManager` + the app delegate's
`supportedInterfaceOrientationsFor`, with a fixed-landscape SpriteKit scene.
Rather than forcing a rotation when a run begins, the interface follows the
device: starting (or rotating) into portrait pauses play behind a "Rotate
Device to Continue" overlay until the device is turned back to landscape, at
which point the run locks to landscape and resumes. This applies on iPhone and
iPad (including iPad multitasking, where rotation can't be forced at all).
iPhone first; iPad is also supported.

> The Xcode project uses a **file-system-synchronized root group** (Xcode 16+):
> the whole `TechFlowRunner/` folder is referenced as one synchronized group, so
> Xcode automatically picks up any file you add to it on disk — no
> `project.pbxproj` edits needed when adding or removing source files.
> `generate_project.py` is kept only to recreate `project.pbxproj` from scratch
> if it is ever lost; it is not part of the normal add-a-file workflow.
> **Requires Xcode 16 or later** to open (`objectVersion = 77`).

## Project structure

```
TechFlowRunner/
  TechFlowRunner.xcodeproj
  TechFlowRunner/
    TechFlowRunnerApp.swift      App entry / scene phase handling
    AppState.swift               Run-state machine, persistence + GC coordinator
    Game/                        SpriteKit simulation
      TechFlowGameScene.swift    Fixed-step sim, spawning, collisions, boss, render
      Player.swift, Boss.swift, Obstacle.swift, CollectibleBit.swift,
      PowerUp.swift, Projectile.swift, ParticleEffect.swift,
      TerrainGenerator.swift, SkinRenderer.swift, SkinIconRenderer.swift,
      GameState.swift,
      GameConstants.swift, PhysicsCategories.swift, SeededRandom.swift,
      GameSceneView.swift        SpriteKit ⇄ SwiftUI bridge + gestures
    Models/                      Modifier.swift, Skin.swift
    Services/                    GameCenterManager, AudioManager,
                                 PersistenceManager, HapticsManager
    UI/                          SwiftUI menus / HUD / overlays / pickers
    Resources/Tech Flow.mp3      Bundled looping soundtrack (© H3 Consulting Partners LLC)
    Assets.xcassets              App icon slot + accent color
    TechFlowRunner.entitlements  Game Center capability
```

## Controls

- **Tap** — jump / double jump
- **Swipe down (hold)** — duck
- **Swipe right** — dash
- **On-screen buttons** — Jump / Duck / Dash (accessibility fallback) + Pause

## Game Center leaderboards

Authentication runs automatically at launch and gracefully degrades when
unavailable; the menu and Leaderboard screens show a status line (Signed in /
Not signed in / Authentication failed). On a run end the score is submitted to
the overall board, the modifier-specific board, and (in Daily Seed mode) the
daily board.

The Leaderboard screen presents the specific Tech Flow Runner board (never the
generic Game Center home) and offers a button per board: Overall, Daily,
Hardcore, Bit Rush, Feather Fall, Glass Cannon. DEBUG builds log Game Center
diagnostics to the Xcode console (`[GameCenter] …`) and show an on-screen debug
panel with the authenticated flag, player name, and presented board IDs.

Create these leaderboards in **App Store Connect → your app → Features →
Leaderboards** (Classic, Integer, High-to-Low) with these exact IDs, or edit
`LeaderboardID` in `Services/GameCenterManager.swift`:

```
techflow.highscore               Overall
techflow.highscore.none          No Modifier
techflow.highscore.hardcore      Hardcore
techflow.highscore.bitrush       Bit Rush
techflow.highscore.featherfall   Feather Fall
techflow.highscore.glasscannon   Glass Cannon
techflow.daily                   Daily Seed
```

Until they exist, submissions fail silently (logged in DEBUG) and the game still
saves local bests.

## Skins & Game Center achievements

Skins are cosmetic, render inside the identical player hitbox, and unlock from
*lifetime* stats. Thresholds are tuned so the set unlocks gradually over roughly
six weeks of regular play (an average ~60-second run ≈ 2,000 distance + ~20 bits;
a regular player ≈ 24 runs/week) rather than in a single session:

```
Pulse      Default (starter)
Sunset     Lifetime distance 25,000m     (~week 1)
Matrix     Lifetime distance 75,000m     (~week 2)
Bit Lord   1,500 lifetime bits           (~week 3)
Plasma     Lifetime distance 175,000m    (~week 4-5)
Bossbane   Defeat 20 bosses              (~week 5-6)
```

The skin picker shows the actual in-game art for each skin (rendered from the
SpriteKit `SkinRenderer` by `SkinIconRenderer`), dimmed behind a lock badge
while still locked.

Each skin unlock awards a Game Center achievement. Create one achievement per
skin in **App Store Connect → your app → Features → Achievements** with these
exact IDs (defined on `Skin.achievementID`):

```
techflow.skin.pulse      Pulse     (welcome — granted on first authenticated play)
techflow.skin.sunset     Sunset    (lifetime distance 25,000m)
techflow.skin.matrix     Matrix    (lifetime distance 75,000m)
techflow.skin.bitlord    Bit Lord  (1,500 lifetime bits)
techflow.skin.plasma     Plasma    (lifetime distance 175,000m)
techflow.skin.bossbane   Bossbane  (defeat 20 bosses)
```

Achievements are reported as 100% complete the first time a skin unlocks (with a
completion banner), and re-synced silently on each sign-in so progress earned
before achievements existed — or while signed out — is credited. Game Center
ignores already-earned reports, so this is idempotent.

## Daily Seed mode

There is no server. The daily seed is derived from the UTC date (`YYYYMMDD`) and
fed through a deterministic Mulberry32 RNG (`SeededRandom`) so every player on
the same app version traverses the same course for that day.

## Audio ownership

`Tech Flow.mp3` and all audio are © H3 Consulting Partners LLC and are bundled as an app
resource (never downloaded remotely).
