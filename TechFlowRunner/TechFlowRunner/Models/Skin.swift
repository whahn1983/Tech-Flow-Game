//
//  Skin.swift
//  Tech Flow Runner
//
//  Cosmetic, unlockable player skins. Every skin renders inside the same
//  player bounding box so the collision hitbox is identical regardless of the
//  selected skin. Unlock thresholds read from lifetime stats.
//

import SwiftUI
import UIKit

enum SkinUnlock {
    case always
    case distance(Double)
    case bits(Int)
    case bossKills(Int)
}

enum Skin: String, CaseIterable, Identifiable, Codable {
    // Cases are listed in their rough unlock order so the picker grid reads as a
    // progression. The thresholds below are tuned (see `unlock`) so the set
    // unlocks gradually over several weeks of regular play rather than in a
    // single session.
    case pulse
    case sunset
    case matrix
    case bitlord
    case plasma
    case bossbane

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pulse: return "Pulse"
        case .sunset: return "Sunset"
        case .matrix: return "Matrix"
        case .plasma: return "Plasma"
        case .bitlord: return "Bit Lord"
        case .bossbane: return "Bossbane"
        }
    }

    /// Unlock thresholds read from *lifetime* (cumulative) stats.
    ///
    /// Calibration (see the SkinPickerView header and the PR notes): an average
    /// ~60-second run yields roughly 2,000 lifetime distance and ~20 bits, and a
    /// regular player completes ~24 runs/week (~48,000 distance, ~480 bits and a
    /// handful of boss kills per week). The thresholds below therefore stagger
    /// the unlocks across roughly six weeks of play:
    ///
    ///   Sunset   ≈ end of week 1   (25,000 distance)
    ///   Matrix   ≈ week 2          (75,000 distance)
    ///   Bit Lord ≈ week 3          (1,500 lifetime bits)
    ///   Plasma   ≈ week 4-5        (175,000 distance)
    ///   Bossbane ≈ week 5-6        (20 bosses defeated)
    var unlock: SkinUnlock {
        switch self {
        case .pulse: return .always
        case .sunset: return .distance(25_000)
        case .matrix: return .distance(75_000)
        case .bitlord: return .bits(1_500)
        case .plasma: return .distance(175_000)
        case .bossbane: return .bossKills(20)
        }
    }

    var unlockHint: String {
        switch self {
        case .pulse: return "Default"
        case .sunset: return "Lifetime distance 25,000m"
        case .matrix: return "Lifetime distance 75,000m"
        case .bitlord: return "Collect 1,500 lifetime bits"
        case .plasma: return "Lifetime distance 175,000m"
        case .bossbane: return "Defeat 20 bosses"
        }
    }

    /// Game Center achievement identifier awarded the first time this skin
    /// unlocks. Must match the Achievement IDs configured in App Store Connect
    /// (see GameCenterManager's setup notes). Pulse is the default skin and has
    /// a "welcome" achievement granted on first authenticated play.
    var achievementID: String {
        switch self {
        case .pulse: return "techflow.skin.pulse"
        case .sunset: return "techflow.skin.sunset"
        case .matrix: return "techflow.skin.matrix"
        case .bitlord: return "techflow.skin.bitlord"
        case .plasma: return "techflow.skin.plasma"
        case .bossbane: return "techflow.skin.bossbane"
        }
    }

    /// [primary, secondary] neon colors used by the SpriteKit renderer.
    var colors: [UIColor] {
        switch self {
        case .pulse: return [UIColor(hex: 0x2EF8FF), UIColor(hex: 0x8E5CFF)]
        case .sunset: return [UIColor(hex: 0xFFD95C), UIColor(hex: 0xFF5A7C)]
        case .matrix: return [UIColor(hex: 0x75FFD4), UIColor(hex: 0x16F06B)]
        case .plasma: return [UIColor(hex: 0xFF5CD1), UIColor(hex: 0x8E5CFF)]
        case .bitlord: return [UIColor(hex: 0xFFD95C), UIColor(hex: 0x2EF8FF)]
        case .bossbane: return [UIColor(hex: 0xFF5A7C), UIColor(hex: 0xFFD95C)]
        }
    }

    var swiftUIColors: [Color] { colors.map { Color($0) } }

    func isUnlocked(distance: Double, bits: Int, bossKills: Int) -> Bool {
        switch unlock {
        case .always: return true
        case .distance(let d): return distance >= d
        case .bits(let b): return bits >= b
        case .bossKills(let k): return bossKills >= k
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
