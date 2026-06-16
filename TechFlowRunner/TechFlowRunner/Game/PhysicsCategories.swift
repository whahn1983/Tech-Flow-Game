//
//  PhysicsCategories.swift
//  Tech Flow Runner
//
//  SpriteKit physics bitmasks. Most gameplay collision in this game is resolved
//  manually with AABB checks (mirroring the original reference), but the
//  categories are kept here so contact-based handling can be layered on where
//  it is convenient.
//

import Foundation

struct PhysicsCategory {
    static let none: UInt32 = 0
    static let player: UInt32 = 1 << 0
    static let ground: UInt32 = 1 << 1
    static let obstacle: UInt32 = 1 << 2
    static let bit: UInt32 = 1 << 3
    static let powerUp: UInt32 = 1 << 4
    static let projectile: UInt32 = 1 << 5
    static let boss: UInt32 = 1 << 6
    static let gapDeathZone: UInt32 = 1 << 7
}
