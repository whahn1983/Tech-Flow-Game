//
//  PowerUp.swift
//  Tech Flow Runner
//
//  Floating, collectible power-ups: shield, overclock, magnet, slow-mo. Each
//  bobs gently and is labeled (S / O / M / ~) to match the original art.
//

import SpriteKit

enum PowerUpKind: CaseIterable {
    case shield, overclock, magnet, slowmo

    var label: String {
        switch self {
        case .shield: return "S"
        case .overclock: return "O"
        case .magnet: return "M"
        case .slowmo: return "~"
        }
    }

    var color: UIColor {
        switch self {
        case .shield: return UIColor(hex: 0x2EF8FF)
        case .overclock: return UIColor(hex: 0xFFD95C)
        case .magnet: return UIColor(hex: 0xFF5CD1)
        case .slowmo: return UIColor(hex: 0x75FFD4)
        }
    }
}

final class PowerUp {
    var worldX: CGFloat
    var baseY: CGFloat   // design-space top of the bobbing range
    let w: CGFloat = 24
    let h: CGFloat = 24
    let kind: PowerUpKind
    var bob: CGFloat
    let node: SKNode

    init(worldX: CGFloat, baseY: CGFloat, kind: PowerUpKind, bobPhase: CGFloat) {
        self.worldX = worldX
        self.baseY = baseY
        self.kind = kind
        self.bob = bobPhase

        let container = SKNode()
        let box = SKShapeNode(rect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 6)
        box.fillColor = kind.color
        box.strokeColor = kind.color
        box.glowWidth = 6
        box.lineWidth = 1
        container.addChild(box)

        let label = SKLabelNode(text: kind.label)
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.fontColor = UIColor(hex: 0x0A1330)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: w/2, y: h/2)
        container.addChild(label)

        container.zPosition = 30
        self.node = container
    }
}
