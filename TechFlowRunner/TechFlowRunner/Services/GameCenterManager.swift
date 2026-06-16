//
//  GameCenterManager.swift
//  Tech Flow Runner
//
//  Owns Game Center authentication, score submission, and leaderboard
//  presentation. Game Center is entirely optional: the game is fully playable
//  offline and unauthenticated, in which case only the local best is saved.
//
//  ───────────────────────────────────────────────────────────────────────────
//  APP STORE CONNECT SETUP
//  ───────────────────────────────────────────────────────────────────────────
//  Create the following leaderboards in App Store Connect (My Apps → your app →
//  Features → Leaderboards) with these EXACT IDs, or edit `LeaderboardID` below
//  to match the IDs you create. All are "Classic" leaderboards, score format
//  "Integer", sort order "High to Low".
//
//    techflow.highscore             Overall best (all modifiers)
//    techflow.highscore.none        No Modifier
//    techflow.highscore.hardcore    Hardcore
//    techflow.highscore.bitrush     Bit Rush
//    techflow.highscore.featherfall Feather Fall
//    techflow.highscore.glasscannon Glass Cannon
//    techflow.daily                 Daily Seed
//
//  Until these exist, submissions will fail silently (logged in DEBUG) but the
//  game continues to work and saves local bests.
//

import GameKit
import SwiftUI

enum LeaderboardID {
    static let overall = "techflow.highscore"
    static let none = "techflow.highscore.none"
    static let hardcore = "techflow.highscore.hardcore"
    static let bitRush = "techflow.highscore.bitrush"
    static let featherFall = "techflow.highscore.featherfall"
    static let glassCannon = "techflow.highscore.glasscannon"
    static let daily = "techflow.daily"

    /// The modifier-specific board for a given run modifier.
    static func forModifier(_ modifier: Modifier) -> String {
        switch modifier {
        case .none: return none
        case .hardcore: return hardcore
        case .bitrush: return bitRush
        case .featherfall: return featherFall
        case .glasscannon: return glassCannon
        }
    }
}

@MainActor
final class GameCenterManager: NSObject, ObservableObject {
    static let shared = GameCenterManager()

    @Published var isAuthenticated = false
    @Published var statusText = "Game Center: signing in…"

    private override init() { super.init() }

    func authenticate() {
        let localPlayer = GKLocalPlayer.local
        localPlayer.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            Task { @MainActor in
                if let viewController {
                    // Present the Game Center sign-in flow over the app's UI.
                    self.present(viewController)
                    self.statusText = "Game Center: sign-in required"
                    self.isAuthenticated = false
                } else if localPlayer.isAuthenticated {
                    self.isAuthenticated = true
                    self.statusText = "Game Center: \(localPlayer.alias)"
                } else {
                    self.isAuthenticated = false
                    if let error {
                        self.statusText = "Game Center unavailable"
                        #if DEBUG
                        print("GameCenter auth error: \(error.localizedDescription)")
                        #endif
                    } else {
                        self.statusText = "Game Center: not signed in"
                    }
                }
            }
        }
    }

    enum SubmissionResult {
        case submitted
        case notAuthenticated
        case failed
    }

    /// Submits the run's score to the overall board, the modifier-specific
    /// board, and (when applicable) the daily board. Returns a coarse result
    /// the game-over overlay can surface to the player.
    func submit(score: Int, modifier: Modifier, daily: Bool) async -> SubmissionResult {
        guard GKLocalPlayer.local.isAuthenticated else { return .notAuthenticated }

        var boards = [LeaderboardID.overall, LeaderboardID.forModifier(modifier)]
        if daily { boards.append(LeaderboardID.daily) }

        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: boards
            )
            return .submitted
        } catch {
            #if DEBUG
            print("GameCenter submit error: \(error.localizedDescription)")
            #endif
            return .failed
        }
    }

    /// Presents the native Game Center leaderboard UI focused on the overall
    /// board.
    ///
    /// When the local player is NOT authenticated this intentionally does not
    /// present `GKGameCenterViewController`: presenting it unauthenticated shows
    /// a modal stuck on a spinner that never resolves (and logs the
    /// `GameOverlayUI` proxy errors), which reads to the player as a freeze.
    /// Instead we re-trigger the sign-in flow and update the status text.
    func showLeaderboard(_ id: String = LeaderboardID.overall) {
        guard GKLocalPlayer.local.isAuthenticated else {
            statusText = "Game Center: sign in to view the leaderboard"
            // Re-trigger sign-in so the player can authenticate, then retry.
            authenticate()
            return
        }
        guard let presenter = Self.topViewController() else {
            #if DEBUG
            print("GameCenter showLeaderboard: no view controller to present from")
            #endif
            return
        }
        // Don't stack another modal if one is already presented.
        guard presenter.presentedViewController == nil else { return }

        let vc = GKGameCenterViewController(leaderboardID: id, playerScope: .global, timeScope: .allTime)
        vc.gameCenterDelegate = self
        presenter.present(vc, animated: true)
    }

    // MARK: - Presentation helper

    private func present(_ viewController: UIViewController) {
        guard let root = Self.topViewController() else { return }
        root.present(viewController, animated: true)
    }

    static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let baseVC = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController

        if let nav = baseVC as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = baseVC as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = baseVC?.presentedViewController {
            return topViewController(base: presented)
        }
        return baseVC
    }
}

extension GameCenterManager: GKGameCenterControllerDelegate {
    nonisolated func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        Task { @MainActor in
            gameCenterViewController.dismiss(animated: true)
        }
    }
}
