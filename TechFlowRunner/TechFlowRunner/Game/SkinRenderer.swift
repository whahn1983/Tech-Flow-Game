//
//  SkinRenderer.swift
//  Tech Flow Runner
//
//  Builds neon SpriteKit node art for each player skin. All skins render inside
//  the same (w, h) bounding box anchored at bottom-left (0,0)…(w,h) so the
//  hitbox is identical. Art is intentionally vector/shape based — no bitmap
//  assets required.
//

import SpriteKit

enum SkinRenderer {

    /// Returns a container node whose children fill the (0,0)…(w,h) box.
    static func node(for skin: Skin, width w: CGFloat, height h: CGFloat) -> SKNode {
        let container = SKNode()
        let colors = skin.colors
        switch skin {
        case .pulse: buildPulse(container, w, h, colors)
        case .sunset: buildSunset(container, w, h, colors)
        case .matrix: buildMatrix(container, w, h, colors)
        case .plasma: buildPlasma(container, w, h, colors)
        case .bitlord: buildBitLord(container, w, h, colors)
        case .bossbane: buildBossbane(container, w, h, colors)
        }
        return container
    }

    private static func roundedBody(_ w: CGFloat, _ h: CGFloat, radius: CGFloat = 10,
                                    fill: UIColor, stroke: UIColor? = nil, lineWidth: CGFloat = 2) -> SKShapeNode {
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        let node = SKShapeNode(rect: rect, cornerRadius: radius)
        node.fillColor = fill
        node.lineWidth = stroke == nil ? 0 : lineWidth
        node.strokeColor = stroke ?? .clear
        node.glowWidth = 1.5
        return node
    }

    private static func glyph(_ text: String, size: CGFloat, color: UIColor) -> SKLabelNode {
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo-Bold"
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }

    private static func buildPulse(_ c: SKNode, _ w: CGFloat, _ h: CGFloat, _ colors: [UIColor]) {
        let body = roundedBody(w, h, fill: colors[0], stroke: colors[1], lineWidth: 2)
        c.addChild(body)
        let g = glyph("</>", size: 14, color: UIColor(hex: 0xE9F6FF))
        g.position = CGPoint(x: w/2, y: h*0.55)
        c.addChild(g)
    }

    private static func buildSunset(_ c: SKNode, _ w: CGFloat, _ h: CGFloat, _ colors: [UIColor]) {
        let body = roundedBody(w, h, fill: UIColor(hex: 0x3A1844), stroke: colors[0], lineWidth: 2)
        c.addChild(body)
        let sun = SKShapeNode(circleOfRadius: min(w, h) * 0.28)
        sun.fillColor = UIColor(hex: 0xFFF1B8)
        sun.lineWidth = 0
        sun.glowWidth = 3
        sun.position = CGPoint(x: w/2, y: h*0.42)
        c.addChild(sun)
    }

    private static func buildMatrix(_ c: SKNode, _ w: CGFloat, _ h: CGFloat, _ colors: [UIColor]) {
        let body = roundedBody(w, h, fill: UIColor(hex: 0x021109), stroke: colors[1], lineWidth: 2)
        c.addChild(body)
        if h >= 30 {
            let lines = ["10110", "01001", "11010"]
            for (i, line) in lines.enumerated() {
                let g = glyph(line, size: 9, color: colors[0])
                g.horizontalAlignmentMode = .left
                g.position = CGPoint(x: 5, y: h - 12 - CGFloat(i) * (h - 14) / 3)
                c.addChild(g)
            }
        } else {
            let g = glyph("01", size: 11, color: colors[0])
            g.position = CGPoint(x: w/2, y: h/2)
            c.addChild(g)
        }
    }

    private static func buildPlasma(_ c: SKNode, _ w: CGFloat, _ h: CGFloat, _ colors: [UIColor]) {
        let body = roundedBody(w, h, fill: UIColor(hex: 0x2A0A4A), stroke: colors[0], lineWidth: 1.5)
        c.addChild(body)
        // Lightning bolt (y-up coordinates).
        let path = CGMutablePath()
        path.move(to: CGPoint(x: w*0.62, y: h - 6))
        path.addLine(to: CGPoint(x: w*0.32, y: h*0.45))
        path.addLine(to: CGPoint(x: w*0.5, y: h*0.45))
        path.addLine(to: CGPoint(x: w*0.28, y: 6))
        path.addLine(to: CGPoint(x: w*0.7, y: h*0.55))
        path.addLine(to: CGPoint(x: w*0.5, y: h*0.55))
        path.addLine(to: CGPoint(x: w*0.7, y: h - 6))
        path.closeSubpath()
        let bolt = SKShapeNode(path: path)
        bolt.fillColor = colors[0]
        bolt.strokeColor = UIColor.white.withAlphaComponent(0.85)
        bolt.lineWidth = 1
        bolt.glowWidth = 2
        c.addChild(bolt)
    }

    private static func buildBitLord(_ c: SKNode, _ w: CGFloat, _ h: CGFloat, _ colors: [UIColor]) {
        let bodyH = h >= 30 ? h - 14 : h - 2
        let body = roundedBody(w, bodyH, radius: 8, fill: UIColor(hex: 0x0A1A32), stroke: colors[0], lineWidth: 1.5)
        c.addChild(body)
        if h >= 30 {
            // Crown (y-up: top of box at h).
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 6, y: h - 16))
            path.addLine(to: CGPoint(x: 6, y: h - 2))
            path.addLine(to: CGPoint(x: w*0.3, y: h - 10))
            path.addLine(to: CGPoint(x: w/2, y: h))
            path.addLine(to: CGPoint(x: w*0.7, y: h - 10))
            path.addLine(to: CGPoint(x: w - 6, y: h - 2))
            path.addLine(to: CGPoint(x: w - 6, y: h - 16))
            path.closeSubpath()
            let crown = SKShapeNode(path: path)
            crown.fillColor = colors[0]
            crown.lineWidth = 0
            crown.glowWidth = 2
            c.addChild(crown)
            let g = glyph("B", size: 18, color: colors[0])
            g.position = CGPoint(x: w/2, y: (h - 14)/2)
            c.addChild(g)
        } else {
            let g = glyph("B", size: 12, color: colors[0])
            g.position = CGPoint(x: w/2, y: h/2)
            c.addChild(g)
        }
    }

    private static func buildBossbane(_ c: SKNode, _ w: CGFloat, _ h: CGFloat, _ colors: [UIColor]) {
        // Shield shape (y-up).
        let path = CGMutablePath()
        path.move(to: CGPoint(x: w/2, y: h - 2))
        path.addLine(to: CGPoint(x: w - 6, y: h - 12))
        path.addLine(to: CGPoint(x: w - 6, y: h*0.45))
        path.addQuadCurve(to: CGPoint(x: w/2, y: 2), control: CGPoint(x: w*0.75, y: h*0.15))
        path.addQuadCurve(to: CGPoint(x: 6, y: h*0.45), control: CGPoint(x: w*0.25, y: h*0.15))
        path.addLine(to: CGPoint(x: 6, y: h - 12))
        path.closeSubpath()
        let shield = SKShapeNode(path: path)
        shield.fillColor = colors[0]
        shield.strokeColor = UIColor(hex: 0x7A1830)
        shield.lineWidth = 2
        shield.glowWidth = 2
        c.addChild(shield)
        // Slash.
        if h >= 30 {
            let slash = CGMutablePath()
            slash.move(to: CGPoint(x: w*0.3, y: h*0.72))
            slash.addLine(to: CGPoint(x: w*0.74, y: h*0.3))
            let slashNode = SKShapeNode(path: slash)
            slashNode.strokeColor = colors[1]
            slashNode.lineWidth = 3
            slashNode.lineCap = .round
            slashNode.glowWidth = 1.5
            c.addChild(slashNode)
        }
    }
}
