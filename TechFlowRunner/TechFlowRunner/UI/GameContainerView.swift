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
        GeometryReader { geo in
            // The gameplay area is only considered playable when it is laid out
            // in landscape. On iPhone the orientation lock makes this immediate;
            // on iPad (Split View / Stage Manager, where rotation can't always
            // be forced) a portrait layout triggers the rotate overlay below.
            let isLandscape = geo.size.width >= geo.size.height

            ZStack {
                GameSceneView(scene: app.scene)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HUDView(hud: app.hud, onPause: { app.pause() })
                    Spacer()
                    if app.runState == .running && !app.awaitingLandscape {
                        OnScreenControls(scene: app.scene)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 2)

                // The rotate overlay takes precedence over the normal overlays:
                // it both pauses play and disables input while not landscape.
                if app.awaitingLandscape {
                    RotateToContinueOverlay()
                        .transition(.opacity)
                } else if app.runState == .paused {
                    PauseOverlayView()
                        .transition(.opacity)
                } else if app.runState == .gameOver {
                    GameOverOverlayView(result: app.runResult)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: app.runState)
            .animation(.easeInOut(duration: 0.2), value: app.awaitingLandscape)
            .onAppear { app.gameViewGeometryChanged(isLandscape: isLandscape) }
            .onChange(of: geo.size) { _, newSize in
                app.gameViewGeometryChanged(isLandscape: newSize.width >= newSize.height)
            }
        }
    }
}

/// Fallback shown when an active run isn't laid out in landscape (primarily
/// iPad multitasking, where the system may decline a forced rotation). It fills
/// the screen and swallows touches so gameplay input is disabled while visible.
private struct RotateToContinueOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "rotate.right.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Theme.cyan)
                Text("Rotate Device to Continue")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Tech Flow Runner plays in landscape.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .multilineTextAlignment(.center)
            .padding(40)
        }
        .contentShape(Rectangle())
        .onTapGesture { }   // swallow taps so the run can't be played in portrait
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rotate device to continue. Tech Flow Runner plays in landscape.")
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
        // Pull the side buttons (Duck / Jump) closer to the screen edges than
        // the surrounding HUD padding (14pt) allows.
        .padding(.horizontal, -10)
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
