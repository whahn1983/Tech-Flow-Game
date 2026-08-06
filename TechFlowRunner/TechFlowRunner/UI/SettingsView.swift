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
    @ObservedObject private var store = StoreManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var hapticsEnabled = HapticsManager.shared.enabled
    @State private var showConnectConsent = false
    @State private var showLivesStore = false
    #if DEBUG
    @State private var testScenario = PersistenceManager.shared.entitlementTestScenario
    #endif

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

                Section("Lives") {
                    switch store.entitlementSource {
                    case .legacyPaidApp:
                        // Original paid-app owner: never show the $2.99 button.
                        LabeledContent("Unlimited Lives", value: "Early Supporter Access")
                        Text("Thank you for supporting Tech Flow Runner from the beginning. Unlimited Lives are unlocked automatically — runs never cost a life.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .purchasedIAP:
                        LabeledContent("Unlimited Lives", value: "Purchased")
                        Text("You own Unlimited Lives Forever — runs never cost a life. Thanks for your support!")
                            .font(.caption).foregroundStyle(.secondary)
                    case .none:
                        Text("Play free with up to \(LivesManager.maxLives) lives — one refills every 15 minutes. Unlock Unlimited Lives Forever to play without waiting.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Unlimited Lives — \(store.displayPrice)") { showLivesStore = true }
                    }
                    Button("Restore Purchases") { Task { await store.restore() } }
                        .disabled(store.isBusy)
                    if case .info(let message) = store.phase {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    } else if case .failed(let message) = store.phase {
                        Text(message).font(.caption).foregroundStyle(Color.red)
                    }
                    Link("Terms of Use (EULA)", destination: TermsOfUse.url)
                        .font(.callout)
                    Link("Privacy Policy", destination: PrivacyPolicy.url)
                        .font(.callout)
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

                #if DEBUG
                Section("Developer") {
                    Picker("Entitlement Override", selection: $testScenario) {
                        ForEach(EntitlementTestScenario.allCases) { scenario in
                            Text(scenario.label).tag(scenario)
                        }
                    }
                    .onChange(of: testScenario) { _, newValue in
                        PersistenceManager.shared.entitlementTestScenario = newValue
                        Task { await store.refreshEntitlements() }
                    }
                    Text("DEBUG builds only. Simulates each Unlimited Lives entitlement state (StoreKit sandbox can't reproduce real paid-app history). Never compiled into a Release build.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Re-run Entitlement Check") {
                        Task { await store.refreshEntitlements() }
                    }
                }
                #endif

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
            .sheet(isPresented: $showLivesStore) {
                LivesStoreView()
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
