//
//  HUDView.swift
//  Tech Flow Runner
//
//  Top heads-up display: Points, Speed, Best, Bits, Combo, Level, plus active
//  power-up pills and the always-reachable pause button.
//

import SwiftUI
import UIKit

struct HUDView: View {
    let hud: HUDSnapshot
    let onPause: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                stat("POINTS", "\(hud.points)", Theme.cyan)
                stat("SPEED", String(format: "%.1f", hud.speed), Theme.text)
                stat("BEST", "\(hud.best)", Theme.gold)
                Spacer(minLength: 6)
                stat("BITS", "\(hud.bits)", Theme.gold)
                stat("COMBO", String(format: "x%.1f", hud.combo), Theme.pink)
                stat("LEVEL", "\(hud.level)", Theme.purple)

                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.panel.opacity(0.8)))
                        .overlay(Circle().strokeBorder(Theme.cyan.opacity(0.5), lineWidth: 1))
                }
                .accessibilityLabel("Pause")
            }

            if !powerupPills.isEmpty {
                HStack(spacing: 6) {
                    ForEach(powerupPills, id: \.0) { pill in
                        Text(pill.1)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(pill.2))
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.bg.opacity(0.45))
        )
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(color)
                .monospacedDigit()
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.dim)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private var powerupPills: [(String, String, Color)] {
        var pills: [(String, String, Color)] = []
        if hud.shieldActive { pills.append(("shield", "SHIELD", Theme.cyan)) }
        if hud.overclockSeconds > 0 { pills.append(("overclock", "OVERCLOCK \(hud.overclockSeconds)s", Theme.gold)) }
        if hud.magnetSeconds > 0 { pills.append(("magnet", "MAGNET \(hud.magnetSeconds)s", Theme.pink)) }
        if hud.slowmoSeconds > 0 { pills.append(("slowmo", "SLOW-MO \(hud.slowmoSeconds)s", Color(UIColor(hex: 0x75FFD4)))) }
        return pills
    }
}
