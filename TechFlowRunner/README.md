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
`supportedInterfaceOrientationsFor`, with a fixed-landscape SpriteKit scene and,
on iPad multitasking where rotation can't be forced, a "Rotate Device to
Continue" overlay that pauses play. iPhone first; iPad is also supported.

> The Xcode project is generated from the on-disk source tree by
> `generate_project.py`. If you add/remove Swift files, re-run
> `python3 generate_project.py` from the `TechFlowRunner/` directory to refresh
> `TechFlowRunner.xcodeproj/project.pbxproj`.

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
      TerrainGenerator.swift, SkinRenderer.swift, GameState.swift,
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
unavailable. On a run end the score is submitted to the overall board, the
modifier-specific board, and (in Daily Seed mode) the daily board.

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

## Daily Seed mode

There is no server. The daily seed is derived from the UTC date (`YYYYMMDD`) and
fed through a deterministic Mulberry32 RNG (`SeededRandom`) so every player on
the same app version traverses the same course for that day.

## Audio ownership

`Tech Flow.mp3` and all audio are © H3 Consulting Partners LLC and are bundled as an app
resource (never downloaded remotely).
