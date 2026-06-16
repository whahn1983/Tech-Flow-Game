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
    /// landscape (e.g. iPad held portrait, Split View, Stage Manager). Drives
    /// the "Rotate Device to Continue" fallback overlay and disables input.
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
        didSet { persistence.dailyEnabled = dailyEnabled }
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
    // Initial size is a placeholder; the scene uses .resizeFill and adopts the
    // hosting SKView's bounds when presented.
    let scene = TechFlowGameScene(size: CGSize(width: 1024, height: 768))

    private let persistence = PersistenceManager.shared

    init() {
        selectedModifier = persistence.lastModifier
        dailyEnabled = persistence.dailyEnabled
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

    func showLeaderboard(_ id: String = LeaderboardID.overall) {
        gameCenter.showLeaderboard(id)
    }

    // MARK: Run control

    func startRun() {
        // Lock the interface to landscape before the gameplay view appears so
        // iOS rotates into landscape as the transition happens. The SpriteKit
        // scene additionally waits for a landscape layout before building the
        // run (see TechFlowGameScene.update), so play never begins in portrait.
        OrientationManager.shared.lockLandscape()
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
            if pausedForOrientation {
                pausedForOrientation = false
                resume()
            }
        } else {
            awaitingLandscape = true
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

        // Lifetime stats
        var stats = lifetime
        stats.distance += Double(points)
        stats.bits += bits
        stats.runs += 1
        stats.bossKills += bossKills
        lifetime = stats
        persistence.lifetime = stats

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
