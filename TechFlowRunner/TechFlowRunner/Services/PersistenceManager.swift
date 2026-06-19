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
}
