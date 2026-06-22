//
//  MainMenuView.swift
//  Tech Flow Runner
//
//  The polished entry screen: title, Start, Daily Seed toggle, modifier and
//  skin pickers, unlock progress, local best, Game Center status, and buttons
//  for the leaderboard and settings.
//

import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var gameCenter = GameCenterManager.shared

    @State private var showSettings = false
    @State private var showSkins = false
    @State private var showModifiers = false
    @State private var showLeaderboard = false

    var body: some View {
        ZStack {
            MenuBackdrop()
            ScrollView {
                VStack(spacing: 18) {
                    header

                    VStack(spacing: 12) {
                        Button {
                            app.startRun()
                        } label: {
                            Label("Start Run", systemImage: "play.fill")
                        }
                        .buttonStyle(NeonButtonStyle(tint: Theme.cyan, prominent: true))
                        .accessibilityHint("Begins a new run")

                        runOptions

                        statsPanel

                        bottomButtons
                    }
                    .frame(maxWidth: 460)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showSkins) { SkinPickerView() }
        .sheet(isPresented: $showModifiers) { ModifierPickerView() }
        .sheet(isPresented: $showLeaderboard) { LeaderboardView() }
        // First-run Game Center consent: ask once the menu has appeared, so the
        // player chooses before any run starts (App Store Review 5.1.2).
        .onAppear { app.presentConsentDialogIfNeeded() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("TECH FLOW")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.cyan)
                .shadow(color: Theme.cyan.opacity(0.7), radius: 12)
            Text("RUNNER")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .tracking(12)
                .foregroundStyle(Theme.purple)
                .shadow(color: Theme.purple.opacity(0.7), radius: 10)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tech Flow Runner")
    }

    private var runOptions: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $app.dailyEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Seed").font(.headline).foregroundStyle(Theme.text)
                    Text(app.dailyEnabled ? "UTC \(app.dailySeedDateString)" : "Same course for everyone today")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
            }
            .tint(Theme.gold)

            Button { showModifiers = true } label: {
                pickerRow(title: "Modifier", value: app.selectedModifier.label, system: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .disabled(app.dailyEnabled)
            .opacity(app.dailyEnabled ? 0.4 : 1)
            .accessibilityHint(app.dailyEnabled ? "Locked to No Modifier while Daily Seed is on" : "")

            Button { showSkins = true } label: {
                pickerRow(title: "Skin", value: app.selectedSkin.label, system: "paintpalette.fill")
            }
            .buttonStyle(.plain)
        }
        .panel()
    }

    private func pickerRow(title: String, value: String, system: String) -> some View {
        HStack {
            Image(systemName: system).foregroundStyle(Theme.cyan)
            Text(title).font(.headline).foregroundStyle(Theme.text)
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(Theme.gold)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.dim)
        }
        .contentShape(Rectangle())
    }

    private var statsPanel: some View {
        VStack(spacing: 8) {
            HStack {
                statBlock("Best", "\(app.best)")
                statBlock("Skins", "\(app.unlockedSkins.count)/\(Skin.allCases.count)")
            }
            HStack {
                statBlock("Distance", "\(Int(app.lifetime.distance))")
                statBlock("Bits", "\(app.lifetime.bits)")
                statBlock("Bosses", "\(app.lifetime.bossKills)")
            }
            Text(gameCenter.statusText)
                .font(.caption)
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .panel()
    }

    private func statBlock(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Theme.cyan)
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomButtons: some View {
        VStack(spacing: 10) {
            Button { showLeaderboard = true } label: {
                Label("Leaderboard", systemImage: "list.number")
            }
            .buttonStyle(NeonButtonStyle(tint: Theme.gold))

            HStack(spacing: 10) {
                Button { app.toggleMusic() } label: {
                    Label(app.musicEnabled ? "Music On" : "Music Off",
                          systemImage: app.musicEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .buttonStyle(NeonButtonStyle(tint: Theme.purple))

                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .buttonStyle(NeonButtonStyle(tint: Theme.purple))
            }
        }
    }
}

/// Subtle animated neon backdrop for the menu.
private struct MenuBackdrop: View {
    @State private var animate = false

    private struct Blob: Identifiable {
        let id: Int
        let color: Color
        let startX: CGFloat
        let endX: CGFloat
        let y: CGFloat
    }

    private let blobs: [Blob] = [
        Blob(id: 0, color: Theme.cyan, startX: 0.7, endX: 0.2, y: 0.25),
        Blob(id: 1, color: Theme.purple, startX: 0.3, endX: 0.8, y: 0.55),
        Blob(id: 2, color: Theme.pink, startX: 0.4, endX: 0.5, y: 0.80)
    ]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            GeometryReader { geo in
                ForEach(blobs) { blob in
                    let xFraction = animate ? blob.endX : blob.startX
                    Circle()
                        .fill(RadialGradient(colors: [blob.color.opacity(0.25), .clear],
                                             center: .center, startRadius: 0, endRadius: 220))
                        .frame(width: 440, height: 440)
                        .position(x: geo.size.width * xFraction, y: geo.size.height * blob.y)
                        .blur(radius: 30)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) { animate = true }
        }
    }
}
