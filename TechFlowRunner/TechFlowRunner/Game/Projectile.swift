//
//  Projectile.swift
//  Tech Flow Runner
//
//  Boss laser bolts. They travel left in world space and expire after a fixed
//  lifetime or when off-screen.
//

import SpriteKit

final class Projectile {
    var worldX: CGFloat
    var y: CGFloat       // design-space top
    let w: CGFloat = 22
    let h: CGFloat = 8
    var vx: CGFloat      // world-space velocity (negative = toward player)
    var life: Int
    let node: SKShapeNode

    init(worldX: CGFloat, y: CGFloat, vx: CGFloat, life: Int) {
        self.worldX = worldX
        self.y = y
        self.vx = vx
        self.life = life

        let shape = SKShapeNode(rect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 3)
        shape.fillColor = UIColor(hex: 0xFF5370)
        shape.strokeColor = UIColor(hex: 0xFF9DB0)
        shape.lineWidth = 0.5
        shape.glowWidth = 4
        shape.zPosition = 35
        self.node = shape
    }
}
