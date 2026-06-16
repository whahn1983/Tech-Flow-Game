//
//  Modifier.swift
//  Tech Flow Runner
//
//  Run modifiers chosen on the main menu before a run. A modifier is captured
//  at run start and held for the whole run so changing the picker afterwards
//  cannot re-categorize a finished score.
//

import Foundation

enum Modifier: String, CaseIterable, Identifiable, Codable {
    case none
    case hardcore
    case bitrush
    case featherfall
    case glasscannon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "No Modifier"
        case .hardcore: return "Hardcore"
        case .bitrush: return "Bit Rush"
        case .featherfall: return "Feather Fall"
        case .glasscannon: return "Glass Cannon"
        }
    }

    var blurb: String {
        switch self {
        case .none: return "Standard mode. Double jump and shields enabled. Start with 1 shield."
        case .hardcore: return "No double jump. 1.5× score."
        case .bitrush: return "2× bits, no shields. 1.2× score."
        case .featherfall: return "Lower gravity, floatier jumps. Start with 1 shield. 1.25× score."
        case .glasscannon: return "No shields, one hit ends it. 1.75× score."
        }
    }

    var scoreMult: Double {
        switch self {
        case .none: return 1.0
        case .hardcore: return 1.5
        case .bitrush: return 1.2
        case .featherfall: return 1.25
        case .glasscannon: return 1.75
        }
    }

    var noDoubleJump: Bool { self == .hardcore }

    var bitsMult: Int { self == .bitrush ? 2 : 1 }

    var gravityMult: Double { self == .featherfall ? 0.6 : 1.0 }

    var allowShield: Bool {
        switch self {
        case .bitrush, .glasscannon: return false
        default: return true
        }
    }

    /// Whether the player begins the run already holding a single-hit shield.
    var startsWithShield: Bool {
        switch self {
        case .none, .featherfall: return true
        default: return false
        }
    }
}
