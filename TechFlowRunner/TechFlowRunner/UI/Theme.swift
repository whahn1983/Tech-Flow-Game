//
//  Theme.swift
//  Tech Flow Runner
//
//  Shared neon styling helpers for the SwiftUI layer.
//

import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(UIColor(hex: 0x03060F))
    static let panel = Color(UIColor(hex: 0x0A1330))
    static let cyan = Color(UIColor(hex: 0x2EF8FF))
    static let purple = Color(UIColor(hex: 0x8E5CFF))
    static let pink = Color(UIColor(hex: 0xFF5CD1))
    static let gold = Color(UIColor(hex: 0xFFD95C))
    static let danger = Color(UIColor(hex: 0xFF5A7C))
    static let text = Color(UIColor(hex: 0xE9F6FF))
    static let dim = Color(UIColor(hex: 0x8FA6C8))
}

struct NeonButtonStyle: ButtonStyle {
    var tint: Color = Theme.cyan
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(prominent ? Theme.bg : Theme.text)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(prominent ? tint : Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint.opacity(0.8), lineWidth: 1.5)
            )
            .shadow(color: tint.opacity(prominent ? 0.6 : 0.25), radius: 10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.panel.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.cyan.opacity(0.25), lineWidth: 1)
            )
    }
}

extension View {
    func panel() -> some View { modifier(PanelBackground()) }
}
