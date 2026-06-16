//
//  HapticsManager.swift
//  Tech Flow Runner
//
//  Thin wrapper over UIKit feedback generators for key gameplay events. Honors
//  the global mute/reduced-motion intent loosely — haptics are independent of
//  audio but are skipped when the app requests a quiet experience.
//

import UIKit

final class HapticsManager {
    static let shared = HapticsManager()

    var enabled: Bool = true

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        selection.prepare()
        notification.prepare()
    }

    func jump() { guard enabled else { return }; lightImpact.impactOccurred() }
    func collect() { guard enabled else { return }; selection.selectionChanged() }
    func powerUp() { guard enabled else { return }; mediumImpact.impactOccurred() }
    func hit() { guard enabled else { return }; heavyImpact.impactOccurred() }
    func bossDefeated() { guard enabled else { return }; notification.notificationOccurred(.success) }
}
