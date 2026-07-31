//
//  TechFlowRunnerApp.swift
//  Tech Flow Runner
//
//  App entry point. Loads persistence, prepares audio, authenticates Game
//  Center, and shows the main menu. The single AppState/scene is shared across
//  the whole UI.
//

import SwiftUI
import UIKit

@main
struct TechFlowRunnerApp: App {
    // The app delegate reports the orientations currently allowed by
    // OrientationManager (menus: all-but-upside-down; gameplay: landscape).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .onAppear { app.onLaunch() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        // Reconcile the lives pool for time elapsed while away so
                        // regenerated lives appear the moment we come forward.
                        app.refreshLives()
                    } else if app.runState == .running {
                        // Auto-pause when the app leaves the foreground mid-run.
                        app.pause()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Color(UIColor(hex: 0x03060F)).ignoresSafeArea()
            switch app.runState {
            case .menu:
                MainMenuView()
                    .transition(.opacity)
            default:
                GameContainerView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.runState)
        // Game Center consent dialog (App Store Review Guideline 5.1.2). Hosted
        // at the root so it can appear over both the menu (first launch) and the
        // game-over overlay (offline player tapping Leaderboard).
        .sheet(isPresented: $app.showGameCenterConsent) {
            GameCenterConsentView(
                onConnect: { app.resolveGameCenterConsent(connect: true) },
                onOffline: { app.resolveGameCenterConsent(connect: false) }
            )
        }
        // Unlimited Lives store / paywall. Hosted at the root so it can appear
        // over both the menu (lives panel / out-of-lives) and the game-over
        // overlay (out-of-lives on Reboot).
        .sheet(isPresented: $app.showLivesStore) {
            LivesStoreView()
        }
    }
}
