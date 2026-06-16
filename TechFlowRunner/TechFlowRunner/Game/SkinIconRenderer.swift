//
//  SkinIconRenderer.swift
//  Tech Flow Runner
//
//  Renders the exact in-game SpriteKit art for a skin (built by SkinRenderer)
//  into a UIImage so the SwiftUI skin picker can show the real player graphic —
//  the same thing you see in a run — instead of a flat color swatch.
//
//  The art is snapshotted once per (skin, size) and cached. Rendering happens
//  on an offscreen SKView with a transparent background, so the resulting image
//  carries only the neon shapes (no opaque scene fill) and can be layered over
//  the picker card.
//

import SpriteKit
import UIKit

enum SkinIconRenderer {

    /// Cache keyed by skin + pixel size so we render each thumbnail at most once.
    private static var cache: [String: UIImage] = [:]

    /// Returns the in-game art for `skin` rendered at `scale`× the player's
    /// design box. Drawing the node scaled (rather than rebuilding it larger)
    /// keeps every detail — glyphs, glow, strokes — proportioned exactly as it
    /// appears in a run.
    static func image(for skin: Skin, scale: CGFloat = 3.0) -> UIImage? {
        let w = GameConstants.playerWidth
        let h = GameConstants.playerHeight
        let key = "\(skin.rawValue)@\(Int(scale))"
        if let cached = cache[key] { return cached }

        let node = SkinRenderer.node(for: skin, width: w, height: h)
        node.setScale(scale)
        node.position = .zero // children fill (0,0)…(w,h); scaled, they fill the scene

        let scene = SKScene(size: CGSize(width: w * scale, height: h * scale))
        scene.backgroundColor = .clear
        scene.addChild(node)

        let view = SKView()
        view.allowsTransparency = true
        guard let texture = view.texture(from: scene) else { return nil }

        let image = UIImage(cgImage: texture.cgImage())
        cache[key] = image
        return image
    }
}
