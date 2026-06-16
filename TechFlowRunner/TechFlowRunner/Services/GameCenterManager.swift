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
//  ───────────────────────────────────────────────────────────────────────────
//  ACHIEVEMENTS
//  ───────────────────────────────────────────────────────────────────────────
//  Create one achievement per skin (My Apps → your app → Features → Game Center
//  → Achievements) with these EXACT IDs. Each is reported as 100% complete the
//  first time the matching skin unlocks. IDs are defined on `Skin.achievementID`.
//
//    techflow.skin.pulse     Pulse    (welcome — granted on first play)
//    techflow.skin.sunset    Sunset   (lifetime distance 25,000m)
//    techflow.skin.matrix    Matrix   (lifetime distance 75,000m)
//    techflow.skin.bitlord   Bit Lord (1,500 lifetime bits)
//    techflow.skin.plasma    Plasma   (lifetime distance 175,000m)
//    techflow.skin.bossbane  Bossbane (defeat 20 bosses)
//
//  Until these exist, submissions/achievement reports fail silently (logged in
//  DEBUG) but the game continues to work and saves local bests.
//

import GameKit
import SwiftUI

/// Single source of truth for every Game Center leaderboard ID.
///
/// IMPORTANT: each value below MUST exactly match the Leaderboard ID configured
/// in App Store Connect (My Apps → your app → Features → Game Center →
/// Leaderboards). A mismatch (typo, wrong case, stray whitespace) makes both
/// submission and presentation fail at runtime. Keep this list and App Store
/// Connect in lockstep.
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

/// Coarse authentication state, surfaced to the UI and the debug panel.
enum GameCenterAuthState: CustomStringConvertible {
    case authenticating
    case signedIn
    case notSignedIn
    case failed

    var description: String {
        switch self {
        case .authenticating: return "Authenticating"
        case .signedIn: return "Signed in"
        case .notSignedIn: return "Not signed in"
        case .failed: return "Authentication failed"
        }
    }
}

@MainActor
final class GameCenterManager: NSObject, ObservableObject {
    static let shared = GameCenterManager()

    @Published var isAuthenticated = false
    @Published var authState: GameCenterAuthState = .authenticating
    @Published var statusText = "Game Center: signing in…"

    /// Invoked on the main actor each time the local player becomes
    /// authenticated. AppState uses this to (re)sync skin-unlock achievements,
    /// so progress earned before this update — or before sign-in — is credited.
    var onAuthenticated: (() -> Void)?

    private override init() { super.init() }

    /// Emits Game Center diagnostics to the Xcode console. DEBUG builds only, so
    /// none of this leaks into release logs.
    private func log(_ message: String) {
        #if DEBUG
        print("[GameCenter] \(message)")
        #endif
    }

    func authenticate() {
        let localPlayer = GKLocalPlayer.local
        authState = .authenticating
        statusText = "Game Center: signing in…"
        localPlayer.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            Task { @MainActor in
                if let viewController {
                    // Present the Game Center sign-in flow over the app's UI.
                    self.present(viewController)
                    self.isAuthenticated = false
                    self.authState = .notSignedIn
                    self.statusText = "Game Center: sign-in required"
                    self.log("authenticated: false — presenting sign-in UI")
                } else if localPlayer.isAuthenticated {
                    self.isAuthenticated = true
                    self.authState = .signedIn
                    self.statusText = "Game Center: \(localPlayer.alias)"
                    self.log("authenticated: true — player: \(localPlayer.alias) (display name: \(localPlayer.displayName))")
                    self.onAuthenticated?()
                } else {
                    self.isAuthenticated = false
                    if let error {
                        self.authState = .failed
                        self.statusText = "Game Center: authentication failed"
                        self.log("authenticated: false — error: \(error.localizedDescription)")
                    } else {
                        self.authState = .notSignedIn
                        self.statusText = "Game Center: not signed in"
                        self.log("authenticated: false — not signed in")
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
        guard GKLocalPlayer.local.isAuthenticated else {
            log("submit skipped — player not authenticated (score: \(score))")
            return .notAuthenticated
        }

        // Overall board + the active modifier's board, plus the daily board when
        // Daily Seed mode was active.
        var boards = [LeaderboardID.overall, LeaderboardID.forModifier(modifier)]
        if daily { boards.append(LeaderboardID.daily) }

        log("submitting score \(score) to leaderboard IDs: \(boards.joined(separator: ", "))")
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: boards
            )
            log("score submitted: \(score) → \(boards.joined(separator: ", "))")
            return .submitted
        } catch {
            log("submit error: \(error.localizedDescription)")
            return .failed
        }
    }

    // MARK: - Achievements

    /// Reports the given skins' unlock achievements as 100% complete. Game
    /// Center is idempotent: re-reporting an already-earned achievement is a
    /// no-op and shows no banner, so this is safe to call for the full set of
    /// unlocked skins on every authentication and for the delta on each unlock.
    ///
    /// `showBanner` drives whether iOS overlays the "Achievement Unlocked"
    /// toast for any achievement newly crossing 100% in this report.
    func reportSkinAchievements(_ skins: [Skin], showBanner: Bool) async {
        guard !skins.isEmpty else { return }
        guard GKLocalPlayer.local.isAuthenticated else {
            log("achievement report skipped — player not authenticated")
            return
        }
        let achievements = skins.map { skin -> GKAchievement in
            let achievement = GKAchievement(identifier: skin.achievementID)
            achievement.percentComplete = 100
            achievement.showsCompletionBanner = showBanner
            return achievement
        }
        log("reporting achievements: \(skins.map(\.achievementID).joined(separator: ", "))")
        do {
            try await GKAchievement.report(achievements)
        } catch {
            log("achievement report error: \(error.localizedDescription)")
        }
    }

    /// Presents the native Game Center dashboard on the achievements tab.
    func showAchievements() {
        guard GKLocalPlayer.local.isAuthenticated else {
            statusText = "Game Center: sign in to view achievements"
            log("showAchievements requested but player not authenticated — re-triggering sign-in")
            authenticate()
            return
        }
        guard let presenter = Self.topViewController() else {
            log("showAchievements: no view controller to present from")
            return
        }
        guard presenter.presentedViewController == nil else { return }

        log("presenting Game Center achievements")
        let vc = GKGameCenterViewController(state: .achievements)
        vc.gameCenterDelegate = self
        presenter.present(vc, animated: true)
    }

    /// Presents the native Game Center leaderboards UI, which lands on the list
    /// of all the game's boards so the player can browse and switch between them.
    ///
    /// When the local player is NOT authenticated this intentionally does not
    /// present `GKGameCenterViewController`: presenting it unauthenticated shows
    /// a modal stuck on a spinner that never resolves (and logs the
    /// `GameOverlayUI` proxy errors), which reads to the player as a freeze.
    /// Instead we re-trigger the sign-in flow and update the status text.
    func showLeaderboard() {
        guard GKLocalPlayer.local.isAuthenticated else {
            statusText = "Game Center: sign in to view the leaderboard"
            log("showLeaderboard requested but player not authenticated — re-triggering sign-in")
            // Re-trigger sign-in so the player can authenticate, then retry.
            authenticate()
            return
        }
        guard let presenter = Self.topViewController() else {
            log("showLeaderboard: no view controller to present from")
            return
        }
        // Don't stack another modal if one is already presented.
        guard presenter.presentedViewController == nil else { return }

        log("presenting Game Center leaderboards list")
        let vc = GKGameCenterViewController(state: .leaderboards)
        vc.gameCenterDelegate = self
        presenter.present(vc, animated: true)
    }

    #if DEBUG
    /// Human-readable diagnostics for the in-app DEBUG panel in LeaderboardView.
    var debugSummary: String {
        let player = GKLocalPlayer.local
        return """
        Authenticated: \(player.isAuthenticated)
        Player: \(player.isAuthenticated ? player.displayName : "—")
        State: \(authState)
        Overall board: \(LeaderboardID.overall)
        """
    }
    #endif

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
