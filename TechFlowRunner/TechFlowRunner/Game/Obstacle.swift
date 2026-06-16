//
//  Obstacle.swift
//  Tech Flow Runner
//
//  Ground and floating hazards. `action` describes how the player must respond
//  (`jump` for bug/server/laser, `stay`/duck for the drone), and the spawn
//  scheduler uses it to keep sequences fair.
//

import SpriteKit

enum ObstacleType {
    case bug, server, laser, drone
}

enum ObstacleAction {
    case jump, stay
}

final class Obstacle {
    var worldX: CGFloat
    var y: CGFloat       // design-space top
    var w: CGFloat
    var h: CGFloat
    let type: ObstacleType
    let action: ObstacleAction
    let node: SKNode

    init(worldX: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, type: ObstacleType, action: ObstacleAction) {
        self.worldX = worldX
        self.y = y
        self.w = w
        self.h = h
        self.type = type
        self.action = action
        self.node = Obstacle.makeNode(type: type, w: w, h: h)
        self.node.zPosition = 40
    }

    private static func makeNode(type: ObstacleType, w: CGFloat, h: CGFloat) -> SKNode {
        let container = SKNode()
        switch type {
        case .bug:
            let body = SKShapeNode(ellipseOf: CGSize(width: w, height: h))
            body.position = CGPoint(x: w/2, y: h/2)
            body.fillColor = UIColor(hex: 0x16F06B)
            body.strokeColor = UIColor(hex: 0x75FFD4)
            body.lineWidth = 1.5
            body.glowWidth = 2
            container.addChild(body)
            for sx in [w*0.32, w*0.68] {
                let eye = SKShapeNode(circleOfRadius: 2)
                eye.fillColor = UIColor(hex: 0x021109)
                eye.lineWidth = 0
                eye.position = CGPoint(x: sx, y: h*0.6)
                container.addChild(eye)
            }
        case .server:
            let body = SKShapeNode(rect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 6)
            body.fillColor = UIColor(hex: 0xFF5A7C)
            body.strokeColor = UIColor(hex: 0xFF8FA8)
            body.lineWidth = 1.5
            body.glowWidth = 2
            container.addChild(body)
            var sy = h - 14
            while sy > 6 {
                let slot = SKShapeNode(rect: CGRect(x: 8, y: sy, width: w - 16, height: 4))
                slot.fillColor = UIColor(hex: 0x12020A)
                slot.lineWidth = 0
                container.addChild(slot)
                sy -= 14
            }
        case .laser:
            let beam = SKShapeNode(rect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 3)
            beam.fillColor = UIColor(hex: 0xFF5370)
            beam.strokeColor = UIColor(hex: 0xFF9DB0)
            beam.lineWidth = 1
            beam.glowWidth = 4
            container.addChild(beam)
        case .drone:
            let body = SKShapeNode(rect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 8)
            body.fillColor = UIColor(hex: 0xFFCA5F)
            body.strokeColor = UIColor(hex: 0xFFE49A)
            body.lineWidth = 1.5
            body.glowWidth = 3
            container.addChild(body)
            let scanner = SKShapeNode(rect: CGRect(x: 10, y: h/2 - 3, width: w - 20, height: 6))
            scanner.fillColor = UIColor(hex: 0x3E2B09)
            scanner.lineWidth = 0
            container.addChild(scanner)
            // Beam pointing down toward the ground.
            let beam = SKShapeNode(rect: CGRect(x: w/2 - 6, y: -12, width: 12, height: 12))
            beam.fillColor = UIColor(hex: 0xFFD95C).withAlphaComponent(0.85)
            beam.lineWidth = 0
            beam.glowWidth = 2
            container.addChild(beam)
        }
        return container
    }
}
