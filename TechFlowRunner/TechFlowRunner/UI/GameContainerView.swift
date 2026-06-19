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
            // in landscape. The interface follows the device's physical
            // orientation, so a portrait layout — whether a run is started in
            // portrait on iPhone/iPad, the device is turned mid-run, or iPad
            // multitasking declines a forced rotation — triggers the rotate
            // overlay below until landscape is restored.
            let isLandscape = geo.size.width >= geo.size.height

            // The scene is rendered with aspect-fit against a fixed reference
            // aspect ratio. On devices whose screen is less wide than that
            // (iPads and older iPhones) SpriteKit letterboxes the scene with
            // black bars top and bottom, so the controls sit in that bar and
            // can keep the original, more generous padding. On iPhones whose
            // screen matches the reference aspect ratio the scene fills the
            // whole display, so the controls are pulled tight to the edges to
            // stay clear of the play area.
            let insets = geo.safeAreaInsets
            let fullWidth = geo.size.width + insets.leading + insets.trailing
            let fullHeight = geo.size.height + insets.top + insets.bottom
            let sceneAspect = GameConstants.designWidth / GameConstants.designHeight
            let fillsScreen = fullHeight > 0 && (fullWidth / fullHeight) >= sceneAspect - 0.05

            ZStack {
                GameSceneView(scene: app.scene)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HUDView(hud: app.hud, onPause: { app.pause() })
                    Spacer()
                    if app.runState == .running && !app.awaitingLandscape && app.showOnScreenControls {
                        OnScreenControls(scene: app.scene, edgeToEdge: fillsScreen)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, fillsScreen ? 2 : 10)

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

/// Shown whenever an active run isn't laid out in landscape — a run started in
/// portrait, the device turned mid-run, or iPad multitasking declining a forced
/// rotation. It fills the screen and swallows touches so gameplay input is
/// disabled while visible, prompting the player to rotate to landscape.
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
    /// True on iPhones where the scene fills the entire screen. When set, the
    /// side buttons are pulled flush to the edges (and the extra bottom inset
    /// dropped) so they don't intrude on the play area. On letterboxed devices
    /// (iPad / older iPhones) this is false and the original padding is kept.
    let edgeToEdge: Bool

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
        // On full-screen iPhones pull the side buttons (Duck / Jump) closer to
        // the screen edges than the surrounding HUD padding (14pt) allows. On
        // letterboxed devices keep the original inset and bottom spacing.
        .padding(.horizontal, edgeToEdge ? -14 : 0)
        .padding(.bottom, edgeToEdge ? 0 : 8)
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
