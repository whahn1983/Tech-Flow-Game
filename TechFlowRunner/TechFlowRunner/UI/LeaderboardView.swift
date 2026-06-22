//
//  LeaderboardView.swift
//  Tech Flow Runner
//
//  Game Center status, a button that presents the native GKGameCenterViewController
//  leaderboard UI, and a local recent-runs list (there is no custom backend).
//

import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var gameCenter = GameCenterManager.shared
    @Environment(\.dismiss) private var dismiss

    private var history: [RunRecord] {
        PersistenceManager.shared.history.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: gameCenter.canUseGameCenter ? "trophy.fill" : "trophy")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.gold)
                        Text(gameCenter.statusText)
                            .font(.subheadline).foregroundStyle(Theme.dim)
                            .multilineTextAlignment(.center)

                        switch gameCenter.consentState {
                        case .consented where gameCenter.isAuthenticated:
                            // Opens the native Game Center leaderboards list, where
                            // the player can browse and switch between every board.
                            Button { app.showLeaderboard() } label: {
                                Label("Open Leaderboards", systemImage: "list.number")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NeonButtonStyle(tint: Theme.gold))

                        case .consented:
                            // Opted in, but the session isn't authenticated
                            // (signed out / failed). Offer a retry.
                            Button { gameCenter.authenticateIfConsented() } label: {
                                Label("Retry Sign In", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(NeonButtonStyle(tint: Theme.gold))
                            Text("Sign in to Game Center to see the global leaderboard. Your runs are saved locally either way.")
                                .font(.caption).foregroundStyle(Theme.dim)
                                .multilineTextAlignment(.center)

                        case .offline, .notAsked:
                            // Never open Game Center before consent. Explain it's
                            // optional and let the player opt in here, with the
                            // privacy policy available before they do.
                            Text("Game Center is off. You can play offline, or connect to Game Center to use leaderboards and achievements.")
                                .font(.caption).foregroundStyle(Theme.dim)
                                .multilineTextAlignment(.center)
                            Button { app.resolveGameCenterConsent(connect: true) } label: {
                                Label("Connect to Game Center", systemImage: "person.crop.circle.badge.checkmark")
                            }
                            .buttonStyle(NeonButtonStyle(tint: Theme.gold))
                            Link(destination: PrivacyPolicy.url) {
                                Label("Privacy Policy", systemImage: "hand.raised.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.cyan)
                            }
                        }
                    }
                    .panel()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local Best: \(app.best)")
                            .font(.headline).foregroundStyle(Theme.cyan)
                        if history.isEmpty {
                            Text("No runs yet. Finish a run to see it here.")
                                .font(.caption).foregroundStyle(Theme.dim)
                        } else {
                            ForEach(Array(history.prefix(10))) { record in
                                HStack {
                                    Text("\(record.score) pts").font(.subheadline.weight(.bold))
                                        .foregroundStyle(Theme.text)
                                    if record.daily {
                                        Text("Daily").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(Theme.gold.opacity(0.3)))
                                            .foregroundStyle(Theme.gold)
                                    }
                                    Spacer()
                                    Text(Modifier(rawValue: record.modifier)?.label ?? record.modifier)
                                        .font(.caption).foregroundStyle(Theme.dim)
                                }
                                .padding(.vertical, 2)
                                Divider().overlay(Theme.cyan.opacity(0.1))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
                }
                .padding()
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Leaderboard")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
