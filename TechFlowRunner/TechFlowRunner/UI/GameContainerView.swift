//
//  GameContainerView.swift
//  Tech Flow Runner
//
//  Composites the SpriteKit scene with the HUD, on-screen accessibility
//  controls, and the pause / game-over overlays.
//

import SwiftUI

struct GameContainerView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            GameSceneView(scene: app.scene)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HUDView(hud: app.hud, onPause: { app.pause() })
                Spacer()
                if app.runState == .running {
                    OnScreenControls(scene: app.scene)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if app.runState == .paused {
                PauseOverlayView()
                    .transition(.opacity)
            }
            if app.runState == .gameOver {
                GameOverOverlayView(result: app.runResult)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.runState)
    }
}

/// Always-reachable on-screen buttons (Jump / Duck / Dash) plus the pause
/// button in the HUD. These provide a non-gesture fallback for accessibility.
private struct OnScreenControls: View {
    let scene: TechFlowGameScene

    var body: some View {
        HStack {
            ControlButton(symbol: "arrow.down.to.line", label: "Duck", tint: Theme.gold,
                          onDown: { scene.beginDuck() }, onUp: { scene.endDuck() })
            Spacer()
            ControlButton(symbol: "bolt.fill", label: "Dash", tint: Theme.pink,
                          onDown: { scene.dash() }, onUp: {})
            Spacer()
            ControlButton(symbol: "arrow.up", label: "Jump", tint: Theme.cyan,
                          onDown: { scene.tapJump() }, onUp: {})
        }
        .padding(.bottom, 8)
    }
}

private struct ControlButton: View {
    let symbol: String
    let label: String
    let tint: Color
    let onDown: () -> Void
    let onUp: () -> Void

    @State private var pressed = false

    var body: some View {
        Image(systemName: symbol)
            .font(.title2.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 64, height: 64)
            .background(Circle().fill(Theme.panel.opacity(0.7)))
            .overlay(Circle().strokeBorder(tint.opacity(0.7), lineWidth: 1.5))
            .scaleEffect(pressed ? 0.92 : 1)
            .accessibilityLabel(label)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed { pressed = true; onDown() }
                    }
                    .onEnded { _ in
                        pressed = false; onUp()
                    }
            )
    }
}
