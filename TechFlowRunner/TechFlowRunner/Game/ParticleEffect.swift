//
//  ParticleEffect.swift
//  Tech Flow Runner
//
//  Lightweight particle bursts and trails built from short-lived SKShapeNodes
//  driven by SKActions. Kept deliberately simple (no .sks files) and fully
//  suppressed when reduced motion is requested.
//

import SpriteKit

enum ParticleEffect {

    /// Radial burst of small squares. `parent` is expected to be in scene
    /// coordinates (the FX layer).
    static func burst(in parent: SKNode, at point: CGPoint, count: Int, color: UIColor, reducedMotion: Bool) {
        guard !reducedMotion else { return }
        for i in 0..<count {
            let angle = (CGFloat.pi * 2 * CGFloat(i)) / CGFloat(count) + CGFloat.random(in: 0...0.4)
            let speed = CGFloat.random(in: 2...6)
            let node = SKShapeNode(rect: CGRect(x: -1.5, y: -1.5, width: 3, height: 3))
            node.fillColor = color
            node.lineWidth = 0
            node.position = point
            node.zPosition = 60
            parent.addChild(node)

            let dx = cos(angle) * speed * 16
            let dy = sin(angle) * speed * 16 + 12
            let move = SKAction.moveBy(x: dx, y: dy, duration: 0.5)
            let fade = SKAction.fadeOut(withDuration: 0.5)
            node.run(.sequence([.group([move, fade]), .removeFromParent()]))
        }
    }

    /// Short neon trail particle behind the player.
    static func trail(in parent: SKNode, at point: CGPoint, color: UIColor, reducedMotion: Bool) {
        guard !reducedMotion else { return }
        guard CGFloat.random(in: 0...1) < 0.4 else { return }
        let node = SKShapeNode(rect: CGRect(x: -1.5, y: -1.5, width: 3, height: 3))
        node.fillColor = color
        node.lineWidth = 0
        node.position = point
        node.zPosition = 20
        parent.addChild(node)
        let move = SKAction.moveBy(x: -24, y: CGFloat.random(in: -6...6), duration: 0.35)
        let fade = SKAction.fadeOut(withDuration: 0.35)
        node.run(.sequence([.group([move, fade]), .removeFromParent()]))
    }
}
