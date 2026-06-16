//
//  Boss.swift
//  Tech Flow Runner
//
//  The Mainframe boss. It drifts to a fixed screen position, patrols
//  vertically, and fires laser fans. The player survives a timer to defeat it;
//  there is no HP to deplete — survival is the win condition (HP is kept for
//  display parity with the reference).
//

import SpriteKit

final class Boss {
    var worldX: CGFloat
    var y: CGFloat       // design-space top
    let w: CGFloat = GameConstants.bossWidth
    let h: CGFloat = GameConstants.bossHeight
    var hp: Int = 100
    let maxHp: Int = 100
    var timer: Int = GameConstants.bossSurvivalFrames
    var cooldown: Int = 60
    var pattern: Int = 0
    var phase: CGFloat = 0   // deterministic vertical-patrol phase

    let node = SKNode()
    private let barFill: SKShapeNode

    init(worldX: CGFloat, y: CGFloat) {
        self.worldX = worldX
        self.y = y

        // Body
        let body = SKShapeNode(rect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 14)
        body.fillColor = UIColor(hex: 0xFF5A7C)
        body.strokeColor = UIColor(hex: 0xFF9DB0)
        body.lineWidth = 2
        body.glowWidth = 4
        node.addChild(body)

        // Eyes (y-up: place near top of box).
        for ex in [CGFloat(18), w - 32] {
            let eye = SKShapeNode(rect: CGRect(x: ex, y: h - 32, width: 14, height: 14), cornerRadius: 3)
            eye.fillColor = UIColor(hex: 0x220009)
            eye.lineWidth = 0
            node.addChild(eye)
        }
        // Mouth
        let mouth = SKShapeNode(rect: CGRect(x: 24, y: 12, width: w - 48, height: 6))
        mouth.fillColor = UIColor(hex: 0xFFD95C)
        mouth.lineWidth = 0
        node.addChild(mouth)

        // Survival bar (background + fill), placed just above the body.
        let barBG = SKShapeNode(rect: CGRect(x: 0, y: h + 6, width: w, height: 6))
        barBG.fillColor = UIColor.black.withAlphaComponent(0.4)
        barBG.lineWidth = 0
        node.addChild(barBG)

        barFill = SKShapeNode(rect: CGRect(x: 0, y: h + 6, width: 0, height: 6))
        barFill.fillColor = UIColor(hex: 0xFFD95C)
        barFill.lineWidth = 0
        node.addChild(barFill)

        node.zPosition = 45
    }

    /// 0…1 survival progress for the on-body bar.
    func updateBar() {
        let progress = max(0, min(1, 1 - CGFloat(timer) / CGFloat(GameConstants.bossSurvivalFrames)))
        barFill.path = CGPath(rect: CGRect(x: 0, y: h + 6, width: w * progress, height: 6), transform: nil)
    }
}
