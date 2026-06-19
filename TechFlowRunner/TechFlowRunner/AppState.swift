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

    // MARK: Stats
    @Published var best: Int
    @Published var lifetime: LifetimeStats

    let gameCenter = GameCenterManager.shared
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
        gameCenter.authenticate()
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
        gameCenter.showLeaderboard()
    }

    // MARK: Run control

    func startRun() {
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
