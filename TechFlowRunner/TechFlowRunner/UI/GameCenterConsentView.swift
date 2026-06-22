//
//  GameCenterConsentView.swift
//  Tech Flow Runner
//
//  The Game Center consent dialog (App Store Review Guideline 5.1.2). Shown on
//  first launch — and again from Settings / the leaderboard for offline players
//  — so the player explicitly chooses between staying offline and connecting to
//  Game Center BEFORE any score or achievement is uploaded. The privacy policy
//  is always reachable from here, before the player opts in.
//

import SwiftUI

struct GameCenterConsentView: View {
    @Environment(\.dismiss) private var dismiss

    /// "Connect to Game Center" was tapped — the caller records consent and
    /// starts authentication.
    let onConnect: () -> Void
    /// "Play Offline" was tapped — the caller records the offline choice.
    let onOffline: () -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.gold)
                        .shadow(color: Theme.gold.opacity(0.6), radius: 12)
                        .padding(.top, 12)

                    Text("Game Center Leaderboards")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)

                    Text("Tech Flow Runner can use Apple Game Center to submit your scores to global leaderboards and sync achievements. Game Center is optional. You can play offline without uploading scores and connect later from Settings.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: PrivacyPolicy.url) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.cyan)
                    }
                    .accessibilityHint("Opens the privacy policy in your browser")

                    VStack(spacing: 12) {
                        Button {
                            onConnect()
                            dismiss()
                        } label: {
                            Label("Connect to Game Center", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .buttonStyle(NeonButtonStyle(tint: Theme.gold, prominent: true))

                        Button {
                            onOffline()
                            dismiss()
                        } label: {
                            Label("Play Offline", systemImage: "wifi.slash")
                        }
                        .buttonStyle(NeonButtonStyle(tint: Theme.purple))
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: 420)
                .padding(24)
            }
        }
    }
}
