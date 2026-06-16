//
//  SkinPickerView.swift
//  Tech Flow Runner
//
//  Grid of unlockable skins with locked/unlocked status and unlock hints, plus
//  the "Skins unlocked: X/6" progress and lifetime stat summary.
//

import SwiftUI
import UIKit

struct SkinPickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("Skins unlocked: \(app.unlockedSkins.count)/\(Skin.allCases.count)")
                        .font(.headline).foregroundStyle(Theme.cyan)
                    Text("Lifetime: \(Int(app.lifetime.distance))m · \(app.lifetime.bits) bits · \(app.lifetime.bossKills) bosses defeated")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Skin.allCases) { skin in
                            skinCard(skin)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Skins")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func skinCard(_ skin: Skin) -> some View {
        let unlocked = app.isUnlocked(skin)
        let selected = app.selectedSkin == skin
        return Button {
            if unlocked { app.selectSkin(skin); dismiss() }
        } label: {
            VStack(spacing: 8) {
                SkinSwatch(skin: skin, locked: !unlocked)
                Text(skin.label).font(.headline).foregroundStyle(Theme.text)
                Text(unlocked ? (selected ? "Selected" : "Tap to equip") : skin.unlockHint)
                    .font(.caption2)
                    .foregroundStyle(unlocked ? (selected ? Theme.gold : Theme.dim) : Theme.danger)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.panel.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? Theme.gold : Theme.cyan.opacity(0.25),
                                  lineWidth: selected ? 2 : 1)
            )
            .opacity(unlocked ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel("\(skin.label), \(unlocked ? "unlocked" : "locked, " + skin.unlockHint)")
    }
}

/// Shows the actual in-game player art for a skin (the same graphic seen during
/// a run), rendered from the SpriteKit `SkinRenderer` via `SkinIconRenderer`.
/// Locked skins are dimmed behind a lock badge so the silhouette still teases
/// what's coming without reading as "equipped".
private struct SkinSwatch: View {
    let skin: Skin
    let locked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.bg.opacity(0.6))
                .frame(width: 54, height: 66)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(skin.swiftUIColors.first?.opacity(0.4) ?? .clear, lineWidth: 1)
                )
                .shadow(color: skin.swiftUIColors.first?.opacity(0.5) ?? .clear, radius: 8)

            if let art = SkinIconRenderer.image(for: skin) {
                Image(uiImage: art)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 54)
                    .opacity(locked ? 0.35 : 1)
                    .saturation(locked ? 0.2 : 1)
            } else {
                // Fallback to the gradient swatch if texture rendering is
                // unavailable (e.g. SwiftUI previews without a GPU context).
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: skin.swiftUIColors,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 54)
                    .opacity(locked ? 0.5 : 1)
            }

            if locked {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 3)
            }
        }
    }
}
