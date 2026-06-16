//
//  GameSceneView.swift
//  Tech Flow Runner
//
//  Hosts the SpriteKit scene inside SwiftUI and wires up the touch controls:
//  tap = jump/double-jump, swipe (hold) down = duck, swipe right = dash. The
//  on-screen accessibility buttons (in the HUD) provide the same actions for
//  players who can't use gestures.
//

import SwiftUI
import SpriteKit

struct GameSceneView: UIViewRepresentable {
    let scene: TechFlowGameScene

    func makeCoordinator() -> Coordinator { Coordinator(scene: scene) }

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = true
        #if DEBUG
        view.showsFPS = false
        view.showsNodeCount = false
        #endif
        if scene.size == .zero {
            scene.size = UIScreen.main.bounds.size
        }
        scene.scaleMode = .resizeFill
        view.presentScene(scene)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.bounds.size != .zero, scene.size != uiView.bounds.size {
            scene.size = uiView.bounds.size
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let scene: TechFlowGameScene
        private var ducking = false

        init(scene: TechFlowGameScene) { self.scene = scene }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            scene.tapJump()
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let t = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .changed:
                if t.y > 30 && abs(t.y) > abs(t.x) {
                    if !ducking { scene.beginDuck(); ducking = true }
                }
                if t.x > 50 && abs(t.x) > abs(t.y) {
                    scene.dash()
                }
            case .ended, .cancelled, .failed:
                if ducking { scene.endDuck(); ducking = false }
            default:
                break
            }
        }

        // Allow tap and pan to coexist so a quick tap still jumps.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
