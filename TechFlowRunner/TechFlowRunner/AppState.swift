//
//  AppState.swift
//  Tech Flow Runner
//
//  The app-wide coordinator. Owns the single SpriteKit scene, the run-state
//  machine, menu selections, local persistence and Game Center submission. It
//  is the scene's delegate, translating gameplay callbacks into published state
//  the SwiftUI layer renders.
//

import SwiftUI
import GameKit

@MainActor
final class AppState: ObservableObject {

    // MARK: Run-state machine
    @Published var runState: RunState = .menu
    @Published var hud = HUDSnapshot()
    @Published var runResult = RunResult()

    /// True while a run is active but the gameplay view is not laid out in
    /// landscape (a run started in portrait, the device turned mid-run, or iPad
    /// Split View / Stage Manager). Drives the "Rotate Device to Continue"
    /// overlay and disables input.
    @Published var awaitingLandscape = false

    /// Tracks a pause that was triggered solely by the device leaving landscape,
    /// so we can auto-resume when landscape is restored without clobbering a
    /// pause the player requested themselves.
    private var pausedForOrientation = false

    // MARK: Menu selections (persisted)
    @Published var selectedModifier: Modifier {
        didSet { persistence.lastModifier = selectedModifier }
    }
    @Published var selectedSkin: Skin {
        didSet { persistence.selectedSkin = selectedSkin }
    }
    @Published var dailyEnabled: Bool {
        didSet {
            persistence.dailyEnabled = dailyEnabled
            // The daily seed is a shared, fixed course, so it always runs with
            // no modifier. Pin the selection to .none while daily is enabled.
            if dailyEnabled { selectedModifier = .none }
        }
    }
    @Published var musicEnabled: Bool {
        didSet { AudioManager.shared.setMusicEnabled(musicEnabled) }
    }
    @Published var sfxEnabled: Bool {
        didSet { AudioManager.shared.setSfxEnabled(sfxEnabled) }
    }
    @Published var musicVolume: Double {
        didSet { AudioManager.shared.setMusicVolume(musicVolume) }
    }
    @Published var sfxVolume: Double {
        didSet { AudioManager.shared.setSfxVolume(sfxVolume) }
    }
    @Published var reducedMotionOverride: Bool {
        didSet { persistence.reducedMotionOverride = reducedMotionOverride }
    }
    @Published var showOnScreenControls: Bool {
        didSet { persistence.showOnScreenControls = showOnScreenControls }
    }

    // MARK: Stats
    @Published var best: Int
    @Published var lifetime: LifetimeStats

    /// Drives the first-run Game Center consent dialog (App Store Review
    /// Guideline 5.1.2). Set true once, after the menu first appears, when the
    /// player has never been asked. The dialog itself records the decision.
    @Published var showGameCenterConsent = false

    /// Drives the Unlimited Lives store / paywall sheet. Set true when the
    /// player runs out of lives (menu or game-over) or taps the store CTA.
    @Published var showLivesStore = false

    let gameCenter = GameCenterManager.shared
    let lives = LivesManager.shared
    let store = StoreManager.shared
    // The scene is locked to the fixed reference design size and uniformly
    // scaled (aspect-fit) onto every device, so the playable area is identical
    // regardless of screen size.
    let scene = TechFlowGameScene(size: GameConstants.designSize)

    private let persistence = PersistenceManager.shared

    init() {
        let dailyEnabled = persistence.dailyEnabled
        self.dailyEnabled = dailyEnabled
        // Daily seed always runs with no modifier (see dailyEnabled.didSet).
        selectedModifier = dailyEnabled ? .none : persistence.lastModifier
        reducedMotionOverride = persistence.reducedMotionOverride
        showOnScreenControls = persistence.showOnScreenControls
        best = persistence.bestScore
        lifetime = persistence.lifetime
        musicEnabled = persistence.musicEnabled
        sfxEnabled = persistence.sfxEnabled
        musicVolume = persistence.musicVolume
        sfxVolume = persistence.sfxVolume

        // Validate the persisted skin against current unlock progress.
        let stats = persistence.lifetime
        let saved = persistence.selectedSkin
        if saved.isUnlocked(distance: stats.distance, bits: stats.bits, bossKills: stats.bossKills) {
            selectedSkin = saved
        } else {
            selectedSkin = .pulse
        }

        scene.gameDelegate = self
        // Load the persisted Game Center consent decision so the manager knows
        // whether it's allowed to authenticate. This does NOT authenticate —
        // that's deferred to onLaunch()/the consent dialog.
        gameCenter.configure(consentState: persistence.gameCenterConsent)
        // Once Game Center signs in, credit achievements for every skin already
        // unlocked (covers installs that earned skins before achievements
        // existed, and players who sign in after playing offline).
        gameCenter.onAuthenticated = { [weak self] in
            self?.syncSkinAchievements()
        }
        // Property observers don't fire during init, so push the persisted
        // audio settings into the AudioManager explicitly.
        AudioManager.shared.setMusicEnabled(musicEnabled)
        AudioManager.shared.setSfxEnabled(sfxEnabled)
        AudioManager.shared.setMusicVolume(musicVolume)
        AudioManager.shared.setSfxVolume(sfxVolume)
    }

    // MARK: Derived

    var effectiveReducedMotion: Bool {
        UIAccessibility.isReduceMotionEnabled || reducedMotionOverride
    }

    var unlockedSkins: [Skin] {
        Skin.allCases.filter {
            $0.isUnlocked(distance: lifetime.distance, bits: lifetime.bits, bossKills: lifetime.bossKills)
        }
    }

    func isUnlocked(_ skin: Skin) -> Bool {
        skin.isUnlocked(distance: lifetime.distance, bits: lifetime.bits, bossKills: lifetime.bossKills)
    }

    /// Reports a Game Center achievement for every currently-unlocked skin. Safe
    /// to call repeatedly — Game Center ignores already-earned achievements — so
    /// it both backfills past progress and is the entry point for the run-end
    /// delta. Banners are suppressed here so a sync never re-toasts old unlocks.
    func syncSkinAchievements() {
        let unlocked = unlockedSkins
        Task { await gameCenter.reportSkinAchievements(unlocked, showBanner: false) }
    }

    var dailySeedDateString: String { RandomSource.dailySeedDateString() }

    // MARK: Lifecycle

    func onLaunch() {
        AudioManager.shared.configureSession()
        AudioManager.shared.prepareMusic()
        HapticsManager.shared.prepare()
        // Only authenticate when the player previously opted in. A fresh install
        // (.notAsked) or an offline player never triggers Game Center sign-in
        // here — App Store Review Guideline 5.1.2.
        gameCenter.authenticateIfConsented()
        // Load the Unlimited Lives product and reconcile ownership with StoreKit,
        // then bring the lives pool up to date for time elapsed while away.
        store.start()
        lives.refresh()
    }

    /// Reconciles the lives pool with the wall clock. Called when the app
    /// returns to the foreground so regenerated lives appear immediately.
    func refreshLives() {
        lives.refresh()
    }

    /// True when a run can begin right now (a life is available or Unlimited
    /// Lives is owned).
    var canStartRun: Bool { lives.canStartRun }

    /// Called by the main menu after it first appears. Presents the one-time
    /// Game Center consent dialog when the player has never been asked, so the
    /// choice is made before any run starts.
    func presentConsentDialogIfNeeded() {
        guard gameCenter.consentState == .notAsked else { return }
        showGameCenterConsent = true
    }

    /// Records the player's choice from a consent dialog (first-run or the
    /// Settings/leaderboard connect flow) and authenticates when they opt in.
    func resolveGameCenterConsent(connect: Bool) {
        showGameCenterConsent = false
        if connect {
            gameCenter.requestConsentAndAuthenticate()
        } else {
            gameCenter.goOffline()
        }
    }

    // MARK: Menu actions

    func selectModifier(_ modifier: Modifier) { selectedModifier = modifier }

    func selectSkin(_ skin: Skin) {
        guard isUnlocked(skin) else { return }
        selectedSkin = skin
    }

    func toggleMusic() {
        musicEnabled.toggle()
    }

    func showLeaderboard() {
        switch gameCenter.consentState {
        case .consented:
            // Opted in: present the native Game Center UI (which itself retries
            // sign-in if the session isn't authenticated).
            gameCenter.showLeaderboard()
        case .notAsked, .offline:
            // Never open Game Center before consent — surface the optional
            // connect / play-offline choice (with the privacy policy) instead.
            showGameCenterConsent = true
        }
    }

    // MARK: Run control

    func startRun() {
        // Free-to-play gate: each run spends one life (Unlimited Lives bypasses
        // this). When the pool is empty, surface the store / wait prompt instead
        // of starting — this also covers "Reboot Run" from the game-over screen.
        guard lives.consume() else {
            showLivesStore = true
            return
        }

        // Don't force a rotation here. The interface is left free to follow the
        // device's physical orientation so that, if it's already landscape, the
        // geometry callback locks it in; if it's portrait, the player sees the
        // "Rotate Device to Continue" overlay until they turn the device. This
        // gives iPhone the same rotate-to-play prompt as iPad, instead of
        // snapping into a sideways landscape layout while held in portrait.
        pausedForOrientation = false

        let seedValue: UInt32? = dailyEnabled ? RandomSource.dailySeed() : nil
        let config = RunConfig(
            modifier: selectedModifier,
            skin: isUnlocked(selectedSkin) ? selectedSkin : .pulse,
            dailySeed: dailyEnabled,
            seedValue: seedValue,
            seedDate: dailyEnabled ? RandomSource.dailySeedDateString() : "",
            reducedMotion: effectiveReducedMotion
        )
        scene.configureRun(config: config, best: best)
        scene.startRun()
        runState = .running
        if musicEnabled { AudioManager.shared.startMusic() }
    }

    func restartRun() {
        startRun()
    }

    func pause() {
        guard runState == .running else { return }
        scene.pauseRun()
        runState = .paused
        AudioManager.shared.pauseMusic()
    }

    func resume() {
        guard runState == .paused else { return }
        scene.resumeRun()
        runState = .running
        if musicEnabled { AudioManager.shared.startMusic() }
    }

    func returnToMenu() {
        runState = .menu
        awaitingLandscape = false
        pausedForOrientation = false
        AudioManager.shared.pauseMusic()
        // Restore the menu orientation behaviour (portrait allowed again).
        OrientationManager.shared.unlock()
    }

    // MARK: Orientation gating

    /// Called by the gameplay view whenever its layout size changes. While a run
    /// is active, a non-landscape layout pauses the run and shows the rotate
    /// overlay; restoring landscape resumes a run that was paused for this reason.
    func gameViewGeometryChanged(isLandscape: Bool) {
        guard runState == .running || runState == .paused else {
            awaitingLandscape = false
            return
        }

        if isLandscape {
            awaitingLandscape = false
            // The device is physically landscape, so pin the interface there for
            // the rest of the run. Locking only once we're already landscape
            // guarantees the forced rotation never lands sideways on iPhone.
            OrientationManager.shared.lockLandscape()
            if pausedForOrientation {
                pausedForOrientation = false
                resume()
            }
        } else {
            awaitingLandscape = true
            // Release any landscape lock so the interface can follow the device
            // into portrait and surface the rotate overlay. On iPhone the lock
            // normally holds landscape during play; this primarily matters when
            // a run first starts in portrait (and for iPad multitasking, where
            // the lock is declined and the view can be laid out portrait).
            OrientationManager.shared.unlock()
            if runState == .running {
                pausedForOrientation = true
                pause()
            }
        }
    }
}

// MARK: - Scene delegate

extension AppState: TechFlowGameSceneDelegate {

    nonisolated func sceneDidUpdateHUD(_ snapshot: HUDSnapshot) {
        Task { @MainActor in
            self.hud = snapshot
        }
    }

    nonisolated func sceneDidEndRun(points: Int, bits: Int, bossKills: Int) {
        Task { @MainActor in
            self.handleRunEnd(points: points, bits: bits, bossKills: bossKills)
        }
    }

    private func handleRunEnd(points: Int, bits: Int, bossKills: Int) {
        // Reconcile the lives pool so the game-over overlay's badge and the
        // Reboot / Out-of-Lives button reflect any lives regenerated during play.
        lives.refresh()

        let modifier = selectedModifier
        let daily = dailyEnabled
        let seedDate = daily ? RandomSource.dailySeedDateString() : ""

        // Local best
        let isNewBest = points > best
        if isNewBest {
            best = points
            persistence.bestScore = points
        }

        // Snapshot which skins were unlocked before this run's stats land, so we
        // can detect (and award Game Center achievements for) any that cross
        // their threshold as a result of this run.
        let previouslyUnlocked = Set(unlockedSkins)

        // Lifetime stats
        var stats = lifetime
        stats.distance += Double(points)
        stats.bits += bits
        stats.runs += 1
        stats.bossKills += bossKills
        lifetime = stats
        persistence.lifetime = stats

        // Award achievements for any skins this run just unlocked (with banner).
        let newlyUnlocked = unlockedSkins.filter { !previouslyUnlocked.contains($0) }
        if !newlyUnlocked.isEmpty {
            Task { await gameCenter.reportSkinAchievements(newlyUnlocked, showBanner: true) }
        }

        // History
        persistence.appendHistory(RunRecord(score: points, bits: bits,
                                             modifier: modifier.rawValue, daily: daily, date: Date()))

        // Build the game-over result; submission resolves asynchronously.
        var result = RunResult()
        result.points = points
        result.bits = bits
        result.modifier = modifier
        result.daily = daily
        result.seedDate = seedDate
        result.isNewBest = isNewBest
        result.submission = .pending
        runResult = result
        runState = .gameOver

        // Submit to Game Center (best-effort; never blocks play).
        guard points > 0 else {
            runResult.submission = .localOnly
            return
        }
        // Offline / not-yet-asked players never upload: report local-only
        // without surfacing a sign-in prompt or error during normal play.
        guard gameCenter.consentState == .consented else {
            runResult.submission = .localOnly
            return
        }
        Task {
            let outcome = await gameCenter.submit(score: points, modifier: modifier, daily: daily)
            switch outcome {
            case .submitted: runResult.submission = .submitted
            case .notAuthenticated: runResult.submission = .notSignedIn
            case .failed: runResult.submission = .localOnly
            }
        }
    }
}
