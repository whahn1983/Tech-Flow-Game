//
//  CollectibleBit.swift
//  Tech Flow Runner
//
//  Diamond-shaped neon "bits" collected by overlap. Bits feed score, combo and
//  lifetime stats, and are pulled toward the player while the magnet power-up
//  is active.
//

import SpriteKit

final class CollectibleBit {
    var worldX: CGFloat
    var y: CGFloat       // design-space top
    let w: CGFloat = 14
    let h: CGFloat = 14
    let value: Int = 1
    let node: SKShapeNode

    init(worldX: CGFloat, y: CGFloat) {
        self.worldX = worldX
        self.y = y

        let path = CGMutablePath()
        // Diamond, anchored within (0,0)…(w,h), y-up.
        path.move(to: CGPoint(x: 7, y: 14))
        path.addLine(to: CGPoint(x: 14, y: 7))
        path.addLine(to: CGPoint(x: 7, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 7))
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        shape.fillColor = UIColor(hex: 0xFFD95C)
        shape.strokeColor = UIColor(hex: 0xFFF1B8)
        shape.lineWidth = 1
        shape.glowWidth = 3
        shape.zPosition = 30
        self.node = shape
    }
}
