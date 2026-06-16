//
//  PauseOverlayView.swift
//  Tech Flow Runner
//
//  Paused state overlay: Resume, Restart, Main Menu, and a music toggle.
//

import SwiftUI

struct PauseOverlayView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("PAUSED")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.cyan)
                    .shadow(color: Theme.cyan.opacity(0.7), radius: 10)

                Button { app.resume() } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(NeonButtonStyle(tint: Theme.cyan, prominent: true))

                Button { app.restartRun() } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(NeonButtonStyle(tint: Theme.gold))

                Button { app.returnToMenu() } label: {
                    Label("Main Menu", systemImage: "house.fill")
                }
                .buttonStyle(NeonButtonStyle(tint: Theme.purple))

                Button { app.toggleMusic() } label: {
                    Label(app.musicEnabled ? "Music On" : "Music Off",
                          systemImage: app.musicEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .buttonStyle(NeonButtonStyle(tint: Theme.purple))
            }
            .frame(maxWidth: 360)
            .padding(24)
        }
    }
}
