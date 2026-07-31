//
//  LivesView.swift
//  Tech Flow Runner
//
//  Menu-facing lives UI: the panel that shows the current pool and the regen
//  countdown (with a shortcut into the Unlimited Lives store), plus a compact
//  badge reused on the game-over overlay.
//

import SwiftUI

/// Formats a countdown interval as `M:SS` (or `H:MM:SS` past an hour).
enum LivesFormat {
    static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

/// The lives panel shown on the main menu. Ticks once a second so the regen
/// countdown stays live and lives are granted the moment they mature.
struct LivesView: View {
    @ObservedObject private var lives = LivesManager.shared
    /// Invoked when the player taps the Unlimited Lives call-to-action.
    var onGetUnlimited: () -> Void

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: lives.unlimited ? "infinity" : "heart.fill")
                    .foregroundStyle(lives.unlimited ? Theme.gold : Theme.danger)
                Text(lives.unlimited ? "Unlimited Lives" : "Lives")
                    .font(.headline).foregroundStyle(Theme.text)
                Spacer()
                if lives.unlimited {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.gold)
                } else {
                    Text("\(lives.lives) / \(LivesManager.maxLives)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.cyan)
                        .monospacedDigit()
                }
            }

            if !lives.unlimited {
                Text(regenText)
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onGetUnlimited) {
                    Label("Unlimited Lives Forever", systemImage: "infinity")
                }
                .buttonStyle(NeonButtonStyle(tint: Theme.gold))
                .accessibilityHint("Opens the Unlimited Lives store")
            }
        }
        .panel()
        .onAppear { lives.refresh() }
        .onReceive(timer) { date in
            now = date
            lives.refresh()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var regenText: String {
        if lives.isFull { return "Lives full" }
        guard let next = lives.nextLifeDate else { return "Regenerating…" }
        return "Next life in \(LivesFormat.countdown(next.timeIntervalSince(now)))  ·  one every 15 min"
    }

    private var accessibilityLabel: String {
        if lives.unlimited { return "Unlimited lives unlocked" }
        if lives.isFull { return "Lives \(lives.lives) of \(LivesManager.maxLives), full" }
        guard let next = lives.nextLifeDate else {
            return "Lives \(lives.lives) of \(LivesManager.maxLives)"
        }
        return "Lives \(lives.lives) of \(LivesManager.maxLives). Next life in \(LivesFormat.countdown(next.timeIntervalSince(now)))"
    }
}

/// Compact lives indicator ("∞" or "N / 10") reused on overlays.
struct LivesBadge: View {
    @ObservedObject private var lives = LivesManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: lives.unlimited ? "infinity" : "heart.fill")
                .foregroundStyle(lives.unlimited ? Theme.gold : Theme.danger)
            Text(lives.unlimited ? "Unlimited" : "\(lives.lives) / \(LivesManager.maxLives)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lives.unlimited
                            ? "Unlimited lives"
                            : "\(lives.lives) of \(LivesManager.maxLives) lives")
    }
}
