//
//  OrientationManager.swift
//  Tech Flow Runner
//
//  App-level source of truth for which interface orientations are currently
//  allowed. Menus permit portrait + landscape; an active run is locked to
//  landscape so every player gets the same vertical play area, which keeps the
//  Game Center leaderboard fair.
//
//  The allowed set is consumed by `AppDelegate`'s
//  `application(_:supportedInterfaceOrientationsFor:)` — the authoritative,
//  non-deprecated gate UIKit honours for every window. There is no
//  `UIDevice.setValue(_:forKey:)` hack or visual-only rotation here: rotation
//  is requested through `UIWindowScene.requestGeometryUpdate` (iOS 16+).
//

import SwiftUI
import UIKit

@MainActor
final class OrientationManager: ObservableObject {
    static let shared = OrientationManager()

    /// Orientations allowed for menus and other non-gameplay screens.
    static let menuMask: UIInterfaceOrientationMask = .allButUpsideDown
    /// Orientations allowed during an active run (landscape both ways).
    static let gameplayMask: UIInterfaceOrientationMask = .landscape

    /// The currently allowed orientations. `AppDelegate` reads this for every
    /// `supportedInterfaceOrientationsFor` callback.
    @Published private(set) var mask: UIInterfaceOrientationMask = OrientationManager.menuMask

    private init() {}

    /// Lock the interface to landscape for gameplay and ask the active window
    /// scene to rotate there if it isn't already.
    func lockLandscape() { apply(OrientationManager.gameplayMask) }

    /// Restore the menu orientation behaviour when leaving gameplay.
    func unlock() { apply(OrientationManager.menuMask) }

    private func apply(_ newMask: UIInterfaceOrientationMask) {
        mask = newMask

        guard let scene = Self.activeWindowScene else { return }

        // Tell UIKit the supported set changed before requesting the rotation so
        // it doesn't immediately snap back to the previous orientation.
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()

        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: newMask)
        // The error handler is intentionally a no-op: on devices/contexts where
        // the system declines the rotation (e.g. iPad Split View / Stage
        // Manager) the gameplay UI falls back to the "Rotate Device to
        // Continue" overlay, so a failed request is non-fatal.
        scene.requestGeometryUpdate(prefs) { _ in }
    }

    /// The foreground-active window scene, falling back to any connected scene.
    private static var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

/// Minimal app delegate whose only job is to report the orientations allowed by
/// `OrientationManager`. UIKit intersects this app-level mask with each view
/// controller's `supportedInterfaceOrientations`, so returning `.landscape`
/// here guarantees no window can present portrait gameplay — on iPhone and,
/// where the system permits, on iPad.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // This delegate callback is always delivered on the main thread.
        MainActor.assumeIsolated { OrientationManager.shared.mask }
    }
}
