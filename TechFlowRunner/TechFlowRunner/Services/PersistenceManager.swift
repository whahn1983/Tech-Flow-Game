//
//  PersistenceManager.swift
//  Tech Flow Runner
//
//  Local-only persistence backed by UserDefaults. There is no backend: best
//  score, lifetime stats, the selected skin, mute preference, last modifier,
//  reduced-motion override and recent run history all live on device.
//

import Foundation

struct LifetimeStats: Codable, Equatable {
    var distance: Double = 0
    var bits: Int = 0
    var runs: Int = 0
    var bossKills: Int = 0
}

struct RunRecord: Codable, Identifiable {
    var id = UUID()
    var score: Int
    var bits: Int
    var modifier: String
    var daily: Bool
    var date: Date
}

/// Whether the player has been asked about — and opted into — Apple Game
/// Center. Game Center uploads scores to global leaderboards and syncs
/// achievements, so (per App Store Review Guideline 5.1.2) the app must obtain
/// explicit consent before authenticating or uploading anything.
///
///   - `.notAsked`   First launch; no consent decision yet. Game Center stays
///                    dormant until the player chooses.
///   - `.offline`    The player declined; play stays fully local, nothing is
///                    uploaded, and Game Center is never authenticated
///                    automatically.
///   - `.consented`  The player opted in; Game Center may authenticate
///                    (including automatically on future launches) and upload
///                    scores / achievements.
enum GameCenterConsentState: String, Codable {
    case notAsked
    case offline
    case consented
}

final class PersistenceManager {
    static let shared = PersistenceManager()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let best = "tfr.bestScore"
        static let lifetime = "tfr.lifetime"
        static let skin = "tfr.skin"
        static let muted = "tfr.muted"           // legacy combined mute (pre volume controls)
        static let musicEnabled = "tfr.musicEnabled"
        static let sfxEnabled = "tfr.sfxEnabled"
        static let musicVolume = "tfr.musicVolume"
        static let sfxVolume = "tfr.sfxVolume"
        static let modifier = "tfr.lastModifier"
        static let reducedMotion = "tfr.reducedMotionOverride"
        static let showOnScreenControls = "tfr.showOnScreenControls"
        static let dailyEnabled = "tfr.dailyEnabled"
        static let history = "tfr.runHistory"
        static let gameCenterConsent = "tfr.gameCenterConsent"
        static let lives = "tfr.lives"
        static let livesAnchor = "tfr.livesAnchor"
        static let unlimitedLives = "tfr.unlimitedLives"
        static let unlimitedLivesSource = "tfr.unlimitedLivesSource"
        static let legacySupporterMessageShown = "tfr.legacySupporterMessageShown"
        #if DEBUG
        static let entitlementTestScenario = "tfr.debug.entitlementTestScenario"
        #endif
    }

    // MARK: Game Center consent (App Store Review Guideline 5.1.2)
    //
    // Defaults to `.notAsked` so a fresh install never authenticates Game
    // Center — or uploads any score — until the player has explicitly chosen.
    var gameCenterConsent: GameCenterConsentState {
        get { GameCenterConsentState(rawValue: defaults.string(forKey: Key.gameCenterConsent) ?? "") ?? .notAsked }
        set { defaults.set(newValue.rawValue, forKey: Key.gameCenterConsent) }
    }

    // MARK: Best score
    var bestScore: Int {
        get { defaults.integer(forKey: Key.best) }
        set { defaults.set(newValue, forKey: Key.best) }
    }

    // MARK: Lifetime stats
    var lifetime: LifetimeStats {
        get {
            guard let data = defaults.data(forKey: Key.lifetime),
                  let stats = try? JSONDecoder().decode(LifetimeStats.self, from: data) else {
                return LifetimeStats()
            }
            return stats
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.lifetime)
            }
        }
    }

    // MARK: Selected skin
    var selectedSkin: Skin {
        get { Skin(rawValue: defaults.string(forKey: Key.skin) ?? "") ?? .pulse }
        set { defaults.set(newValue.rawValue, forKey: Key.skin) }
    }

    // MARK: Mute (legacy combined flag, retained only to migrate old installs)
    var muted: Bool {
        get { defaults.bool(forKey: Key.muted) }
        set { defaults.set(newValue, forKey: Key.muted) }
    }

    // MARK: Independent audio channels
    //
    // Music and sound effects each have an enable toggle and a 0...1 volume.
    // When the new keys are absent we fall back to the legacy `muted` flag so a
    // previously-muted player stays muted after upgrading.

    var musicEnabled: Bool {
        get { defaults.object(forKey: Key.musicEnabled) as? Bool ?? !defaults.bool(forKey: Key.muted) }
        set { defaults.set(newValue, forKey: Key.musicEnabled) }
    }

    var sfxEnabled: Bool {
        get { defaults.object(forKey: Key.sfxEnabled) as? Bool ?? !defaults.bool(forKey: Key.muted) }
        set { defaults.set(newValue, forKey: Key.sfxEnabled) }
    }

    var musicVolume: Double {
        get { defaults.object(forKey: Key.musicVolume) as? Double ?? 0.55 }
        set { defaults.set(min(1, max(0, newValue)), forKey: Key.musicVolume) }
    }

    var sfxVolume: Double {
        get { defaults.object(forKey: Key.sfxVolume) as? Double ?? 1.0 }
        set { defaults.set(min(1, max(0, newValue)), forKey: Key.sfxVolume) }
    }

    // MARK: Last modifier
    var lastModifier: Modifier {
        get { Modifier(rawValue: defaults.string(forKey: Key.modifier) ?? "") ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Key.modifier) }
    }

    // MARK: Reduced-motion in-app override (in addition to the system setting)
    var reducedMotionOverride: Bool {
        get { defaults.bool(forKey: Key.reducedMotion) }
        set { defaults.set(newValue, forKey: Key.reducedMotion) }
    }

    // MARK: On-screen controls (Jump / Dash / Duck buttons)
    //
    // Defaults to on. Players who prefer the gesture controls can hide the
    // buttons so they don't overlap the play area. Absent key falls back to
    // visible so existing installs keep the buttons.
    var showOnScreenControls: Bool {
        get { defaults.object(forKey: Key.showOnScreenControls) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showOnScreenControls) }
    }

    // MARK: Daily seed toggle
    var dailyEnabled: Bool {
        get { defaults.bool(forKey: Key.dailyEnabled) }
        set { defaults.set(newValue, forKey: Key.dailyEnabled) }
    }

    // MARK: Recent run history (capped)
    var history: [RunRecord] {
        get {
            guard let data = defaults.data(forKey: Key.history),
                  let records = try? JSONDecoder().decode([RunRecord].self, from: data) else {
                return []
            }
            return records
        }
        set {
            let capped = Array(newValue.suffix(20))
            if let data = try? JSONEncoder().encode(capped) {
                defaults.set(data, forKey: Key.history)
            }
        }
    }

    func appendHistory(_ record: RunRecord) {
        var current = history
        current.append(record)
        history = current
    }

    // MARK: Lives (free-to-play energy pool)
    //
    // The game is free with a pool of lives; each run spends one, and one
    // regenerates every 15 minutes up to a maximum. `LivesManager` owns the
    // regeneration math — here we only store the raw values.
    //
    //   - `lives`        Current count. `nil` (absent key) on a fresh or
    //                    upgraded install so `LivesManager` can seed the pool
    //                    to full the first time.
    //   - `livesAnchor`  Wall-clock reference the current regen interval counts
    //                    from. Stored as a Unix timestamp; 0 (absent) means the
    //                    pool is full and no regeneration is in progress.
    //   - `unlimitedLives` Cached mirror of the "Unlimited Lives" IAP so the UI
    //                    reflects ownership instantly at launch. StoreKit's
    //                    entitlements are the source of truth (see StoreManager);
    //                    this is only a fast local cache.

    var lives: Int? {
        get { defaults.object(forKey: Key.lives) as? Int }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.lives)
            } else {
                defaults.removeObject(forKey: Key.lives)
            }
        }
    }

    var livesAnchor: Date? {
        get {
            let t = defaults.double(forKey: Key.livesAnchor)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.livesAnchor) }
    }

    var unlimitedLives: Bool {
        get { defaults.bool(forKey: Key.unlimitedLives) }
        set { defaults.set(newValue, forKey: Key.unlimitedLives) }
    }

    // MARK: Unlimited Lives entitlement source
    //
    // The single cached model for WHY Unlimited Lives is active (see
    // `UnlimitedLivesSource`). StoreKit's verified transactions are the source
    // of truth (StoreManager); this caches the last verified result so the
    // entitlement keeps working offline and the UI can distinguish an original
    // paid-app owner from an IAP purchaser.
    //
    // Migration: installs that predate this key stored only the `unlimitedLives`
    // bool. A previously-owned entitlement there could only have come from the
    // $2.99 IAP (legacy grandfathering did not exist yet), so we map a legacy
    // `true` to `.purchasedIAP`. StoreManager re-verifies on next launch either
    // way.
    var unlimitedLivesSource: UnlimitedLivesSource {
        get {
            if let raw = defaults.string(forKey: Key.unlimitedLivesSource),
               let source = UnlimitedLivesSource(rawValue: raw) {
                return source
            }
            return defaults.bool(forKey: Key.unlimitedLives) ? .purchasedIAP : .none
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.unlimitedLivesSource)
            // Keep the legacy bool mirror in lockstep so `LivesManager` and any
            // older code path still read a correct "is unlimited" value.
            defaults.set(newValue != .none, forKey: Key.unlimitedLives)
        }
    }

    // MARK: Early Supporter message (one-time)
    //
    // Whether the one-time "Early Supporter Upgrade" message has been shown and
    // acknowledged. Tracked SEPARATELY from the entitlement itself so the
    // entitlement flag can never be mistaken for "message already shown".
    // Defaults to false; set true (and persisted immediately) when the user
    // taps Continue on the message.
    var legacySupporterMessageShown: Bool {
        get { defaults.bool(forKey: Key.legacySupporterMessageShown) }
        set { defaults.set(newValue, forKey: Key.legacySupporterMessageShown) }
    }

    #if DEBUG
    // MARK: Developer entitlement override (DEBUG builds only)
    //
    // Simulates each entitlement state without real StoreKit history. Compiled
    // out of Release builds entirely (see EntitlementTestScenario). Persisted so
    // a chosen scenario survives relaunch during testing.
    var entitlementTestScenario: EntitlementTestScenario {
        get {
            EntitlementTestScenario(rawValue: defaults.string(forKey: Key.entitlementTestScenario) ?? "")
                ?? .disabled
        }
        set { defaults.set(newValue.rawValue, forKey: Key.entitlementTestScenario) }
    }
    #endif
}
