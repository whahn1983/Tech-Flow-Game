//
//  LivesStoreView.swift
//  Tech Flow Runner
//
//  The Unlimited Lives store / paywall. Reached from the menu's lives panel, the
//  "Out of Lives" prompt (menu and game-over), and Settings. Presents the
//  one-time purchase, a Restore Purchases action, and — while the pool is
//  limited — the current lives and regen countdown so the player can also just
//  wait.
//

import SwiftUI

struct LivesStoreView: View {
    @ObservedObject private var lives = LivesManager.shared
    @ObservedObject private var store = StoreManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        header

                        if store.hasUnlimitedLives {
                            unlockedPanel
                        } else {
                            livesStatusPanel
                            offerPanel
                        }

                        if case .failed(let message) = store.phase {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(Theme.danger)
                                .multilineTextAlignment(.center)
                        } else if case .info(let message) = store.phase {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(Theme.cyan)
                                .multilineTextAlignment(.center)
                        }

                        restoreButton

                        legalFooter
                    }
                    .frame(maxWidth: 460)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Unlimited Lives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { lives.refresh() }
            .onReceive(timer) { date in
                now = date
                lives.refresh()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "infinity")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(Theme.gold)
                .shadow(color: Theme.gold.opacity(0.6), radius: 12)
            Text("Unlimited Lives Forever")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text("Play as much as you want — no waiting for lives to refill.")
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var livesStatusPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "heart.fill").foregroundStyle(Theme.danger)
                Text("Your Lives").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Text("\(lives.lives) / \(LivesManager.maxLives)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.cyan)
                    .monospacedDigit()
            }
            Text(regenText)
                .font(.caption)
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panel()
    }

    private var offerPanel: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                benefitRow(icon: "infinity", text: "Never run out of lives")
                benefitRow(icon: "bolt.fill", text: "No 15-minute waits between runs")
                benefitRow(icon: "checkmark.seal.fill", text: "One-time purchase, yours forever")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await store.purchase() }
            } label: {
                HStack {
                    if store.phase == .purchasing {
                        ProgressView().tint(Theme.bg)
                        Text("Purchasing…")
                    } else {
                        Label("Unlimited Lives", systemImage: "infinity")
                        Spacer()
                        Text(store.displayPrice).monospacedDigit()
                    }
                }
            }
            .buttonStyle(NeonButtonStyle(tint: Theme.gold, prominent: true))
            .disabled(store.isBusy)
        }
        .panel()
    }

    /// The "already owned" panel. It reflects WHY Unlimited Lives is active:
    /// original paid-app owners see Early Supporter Access (never the $2.99
    /// button), IAP purchasers see Purchased.
    private var unlockedPanel: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.gold)

            Text("Unlimited Lives")
                .font(.headline).foregroundStyle(Theme.text)

            switch store.entitlementSource {
            case .legacyPaidApp:
                Text("Early Supporter Access")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.gold)
                Text("Thank you for supporting Tech Flow Runner from the beginning.")
                    .font(.caption).foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
            case .purchasedIAP:
                Text("Purchased")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.gold)
                Text("Thanks for your support! Runs never cost a life.")
                    .font(.caption).foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
            case .none:
                // Not reachable — this panel only shows when unlimited is active.
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .panel()
    }

    private var restoreButton: some View {
        Button {
            Task { await store.restore() }
        } label: {
            if store.phase == .restoring {
                Label("Restoring…", systemImage: "arrow.clockwise")
            } else {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(NeonButtonStyle(tint: Theme.purple))
        .disabled(store.isBusy)
    }

    /// Purchase disclosure plus the required Terms of Use (Apple's standard
    /// EULA) and Privacy Policy links.
    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text("Unlimited Lives Forever is a one-time \(store.displayPrice) purchase (a non-consumable — it does not auto-renew). Payment is charged to your Apple Account at confirmation of purchase. It never expires and can be restored on any device signed in to the same Apple Account.")
                .font(.caption2)
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Link("Terms of Use (EULA)", destination: TermsOfUse.url)
                Text("·").foregroundStyle(Theme.dim)
                Link("Privacy Policy", destination: PrivacyPolicy.url)
            }
            .font(.caption)
            .tint(Theme.cyan)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.cyan)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
        }
    }

    private var regenText: String {
        if lives.isFull { return "Your lives are full." }
        guard let next = lives.nextLifeDate else { return "Regenerating…" }
        return "Next life in \(LivesFormat.countdown(next.timeIntervalSince(now))) — one every 15 minutes, up to \(LivesManager.maxLives)."
    }
}
