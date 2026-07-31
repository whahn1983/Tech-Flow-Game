//
//  LivesManager.swift
//  Tech Flow Runner
//
//  The free-to-play lives ("energy") system. The game is free to download and
//  play; each run spends one life, and lives regenerate over real time so a
//  session is naturally paced. Players who want to play without waiting can buy
//  the one-time "Unlimited Lives" in-app purchase (see StoreManager), which
//  makes the pool effectively infinite.
//
//  ───────────────────────────────────────────────────────────────────────────
//  RULES
//  ───────────────────────────────────────────────────────────────────────────
//    • Start with 10 lives (a fresh install seeds a full pool).
//    • Each started run costs 1 life.
//    • 1 life regenerates every 15 minutes, up to a maximum of 10.
//    • Unlimited Lives (IAP) bypasses all of the above — runs never cost a life.
//
//  ───────────────────────────────────────────────────────────────────────────
//  REGENERATION MODEL
//  ───────────────────────────────────────────────────────────────────────────
//  Regeneration is computed from the wall clock, not a running timer, so it
//  keeps accruing while the app is backgrounded or terminated. Persistence
//  stores the current `lives` count and a single `anchor` timestamp: the moment
//  the currently-regenerating life started counting. `refresh()` reconciles the
//  count against elapsed time on demand (at launch, on foreground, and once a
//  second while the menu is visible), granting whole lives and advancing the
//  anchor by the intervals consumed so sub-interval progress is never lost.
//

import SwiftUI

@MainActor
final class LivesManager: ObservableObject {
    static let shared = LivesManager()

    /// Maximum lives the pool can hold and the amount a fresh install starts
    /// with.
    static let maxLives = 10
    /// Real time between regenerated lives.
    static let regenInterval: TimeInterval = 15 * 60   // 15 minutes

    /// Current life count (0...maxLives). Ignored while `unlimited` is true.
    @Published private(set) var lives: Int
    /// True once the Unlimited Lives IAP is owned. Mirrored from StoreManager.
    @Published private(set) var unlimited: Bool
    /// Wall-clock time the next life will be granted, or nil when the pool is
    /// full or unlimited. Published so countdown UIs re-render as it changes.
    @Published private(set) var nextLifeDate: Date?

    private let persistence = PersistenceManager.shared

    private init() {
        let stored = persistence.lives ?? Self.maxLives   // fresh install → full
        lives = min(Self.maxLives, max(0, stored))
        unlimited = persistence.unlimitedLives
        // Reconcile against any time that elapsed while the app was closed.
        refresh()
    }

    /// True when the pool is at its maximum (no regeneration in progress).
    var isFull: Bool { lives >= Self.maxLives }

    /// True when a run may be started right now.
    var canStartRun: Bool { unlimited || lives > 0 }

    // MARK: - Regeneration

    /// Reconciles `lives` with the wall clock, granting any lives that
    /// regenerated since the stored anchor and refreshing `nextLifeDate`. Cheap
    /// and idempotent — safe to call every second to drive a live countdown.
    func refresh() {
        guard !unlimited else {
            clearAnchorIfNeeded()
            nextLifeDate = nil
            return
        }
        guard lives < Self.maxLives else {
            // Full: nothing regenerating.
            clearAnchorIfNeeded()
            nextLifeDate = nil
            return
        }

        let now = Date()
        guard let anchor = persistence.livesAnchor else {
            // Below max with no clock running (just dropped below max, or a
            // migrated install): start the regen interval from now.
            persistence.livesAnchor = now
            nextLifeDate = now.addingTimeInterval(Self.regenInterval)
            return
        }

        let elapsed = now.timeIntervalSince(anchor)
        guard elapsed >= 0 else {
            // Device clock moved backwards — restart the interval from now
            // rather than granting a windfall or stalling forever.
            persistence.livesAnchor = now
            nextLifeDate = now.addingTimeInterval(Self.regenInterval)
            return
        }

        let gained = Int(elapsed / Self.regenInterval)
        guard gained > 0 else {
            // Still within the current interval; just surface the target.
            nextLifeDate = anchor.addingTimeInterval(Self.regenInterval)
            return
        }

        let newLives = min(Self.maxLives, lives + gained)
        setLives(newLives)
        if newLives >= Self.maxLives {
            persistence.livesAnchor = nil
            nextLifeDate = nil
        } else {
            // Carry the leftover sub-interval progress into the next interval.
            let advanced = anchor.addingTimeInterval(Double(gained) * Self.regenInterval)
            persistence.livesAnchor = advanced
            nextLifeDate = advanced.addingTimeInterval(Self.regenInterval)
        }
    }

    // MARK: - Spending

    /// Spends one life to start a run. Returns whether the run may proceed:
    /// always true with Unlimited Lives; otherwise true iff a life was
    /// available and has now been deducted.
    @discardableResult
    func consume() -> Bool {
        if unlimited { return true }
        refresh()
        guard lives > 0 else { return false }

        let wasFull = (lives == Self.maxLives)
        setLives(lives - 1)
        if wasFull {
            // Leaving a full pool starts the regeneration clock. When already
            // below full, the in-progress interval keeps running untouched.
            persistence.livesAnchor = Date()
        }
        refresh()   // recompute nextLifeDate for the new count
        return true
    }

    // MARK: - Unlimited Lives (IAP)

    /// Mirrors the Unlimited Lives entitlement into the lives model. StoreManager
    /// is the source of truth and calls this whenever ownership changes.
    func setUnlimited(_ value: Bool) {
        guard unlimited != value else { return }
        unlimited = value
        persistence.unlimitedLives = value
        refresh()
    }

    // MARK: - Helpers

    private func setLives(_ value: Int) {
        let clamped = min(Self.maxLives, max(0, value))
        if clamped != lives { lives = clamped }
        persistence.lives = clamped
    }

    private func clearAnchorIfNeeded() {
        if persistence.livesAnchor != nil { persistence.livesAnchor = nil }
    }

    #if DEBUG
    /// Debug-only: refill the pool to full (used from the in-app debug panel).
    func debugRefill() {
        setLives(Self.maxLives)
        persistence.livesAnchor = nil
        refresh()
    }

    /// Debug-only: drain the pool to empty to exercise the paywall flow.
    func debugDrain() {
        setLives(0)
        persistence.livesAnchor = Date()
        refresh()
    }
    #endif
}
