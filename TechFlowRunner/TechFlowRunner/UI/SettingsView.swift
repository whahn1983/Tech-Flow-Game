//
//  SettingsView.swift
//  Tech Flow Runner
//
//  Local settings: independent music and sound-effect controls (each with an
//  enable toggle and a volume slider), reduced-motion override, haptics, and a
//  toggle to hide the on-screen Jump/Dash/Duck buttons. All values persist via
//  PersistenceManager. Also surfaces lifetime stats.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var gameCenter = GameCenterManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var hapticsEnabled = HapticsManager.shared.enabled
    @State private var showConnectConsent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Music") {
                    Toggle("Music", isOn: $app.musicEnabled)
                    if app.musicEnabled {
                        volumeSlider(value: $app.musicVolume)
                    }
                }

                Section("Sound Effects") {
                    Toggle("Sound Effects", isOn: $app.sfxEnabled)
                    if app.sfxEnabled {
                        volumeSlider(value: $app.sfxVolume) { editing in
                            // Play a sample tone once the player lets go so they
                            // can gauge the chosen level.
                            if !editing { AudioManager.shared.previewSfx() }
                        }
                    }
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

                Section("Controls") {
                    Toggle("On-Screen Controls", isOn: $app.showOnScreenControls)
                    Text("Show the Jump, Dash, and Duck buttons during play. Turn off to play with taps and swipes only.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Lifetime") {
                    LabeledContent("Best score", value: "\(app.best)")
                    LabeledContent("Distance", value: "\(Int(app.lifetime.distance))")
                    LabeledContent("Bits", value: "\(app.lifetime.bits)")
                    LabeledContent("Runs", value: "\(app.lifetime.runs)")
                    LabeledContent("Bosses defeated", value: "\(app.lifetime.bossKills)")
                }

                Section("Game Center") {
                    LabeledContent("Status", value: gameCenter.settingsStatusText)
                    Text(gameCenter.statusText)
                        .font(.caption).foregroundStyle(.secondary)

                    switch gameCenter.consentState {
                    case .offline, .notAsked:
                        // Offline players can opt in later. Re-show the consent
                        // message (with the privacy policy) before connecting.
                        Text("Connect to Game Center to submit your scores to global leaderboards and sync achievements. Game Center is optional.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Connect to Game Center") { showConnectConsent = true }
                        Link("Privacy Policy", destination: PrivacyPolicy.url)
                            .font(.callout)

                    case .consented:
                        Button("Show Leaderboard") { app.showLeaderboard() }
                        // Honest opt-out: the app can't tear down the live Game
                        // Center session, but this stops all future score and
                        // achievement uploads. Local play is unaffected.
                        Button("Switch to Offline Mode", role: .destructive) {
                            gameCenter.goOffline()
                        }
                    }
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
            .sheet(isPresented: $showConnectConsent) {
                GameCenterConsentView(
                    onConnect: { gameCenter.requestConsentAndAuthenticate() },
                    onOffline: { gameCenter.goOffline() }
                )
            }
        }
    }

    /// A labelled 0...1 volume slider flanked by speaker glyphs.
    private func volumeSlider(value: Binding<Double>,
                              onEditingChanged: @escaping (Bool) -> Void = { _ in }) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: value, in: 0...1, onEditingChanged: onEditingChanged)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int((value.wrappedValue * 100).rounded())) percent")
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
