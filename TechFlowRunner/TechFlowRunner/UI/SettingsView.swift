//
//  SettingsView.swift
//  Tech Flow Runner
//
//  Local settings: music mute, reduced-motion override, and haptics. All values
//  persist via PersistenceManager. Also surfaces lifetime stats.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var hapticsEnabled = HapticsManager.shared.enabled

    var body: some View {
        NavigationStack {
            Form {
                Section("Audio") {
                    Toggle("Music & Sound", isOn: Binding(
                        get: { !app.muted },
                        set: { _ in app.toggleMute() }
                    ))
                }

                Section("Accessibility") {
                    Toggle("Reduce Motion", isOn: $app.reducedMotionOverride)
                    if UIAccessibility.isReduceMotionEnabled {
                        Text("System Reduce Motion is on; screen shake and particles are already limited.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Haptics", isOn: $hapticsEnabled)
                        .onChange(of: hapticsEnabled) { _, value in
                            HapticsManager.shared.enabled = value
                        }
                }

                Section("Lifetime") {
                    LabeledContent("Best score", value: "\(app.best)")
                    LabeledContent("Distance", value: "\(Int(app.lifetime.distance))")
                    LabeledContent("Bits", value: "\(app.lifetime.bits)")
                    LabeledContent("Runs", value: "\(app.lifetime.runs)")
                    LabeledContent("Bosses defeated", value: "\(app.lifetime.bossKills)")
                }

                Section("Game Center") {
                    Text(GameCenterManager.shared.statusText)
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Show Leaderboard") { app.showLeaderboard() }
                }

                Section {
                    Text("Tech Flow Runner — neon circuit-board endless runner. Music and audio © whahn1983.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
