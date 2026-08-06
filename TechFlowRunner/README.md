# Tech Flow Runner — Native iOS App

A standalone native iOS game built with **Swift, SwiftUI, SpriteKit, GameKit,
StoreKit, and AVFoundation**. It recreates the gameplay identity of the Tech
Flow Runner web game natively — a neon/circuit-board endless runner with
jumping, double jumping, ducking, dashing, collectible bits, combos, power-ups,
progressive levels, and a Mainframe boss fight — with **no backend**:
leaderboards use Game Center and all settings/progress persist locally.

The game is **free to play** with a regenerating pool of lives; a single
one-time in-app purchase (**Unlimited Lives Forever**) removes the wait. See
[Monetization](#monetization--lives--in-app-purchase) below.

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
                                 PersistenceManager, HapticsManager,
                                 LivesManager (free-to-play lives),
                                 StoreManager (StoreKit 2 IAP)
    UI/                          SwiftUI menus / HUD / overlays / pickers
                                 (LivesView, LivesStoreView paywall)
    Resources/Tech Flow.mp3      Bundled looping soundtrack (© H3 Consulting Partners LLC)
    Assets.xcassets              App icon slot + accent color
    TechFlowRunner.entitlements  Game Center capability
  Products.storekit              StoreKit config for local IAP testing (scheme-referenced)
```

## Controls

- **Tap** — jump / double jump
- **Swipe down (hold)** — duck
- **Swipe right** — dash
- **On-screen buttons** — Jump / Duck / Dash (accessibility fallback) + Pause

## Monetization — lives & in-app purchase

The app is **free to download and play** on a lives (energy) model:

```
Start with     10 lives (a fresh install seeds a full pool)
Each run costs  1 life
Regeneration    1 life every 15 minutes
Maximum         10 lives
```

Lives regenerate from the **wall clock**, so they keep accruing while the app is
backgrounded or closed. `LivesManager` stores the current count plus a single
anchor timestamp and reconciles on demand (launch, foreground, and once a second
while the menu is visible), granting whole lives and carrying sub-interval
progress forward so no partial regen is lost. The menu shows the current pool and
a live countdown to the next life; when the pool is empty, Start Run and Reboot
Run become an **Out of Lives** prompt that opens the store (the player can also
just wait).

### Unlimited Lives Forever (one-time IAP)

A single **non-consumable** in-app purchase removes the lives limit entirely —
runs never cost a life. It is implemented with **StoreKit 2** in `StoreManager`:

- Ownership is derived from `Transaction.currentEntitlements` (the source of
  truth, resolved even offline once purchased) and mirrored into a cached
  `PersistenceManager.unlimitedLives` flag so the UI is correct instantly at
  launch. A `Transaction.updates` listener picks up Ask-to-Buy approvals,
  purchases made on another device, and refunds.
- A **Restore Purchases** action (`AppStore.sync()`) is offered in the paywall
  and in Settings, satisfying App Store Review Guideline 3.1.1.
- The paywall (`LivesStoreView`) is reachable from the menu lives panel, the
  Out-of-Lives prompts (menu and game-over), and Settings.
- The paywall shows the full purchase disclosure — product name, price, that it
  is a one-time non-consumable that does not auto-renew, and that payment is
  charged to the Apple Account at confirmation — plus links to the **Terms of
  Use (Apple's standard EULA, `TermsOfUse.url`)** and the **Privacy Policy
  (`PrivacyPolicy.url`, hosted on GitHub Pages)**. The same two links also
  appear in Settings. If you configure a custom EULA in App Store Connect,
  update `TermsOfUse.url` in `Services/StoreManager.swift` to match.

Create a single **Non-Consumable** IAP in **App Store Connect → your app →
Features → In-App Purchases** with this exact Product ID (suggested price Tier 3,
$2.99), or edit `StoreProductID` in `Services/StoreManager.swift`:

```
com.whahn1983.techflowrunner.unlimitedlives   Unlimited Lives Forever
```

No entitlement changes are needed (StoreKit 2 auto-links via `import StoreKit`);
enable the **In-App Purchase** capability on the App ID in App Store Connect.

**Local testing without App Store Connect:** the shared scheme references
`Products.storekit` (a StoreKit configuration file defining the same product), so
the purchase and restore flows work in the simulator. In `Debug` builds you can
also drive the state from code via `LivesManager.debugRefill()` /
`debugDrain()`. In the simulator you can clear a test purchase with
**Debug → StoreKit → Manage Transactions**.

### Early Supporter grandfathering (original paid-app owners)

Tech Flow Runner was originally a **paid ($0.99)** download before it went free.
Anyone who bought that version is granted **Unlimited Lives permanently, for
free** — they are never asked to pay the $2.99. This is handled by
`Services/LegacyPaidAppEligibility.swift` together with `StoreManager`:

- Eligibility uses StoreKit 2's **app-level** transaction,
  `AppTransaction.shared` (the **verified** result only). On iOS its
  `originalAppVersion` is the `CFBundleVersion` (build number) the customer
  first acquired, and `originalPurchaseDate` is when they acquired it.
- A user counts as **paid** (and is grandfathered) if **either**:
  1. their original build is **at or before** `lastPaidBuildNumber` — compared
     **component-wise numerically** (so `"10"` sorts after `"2"`), covering the
     whole paid ($0.99) era; **or**
  2. their `originalPurchaseDate` is **before** `freeTransitionDate` — covering
     the transition window where the free-model build is already live but its
     price hasn't been dropped yet, so those buyers download the *same build* as
     later free users and can only be told apart by purchase date.
- We do **not** grant based on merely having a receipt/app transaction — free
  downloads have one too.
- Both entitlement sources are unified under `UnlimitedLivesSource`
  (`.purchasedIAP` / `.legacyPaidApp`); the app reasons about
  `StoreManager.hasUnlimitedLives`. Resolution priority: verified IAP → verified
  legacy → locally cached (kept offline) → none. A previously-verified
  entitlement is **never revoked** because a later check fails on a bad network.
- Grandfathered users see a one-time **"Early Supporter Upgrade"** message
  (gated by the separate `legacySupporterMessageShown` flag), and the store /
  Settings show **"Early Supporter Access"** instead of the purchase button.

> ⚠️ **Release-engineering invariants — verify before every submission:**
>
> 1. `LegacyPaidAppEligibility.lastPaidBuildNumber` **must equal the final
>    `CFBundleVersion` that was live on the App Store while the app cost $0.99**
>    (check the paid version's Build number in App Store Connect). It is `"7"`
>    (marketing 1.0 shipped at build 7). Note iOS compares the **build number**,
>    not the marketing version.
> 2. The shipping build's **`CURRENT_PROJECT_VERSION` must be strictly greater
>    than that cutoff.** It is `8` for the free release (also the next valid
>    build after the paid build 7). If a free build ever shipped at a number ≤
>    the cutoff, those free users would be wrongly grandfathered.
> 3. To grandfather **transition-window buyers** (people who pay $0.99 for the
>    build 8 release before you remove the price), set
>    `LegacyPaidAppEligibility.freeTransitionDate` to at/before the moment you
>    change the App Store price to free. Leaving it `nil` relies on the build
>    cutoff alone — safe (never grandfathers a free user) but does not cover the
>    transition window. Since build 8 is the *same* build whether bought at
>    $0.99 or downloaded free later, the purchase date is the only signal that
>    separates those two groups.

**Simulating entitlement states:** because the StoreKit sandbox's
`originalAppVersion` doesn't reproduce real paid-app history, `Debug` builds get
a **Developer → Entitlement Override** picker in Settings that forces a legacy
owner (message pending or already seen), an IAP owner, or a free user. It is
compiled out of Release builds entirely.

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
