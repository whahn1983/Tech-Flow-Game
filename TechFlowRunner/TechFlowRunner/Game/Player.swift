//
//  Player.swift
//  Tech Flow Runner
//
//  The runner. Kinematic state is tracked in "design space" (y increases
//  downward, matching the original reference) and rendered into SpriteKit's
//  y-up space by the scene. The collision hitbox is the plain rectangle
//  (x, y, w, h); skins are purely cosmetic.
//

import SpriteKit

final class Player {
    // Design-space rectangle. `x` is the fixed on-screen left edge; `y` is the
    // top edge in design space; the run scrolls the world past this point.
    let x: CGFloat = GameConstants.playerStartX
    var y: CGFloat = 0
    var w: CGFloat = GameConstants.playerWidth
    var h: CGFloat = GameConstants.playerHeight
    var vy: CGFloat = 0
    var onGround: Bool = true
    var jumpsLeft: Int = 2

    let jumpPower: CGFloat = -GameConstants.jumpVelocity   // design space: up = negative

    // SpriteKit nodes.
    let container = SKNode()
    private var skinNode = SKNode()
    private var shieldAura: SKShapeNode?
    private var overclockOutline: SKShapeNode?
    private var dashTrail: SKNode?

    private var currentSkin: Skin = .pulse
    private var renderedHeight: CGFloat = GameConstants.playerHeight

    init() {
        container.zPosition = 50
        rebuildSkin(.pulse)
    }

    func rebuildSkin(_ skin: Skin) {
        currentSkin = skin
        skinNode.removeFromParent()
        skinNode = SkinRenderer.node(for: skin, width: w, height: h)
        renderedHeight = h
        container.addChild(skinNode)
    }

    /// Rebuilds the visual when the duck state flattens/expands the box so the
    /// art always matches the live hitbox height.
    func syncVisualHeightIfNeeded() {
        if abs(renderedHeight - h) > 0.5 {
            rebuildSkin(currentSkin)
        }
    }

    // MARK: Auras

    func setShield(_ active: Bool) {
        if active {
            if shieldAura == nil {
                let aura = SKShapeNode(circleOfRadius: max(w, h) * 0.65)
                aura.strokeColor = UIColor(hex: 0x2EF8FF).withAlphaComponent(0.85)
                aura.lineWidth = 3
                aura.glowWidth = 4
                aura.fillColor = .clear
                aura.zPosition = -1
                container.addChild(aura)
                shieldAura = aura
            }
            shieldAura?.position = CGPoint(x: w/2, y: h/2)
        } else {
            shieldAura?.removeFromParent()
            shieldAura = nil
        }
    }

    func setOverclock(_ active: Bool) {
        if active {
            if overclockOutline == nil {
                let rect = CGRect(x: -3, y: -3, width: w + 6, height: h + 6)
                let outline = SKShapeNode(rect: rect, cornerRadius: 10)
                outline.strokeColor = UIColor(hex: 0xFFD95C).withAlphaComponent(0.9)
                outline.lineWidth = 2
                outline.glowWidth = 3
                outline.fillColor = .clear
                outline.zPosition = -1
                container.addChild(outline)
                overclockOutline = outline
            }
        } else {
            overclockOutline?.removeFromParent()
            overclockOutline = nil
        }
    }

    func setDashing(_ active: Bool) {
        if active {
            if dashTrail == nil {
                let trail = SKNode()
                let s1 = SKShapeNode(rect: CGRect(x: -18, y: 6, width: 18, height: h - 12))
                s1.fillColor = UIColor.white.withAlphaComponent(0.25)
                s1.lineWidth = 0
                let s2 = SKShapeNode(rect: CGRect(x: -36, y: 12, width: 18, height: h - 24))
                s2.fillColor = UIColor.white.withAlphaComponent(0.12)
                s2.lineWidth = 0
                trail.addChild(s1); trail.addChild(s2)
                trail.zPosition = -1
                container.addChild(trail)
                dashTrail = trail
            }
        } else {
            dashTrail?.removeFromParent()
            dashTrail = nil
        }
    }

    // MARK: Geometry helpers

    /// Bottom edge in design space.
    var bottom: CGFloat { y + h }
}
