//
//  GameOverOverlayView.swift
//  Tech Flow Runner
//
//  "Signal Lost" overlay: final points, bits, modifier, daily status, new-best
//  indicator, Game Center submission status, and Reboot / Menu / Leaderboard.
//

import SwiftUI
import UIKit

struct GameOverOverlayView: View {
    @EnvironmentObject var app: AppState
    let result: RunResult

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("SIGNAL LOST")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.danger)
                    .shadow(color: Theme.danger.opacity(0.7), radius: 12)

                if result.isNewBest {
                    Text("★ NEW BEST ★")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.gold)
                }

                VStack(spacing: 8) {
                    bigStat("Points", "\(result.points)")
                    HStack {
                        smallStat("Bits", "\(result.bits)")
                        smallStat("Modifier", result.modifier.label)
                    }
                    if result.daily {
                        Text("Daily Seed · \(result.seedDate)")
                            .font(.caption).foregroundStyle(Theme.gold)
                    }
                    submissionLabel
                }
                .panel()

                Button { app.restartRun() } label: {
                    Label("Reboot Run", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(NeonButtonStyle(tint: Theme.cyan, prominent: true))

                HStack(spacing: 10) {
                    Button { app.returnToMenu() } label: {
                        Label("Menu", systemImage: "house.fill")
                    }
                    .buttonStyle(NeonButtonStyle(tint: Theme.purple))

                    Button { app.showLeaderboard() } label: {
                        Label("Leaderboard", systemImage: "list.number")
                    }
                    .buttonStyle(NeonButtonStyle(tint: Theme.gold))
                }
            }
            .frame(maxWidth: 380)
            .padding(24)
        }
    }

    private var submissionLabel: some View {
        let (text, color, icon): (String, Color, String) = {
            switch result.submission {
            case .pending: return ("Submitting to Game Center…", Theme.dim, "arrow.up.circle")
            case .submitted: return ("Submitted to Game Center", Color(UIColor(hex: 0x16F06B)), "checkmark.seal.fill")
            case .notSignedIn: return ("Not signed in · saved locally", Theme.dim, "person.crop.circle.badge.xmark")
            case .localOnly: return ("Offline · saved locally", Theme.dim, "wifi.slash")
            }
        }()
        return Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func bigStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Theme.cyan)
                .monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
    }

    private func smallStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(Theme.text)
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}
