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
    case pulse
    case sunset
    case matrix
    case plasma
    case bitlord
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

    var unlock: SkinUnlock {
        switch self {
        case .pulse: return .always
        case .sunset: return .distance(1000)
        case .matrix: return .distance(2500)
        case .plasma: return .distance(5000)
        case .bitlord: return .bits(500)
        case .bossbane: return .bossKills(3)
        }
    }

    var unlockHint: String {
        switch self {
        case .pulse: return "Default"
        case .sunset: return "Lifetime distance 1,000"
        case .matrix: return "Lifetime distance 2,500"
        case .plasma: return "Lifetime distance 5,000"
        case .bitlord: return "Lifetime bits 500"
        case .bossbane: return "Defeat 3 bosses"
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
